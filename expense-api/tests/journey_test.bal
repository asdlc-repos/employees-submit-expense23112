import ballerina/http;
import ballerina/test;

// End-to-end over the real HTTP surface: draft to export, through both review
// gates, exactly as the flows draw them. The service runs on the in-memory
// fallback (no PostgreSQL in this sandbox), which shares the journey logic.

final http:Client journeyClient = checkpanic new ("http://localhost:9090");

function employeeHeader(AssertionKey key, string username) returns map<string|string[]> {
    string assertion = mintAssertion(key, "uuid-" + username, username,
        "openid profile email group ou claims:read claims:write claims:submit");
    string assertionName = key.header;
    map<string|string[]> header = {};
    header[assertionName] = assertion;
    return header;
}

function managerHeader(AssertionKey key) returns map<string|string[]> {
    string assertion = mintAssertion(key, "uuid-test-manager", "test-manager",
        "openid profile email group ou claims:read claims:write claims:submit claims:review claims:approve");
    string assertionName = key.header;
    map<string|string[]> header = {};
    header[assertionName] = assertion;
    return header;
}

function financeHeader(AssertionKey key) returns map<string|string[]> {
    string assertion = mintAssertion(key, "uuid-test-finance-reviewer", "test-finance-reviewer",
        "openid profile email group ou claims:read claims:write claims:submit claims:review-all claims:export");
    string assertionName = key.header;
    map<string|string[]> header = {};
    header[assertionName] = assertion;
    return header;
}

@test:Config {}
function testSubmitRefusedWithoutLines() {
    AssertionKey key = assertionKey();
    map<string|string[]> header = employeeHeader(key, "test-employee");
    json claim = checkpanic journeyClient->post("/me/claims", {title: "No lines yet"},
        headers = header);
    json claimIdRaw = checkpanic claim.claimId;
    string claimId = claimIdRaw.toString();
    json|http:ClientError submitResult = journeyClient->post(
        "/me/claims/" + claimId + "/submit", message = {}, headers = header);
    test:assertTrue(submitResult is http:ClientRequestError,
        msg = "submitting an empty claim must be refused");
    if submitResult is http:ClientRequestError {
        test:assertEquals(submitResult.detail().statusCode, 400,
            msg = "submission with no lines is a 400");
    }
}

@test:Config {}
function testSubmitRefusedWhenALineLacksAReceipt() {
    AssertionKey key = assertionKey();
    map<string|string[]> header = employeeHeader(key, "test-employee");
    json claim = checkpanic journeyClient->post("/me/claims", {title: "Missing receipt"},
        headers = header);
    json claimIdRaw = checkpanic claim.claimId;
    string claimId = claimIdRaw.toString();
    json ignored1 = checkpanic journeyClient->post("/me/claims/" + claimId + "/lines",
        {expenseDate: "2026-09-01", category: "travel", amount: 40.0, description: "Taxi"},
        headers = header);
    json|http:ClientError submitResult = journeyClient->post(
        "/me/claims/" + claimId + "/submit", message = {}, headers = header);
    test:assertTrue(submitResult is http:ClientRequestError,
        msg = "submitting with a receiptless line must be refused");
    if submitResult is http:ClientRequestError {
        test:assertEquals(submitResult.detail().statusCode, 400);
    }
}

@test:Config {}
function testFullJourneySubmitApproveExport() {
    AssertionKey key = assertionKey();
    map<string|string[]> employee = employeeHeader(key, "test-employee");
    map<string|string[]> manager = managerHeader(key);
    map<string|string[]> finance = financeHeader(key);

    // build the claim
    json claim = checkpanic journeyClient->post("/me/claims", {title: "Client visit"},
        headers = employee);
    json claimIdRaw = checkpanic claim.claimId;
    string claimId = claimIdRaw.toString();
    json line = checkpanic journeyClient->post("/me/claims/" + claimId + "/lines",
        {expenseDate: "2026-09-02", category: "travel", amount: 80.5, description: "Train"},
        headers = employee);
    json lineIdRaw = checkpanic line.lineId;
    string lineId = lineIdRaw.toString();
    json ignored2 = checkpanic journeyClient->post("/me/claims/" + claimId + "/lines/" + lineId + "/receipt",
        {fileName: "train.png", contentType: "image/png", fileSize: 5,
            content: "dHJhaW4="}, headers = employee);

    // submit -> awaiting-manager
    json submitted = checkpanic journeyClient->post("/me/claims/" + claimId + "/submit",
        message = {}, headers = employee);
    test:assertEquals(submitted.status, "awaiting-manager",
        msg = "a submitted claim must await the seeded manager");

    // manager queue sees it; approve -> awaiting-finance
    json queue = checkpanic journeyClient->get("/me/reports/claims", headers = manager);
    json queueCountRaw = checkpanic queue.count;
    int queueCount = <int> queueCountRaw;
    test:assertTrue(queueCount > 0, msg = "the manager queue must list the report's claim");
    json approved = checkpanic journeyClient->post("/me/reports/claims/" + claimId + "/approve",
        message = {}, headers = manager);
    test:assertEquals(approved.status, "awaiting-finance");

    // re-approving a claim already past the gate is a 409
    json|http:ClientError reapprove = journeyClient->post(
        "/me/reports/claims/" + claimId + "/approve", message = {}, headers = manager);
    test:assertTrue(reapprove is http:ClientRequestError,
        msg = "re-approving a claim not awaiting the manager must fail");
    if reapprove is http:ClientRequestError {
        test:assertEquals(reapprove.detail().statusCode, 409);
    }

    // finance queue sees it; approve for export -> ready-for-export
    json financeQueue = checkpanic journeyClient->get("/claims", headers = finance);
    json financeCountRaw = checkpanic financeQueue.count;
    int financeCount = <int> financeCountRaw;
    test:assertTrue(financeCount > 0, msg = "the finance queue must list manager-approved claims");
    json ready = checkpanic journeyClient->post("/claims/" + claimId + "/approve", message = {}, headers = finance);
    test:assertEquals(ready.status, "ready-for-export");

    // export every ready claim
    json exportRun = checkpanic journeyClient->post("/claims/exports", message = {}, headers = finance);
    json exportIdRaw = checkpanic exportRun.exportId;
    string exportId = exportIdRaw.toString();
    json claimCountRaw = checkpanic exportRun.claimCount;
    int claimCount = <int> claimCountRaw;
    test:assertTrue(claimCount >= 1, msg = "the export must include the ready claim");

    // the CSV is one row per claim, downloadable afterwards
    http:Request csvRequest = new;
    csvRequest.setHeader(key.header, mintAssertion(key, "uuid-test-finance-reviewer",
        "test-finance-reviewer", "openid claims:read claims:review-all claims:export"));
    http:Response csvResponse = checkpanic journeyClient->execute("GET",
        "/claims/exports/" + exportId, csvRequest);
    string csv = checkpanic csvResponse.getTextPayload();
    test:assertTrue(csv.includes("test-employee"), msg = "the CSV must carry the claimant");
    test:assertTrue(csv.includes("Client visit"), msg = "the CSV must carry the claim title");

    // the exported claim never enters a second export
    json secondRun = checkpanic journeyClient->post("/claims/exports", message = {}, headers = finance);
    json secondCountRaw = checkpanic secondRun.claimCount;
    int secondCount = <int> secondCountRaw;
    test:assertEquals(secondCount, 0, msg = "an exported claim never enters a second export");

    // the claimant was notified at each step
    json notifications = checkpanic journeyClient->get("/me/notifications", headers = employee);
    json notificationCountRaw = checkpanic notifications.count;
    int notificationCount = <int> notificationCountRaw;
    test:assertTrue(notificationCount >= 3,
        msg = "approval, export and return notices must be recorded for the claimant");
}

@test:Config {}
function testAnotherEmployeeCannotSeeSomeoneElsesClaim() {
    AssertionKey key = assertionKey();
    map<string|string[]> owner = employeeHeader(key, "test-employee");
    map<string|string[]> other = employeeHeader(key, "test-employee-2");
    json claim = checkpanic journeyClient->post("/me/claims", {title: "Someone else's"},
        headers = owner);
    json claimIdRaw = checkpanic claim.claimId;
    string claimId = claimIdRaw.toString();
    json|http:ClientError otherView = journeyClient->get("/me/claims/" + claimId,
        headers = other);
    test:assertTrue(otherView is http:ClientRequestError,
        msg = "another employee's claim must not be visible");
    if otherView is http:ClientRequestError {
        test:assertEquals(otherView.detail().statusCode, 404,
            msg = "a row that is not the caller's is a 404, never a 403");
    }
}

@test:Config {}
function testEditingRefusedAfterSubmission() {
    AssertionKey key = assertionKey();
    map<string|string[]> employee = employeeHeader(key, "test-employee");
    json claim = checkpanic journeyClient->post("/me/claims", {title: "Locked after submit"},
        headers = employee);
    json claimIdRaw = checkpanic claim.claimId;
    string claimId = claimIdRaw.toString();
    json line = checkpanic journeyClient->post("/me/claims/" + claimId + "/lines",
        {expenseDate: "2026-09-03", category: "meals", amount: 15.0, description: "Lunch"},
        headers = employee);
    json lineIdRaw = checkpanic line.lineId;
    string lineId = lineIdRaw.toString();
    json ignored3 = checkpanic journeyClient->post("/me/claims/" + claimId + "/lines/" + lineId + "/receipt",
        {fileName: "lunch.png", contentType: "image/png", fileSize: 5,
            content: "bHVuY2g="}, headers = employee);
    json ignored4 = checkpanic journeyClient->post("/me/claims/" + claimId + "/submit", message = {}, headers = employee);
    json|http:ClientError editResult = journeyClient->put("/me/claims/" + claimId,
        {title: "Should not work"}, headers = employee);
    test:assertTrue(editResult is http:ClientRequestError,
        msg = "editing after submission must be refused");
    if editResult is http:ClientRequestError {
        test:assertEquals(editResult.detail().statusCode, 404,
            msg = "a submitted claim is not editable, so the update is a 404");
    }
}

@test:Config {}
function testReturnedClaimCanBeFixedAndResubmitted() {
    AssertionKey key = assertionKey();
    map<string|string[]> employee = employeeHeader(key, "test-employee");
    map<string|string[]> manager = managerHeader(key);
    json claim = checkpanic journeyClient->post("/me/claims", {title: "Return me"},
        headers = employee);
    json claimIdRaw = checkpanic claim.claimId;
    string claimId = claimIdRaw.toString();
    json line = checkpanic journeyClient->post("/me/claims/" + claimId + "/lines",
        {expenseDate: "2026-09-04", category: "supplies", amount: 25.0, description: "Pens"},
        headers = employee);
    json lineIdRaw = checkpanic line.lineId;
    string lineId = lineIdRaw.toString();
    json ignored5 = checkpanic journeyClient->post("/me/claims/" + claimId + "/lines/" + lineId + "/receipt",
        {fileName: "pens.png", contentType: "image/png", fileSize: 4,
            content: "cGVucw=="}, headers = employee);
    json ignored6 = checkpanic journeyClient->post("/me/claims/" + claimId + "/submit", message = {}, headers = employee);

    // manager returns with a comment -> returned
    json returned = checkpanic journeyClient->post("/me/reports/claims/" + claimId + "/return",
        message = {comment: "Wrong date on the receipt"}, headers = manager);
    test:assertEquals(returned.status, "returned");

    // the claimant edits and resubmits -> back to awaiting-manager
    json|http:ClientError resubmit = journeyClient->post(
        "/me/claims/" + claimId + "/submit", message = {}, headers = employee);
    test:assertTrue(resubmit is json, msg = "a returned claim must be resubmittable");
    if resubmit is json {
        test:assertEquals(resubmit.status, "awaiting-manager",
            msg = "resubmission routes back through the manager gate");
    }
}

@test:Config {}
function testReturnCommentRequired() {
    AssertionKey key = assertionKey();
    map<string|string[]> employee = employeeHeader(key, "test-employee");
    map<string|string[]> manager = managerHeader(key);
    json claim = checkpanic journeyClient->post("/me/claims", {title: "Needs a comment"},
        headers = employee);
    json claimIdRaw = checkpanic claim.claimId;
    string claimId = claimIdRaw.toString();
    json line = checkpanic journeyClient->post("/me/claims/" + claimId + "/lines",
        {expenseDate: "2026-09-05", category: "training", amount: 99.0, description: "Course"},
        headers = employee);
    json lineIdRaw = checkpanic line.lineId;
    string lineId = lineIdRaw.toString();
    json ignored7 = checkpanic journeyClient->post("/me/claims/" + claimId + "/lines/" + lineId + "/receipt",
        {fileName: "course.png", contentType: "image/png", fileSize: 6,
            content: "Y291cnNl"}, headers = employee);
    json ignored8 = checkpanic journeyClient->post("/me/claims/" + claimId + "/submit", message = {}, headers = employee);
    json|http:ClientError returnResult = journeyClient->post(
        "/me/reports/claims/" + claimId + "/return", message = {comment: "  "}, headers = manager);
    test:assertTrue(returnResult is http:ClientRequestError,
        msg = "a return with an empty comment must be refused");
    if returnResult is http:ClientRequestError {
        test:assertEquals(returnResult.detail().statusCode, 400);
    }
}

@test:Config {}
function testPeopleListIsSignedIn() {
    AssertionKey key = assertionKey();
    map<string|string[]> employee = employeeHeader(key, "test-employee");
    json[] people = checkpanic journeyClient->get("/people", headers = employee);
    int peopleCount = people.length();
    test:assertEquals(peopleCount, 5, msg = "the seeded people list has five records");
}