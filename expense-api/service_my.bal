import ballerina/lang.array as la;
import ballerina/http;
import ballerina/io;
import ballerina/time;
import expense_api.types as ty;

// The API surface. Every operation mirrors openapi.yaml exactly: same paths,
// schemas and status codes. The gateway has already enforced the scope; here
// identity comes only from the verified assertion.

listener http:Listener expenseListener = new (9090);

service http:InterceptableService / on expenseListener {
    public function createInterceptors() returns AssertionInterceptor => new;

    // ---------- public ----------

    resource function get health() returns string {
        return "ok";
    }

    resource function get categories() returns string[] {
        return validCategories();
    }

    // ---------- people ----------

    resource function get people(http:RequestContext ctx) returns ty:Person[]|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        ty:PersonRow[]|StoreError people = appStore.listPeople();
        if people is StoreError {
            return error("store failure");
        }
        return from ty:PersonRow person in people
            select {username: person.username, displayName: person.displayName,
                email: person.email, manager: person?.manager};
    }

    // ---------- my notifications ----------

    resource function get me/notifications(http:RequestContext ctx, int 'limit = 20, int offset = 0)
            returns ty:NotificationPage|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        int pageSize = clampLimit('limit);
        ty:NotificationRow[]|StoreError rows = appStore.listNotifications(callerName, pageSize, offset);
        if rows is StoreError {
            return error("store failure");
        }
        [string?, string?] links = pageLinks(rows.length(), pageSize, offset, "/me/notifications");
        return {count: rows.length(),
            next: links[0], previous: links[1],
            data: from ty:NotificationRow row in rows
                select {notificationId: row.notificationId, recipient: row.recipient,
                    subject: row.subject, body: row.body, claimId: row?.claimId,
                    sentAt: time:utcToString(row.sentAt)}};
    }

    // ---------- my claims ----------

    resource function get me/claims(http:RequestContext ctx, string? status = (), int 'limit = 20, int offset = 0)
            returns ty:ClaimPage|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        int pageSize = clampLimit('limit);
        ClaimListResult|StoreError page = appStore.listClaims(callerName, status, pageSize, offset);
        if page is StoreError {
            return error("store failure");
        }
        [string?, string?] links = pageLinks(page.count, pageSize, offset, "/me/claims");
        ty:ExpenseClaim[] data = [];
        foreach ty:ClaimRow claim in page.claims {
            ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
            if wire is ty:ExpenseClaim {
                data.push(wire);
            }
        }
        return {count: page.count, next: links[0], previous: links[1], data: data};
    }

    resource function post me/claims(http:RequestContext ctx, ty:ClaimCreate payload)
            returns http:Created|http:BadRequest|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        if payload.title.trim() == "" {
            return badRequest("title is required");
        }
        time:Utc now = time:utcNow();
        ty:ClaimRow claim = {claimId: freshId("CLM"), title: payload.title,
            claimant: callerName, status: "draft", totalAmount: 0, manager: (),
            submittedAt: (), approvedAt: (), returnedAt: (), exportedAt: (),
            createdAt: now, updatedAt: now};
        StoreError? created = appStore.createClaim(claim);
        if created is StoreError {
            return error("store failure");
        }
        ty:ExpenseClaim wire = toWireClaim(claim, [], [], []);
        return <http:Created>{headers: {location: "/me/claims/" + claim.claimId}, body: wire};
    }

    resource function get me/claims/[string claimId](http:RequestContext ctx)
            returns ty:ExpenseClaim|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.claimant != callerName {
            return notFound("no such claim");
        }
        ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
        if wire is StoreError {
            return error("store failure");
        }
        return wire;
    }

    resource function put me/claims/[string claimId](http:RequestContext ctx, ty:ClaimCreate payload)
            returns ty:ExpenseClaim|http:BadRequest|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        if payload.title.trim() == "" {
            return badRequest("title is required");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.claimant != callerName || !isEditable(claim.status) {
            return notFound("no such editable claim");
        }
        claim.title = payload.title;
        claim.updatedAt = time:utcNow();
        StoreError? updated = appStore.updateClaim(claim);
        if updated is StoreError {
            return error("store failure");
        }
        ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
        if wire is StoreError {
            return error("store failure");
        }
        return wire;
    }

    resource function delete me/claims/[string claimId](http:RequestContext ctx)
            returns http:NoContent|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return http:NO_CONTENT;
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.claimant != callerName || claim.status != "draft" {
            return notFound("no such deletable claim");
        }
        StoreError? deleted = appStore.deleteClaim(claimId);
        if deleted is StoreError {
            return error("store failure");
        }
        return http:NO_CONTENT;
    }

    // ---------- submit ----------

    resource function post me/claims/[string claimId]/submit(http:RequestContext ctx)
            returns ty:ExpenseClaim|http:BadRequest|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.claimant != callerName || !isSubmittable(claim.status) {
            return notFound("no such submittable claim");
        }
        ty:LineRow[]|StoreError lines = appStore.listLines(claimId);
        if lines is StoreError {
            return error("store failure");
        }
        ty:ReceiptRow[]|StoreError receipts = appStore.listReceiptsForClaim(claimId);
        if receipts is StoreError {
            return error("store failure");
        }
        string? blocker = submissionBlocker(lines.length(), receipts.length());
        if blocker is string {
            return badRequest(blocker);
        }
        string? manager = managerOf(callerName);
        if manager is () {
            return badRequest("the claimant has no recorded manager to route this claim to");
        }
        boolean resubmission = claim.status == "returned";
        time:Utc now = time:utcNow();
        claim.status = "awaiting-manager";
        claim.manager = manager;
        claim.submittedAt = now;
        claim.returnedAt = ();
        claim.updatedAt = now;
        StoreError? updated = appStore.updateClaim(claim);
        if updated is StoreError {
            return error("store failure");
        }
        if resubmission {
            notify(manager, "Claim resubmitted", "A returned claim was corrected and resubmitted for your approval: " + claim.title, claimId);
        } else {
            notify(manager, "Claim submitted", "A new claim awaits your approval: " + claim.title, claimId);
        }
        ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
        if wire is StoreError {
            return error("store failure");
        }
        return wire;
    }

    // ---------- lines ----------

    resource function post me/claims/[string claimId]/lines(http:RequestContext ctx, ty:LineCreate payload)
            returns http:Created|http:BadRequest|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        string? validation = validateLine(payload.expenseDate, payload.category, payload.amount, payload.description);
        if validation is string {
            return badRequest(validation);
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such editable claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.claimant != callerName || !isEditable(claim.status) {
            return notFound("no such editable claim");
        }
        ty:LineRow line = {lineId: freshId("LNE"), claimId: claimId,
            expenseDate: payload.expenseDate, category: payload.category.trim(),
            amount: payload.amount, description: payload.description};
        StoreError? added = appStore.createLine(line);
        if added is StoreError {
            return error("store failure");
        }
        StoreError? retotaled = reTotal(claim);
        if retotaled is StoreError {
            return error("store failure");
        }
        return <http:Created>{headers: {location: "/me/claims/" + claimId + "/lines/" + line.lineId},
            body: {lineId: line.lineId, expenseDate: line.expenseDate, category: line.category,
                amount: line.amount, description: line.description}};
    }

    resource function put me/claims/[string claimId]/lines/[string lineId](http:RequestContext ctx, ty:LineCreate payload)
            returns ty:ExpenseLine|http:BadRequest|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        string? validation = validateLine(payload.expenseDate, payload.category, payload.amount, payload.description);
        if validation is string {
            return badRequest(validation);
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such editable claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.claimant != callerName || !isEditable(claim.status) {
            return notFound("no such editable claim");
        }
        ty:LineRow|StoreError line = appStore.getLine(claimId, lineId);
        if line is StoreNotFoundErr {
            return notFound("no such line");
        }
        if line is StoreError {
            return error("store failure");
        }
        line.expenseDate = payload.expenseDate;
        line.category = payload.category.trim();
        line.amount = payload.amount;
        line.description = payload.description;
        StoreError? updated = appStore.updateLine(line);
        if updated is StoreError {
            return error("store failure");
        }
        StoreError? retotaled = reTotal(claim);
        if retotaled is StoreError {
            return error("store failure");
        }
        return {lineId: line.lineId, expenseDate: line.expenseDate, category: line.category,
            amount: line.amount, description: line.description};
    }

    resource function delete me/claims/[string claimId]/lines/[string lineId](http:RequestContext ctx)
            returns http:NoContent|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such editable claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.claimant != callerName || !isEditable(claim.status) {
            return notFound("no such editable claim");
        }
        ty:LineRow|StoreError line = appStore.getLine(claimId, lineId);
        if line is StoreNotFoundErr {
            return http:NO_CONTENT;
        }
        if line is StoreError {
            return error("store failure");
        }
        StoreError? deleted = appStore.deleteLine(claimId, lineId);
        if deleted is StoreError {
            return error("store failure");
        }
        StoreError? retotaled = reTotal(claim);
        if retotaled is StoreError {
            return error("store failure");
        }
        return http:NO_CONTENT;
    }

    // ---------- receipts ----------

    resource function post me/claims/[string claimId]/lines/[string lineId]/receipt(http:RequestContext ctx,
            ty:ReceiptUpload payload)
            returns http:Created|http:BadRequest|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        if payload.fileName.trim() == "" || payload.contentType.trim() == "" || payload.fileSize <= 0
                || payload.content.trim() == "" {
            return badRequest("fileName, contentType, fileSize and content are required");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such editable claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.claimant != callerName || !isEditable(claim.status) {
            return notFound("no such editable claim");
        }
        ty:LineRow|StoreError line = appStore.getLine(claimId, lineId);
        if line is StoreNotFoundErr {
            return notFound("no such line");
        }
        if line is StoreError {
            return error("store failure");
        }
        string receiptId = freshId("RCP");
        string objectKey = receiptId + ".bin";
        byte[] contentBytes = base64Decode(payload.content);
        if contentBytes.length() != payload.fileSize {
            return badRequest("fileSize does not match the decoded content");
        }
        io:Error? written = writeReceiptBytes(objectKey, contentBytes);
        if written is io:Error {
            return error("store failure");
        }
        ty:ReceiptRow receipt = {receiptId: receiptId, lineId: lineId, objectKey: objectKey,
            fileName: payload.fileName, contentType: payload.contentType,
            fileSize: payload.fileSize, uploadedBy: callerName};
        StoreError? attached = appStore.replaceReceipt(receipt);
        if attached is StoreError {
            return error("store failure");
        }
        return <http:Created>{body: {receiptId: receipt.receiptId, fileName: receipt.fileName,
            contentType: receipt.contentType, fileSize: receipt.fileSize}};
    }

    resource function get me/claims/[string claimId]/lines/[string lineId]/receipt(http:RequestContext ctx)
            returns http:Response|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.claimant != callerName {
            return notFound("no such claim");
        }
        ty:ReceiptRow|StoreError receipt = appStore.getReceiptByLine(lineId);
        if receipt is StoreNotFoundErr {
            return notFound("no such receipt");
        }
        if receipt is StoreError {
            return error("store failure");
        }
        byte[]|io:Error content = readReceiptBytes(receipt.objectKey);
        if content is io:Error {
            return notFound("no such receipt");
        }
        http:Response response = new;
        response.setBinaryPayload(content, receipt.contentType);
        return response;
    }

    // ---------- manager queue ----------

    resource function get me/reports/claims(http:RequestContext ctx, string? status = (), int 'limit = 20, int offset = 0)
            returns ty:ClaimPage|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        int pageSize = clampLimit('limit);
        string[]|StoreError reports = appStore.personByManager(callerName);
        if reports is StoreError {
            return error("store failure");
        }
        ClaimListResult|StoreError page = appStore.listClaimsByClaimants(reports, status, pageSize, offset);
        if page is StoreError {
            return error("store failure");
        }
        [string?, string?] links = pageLinks(page.count, pageSize, offset, "/me/reports/claims");
        ty:ExpenseClaim[] data = [];
        foreach ty:ClaimRow claim in page.claims {
            ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
            if wire is ty:ExpenseClaim {
                data.push(wire);
            }
        }
        return {count: page.count, next: links[0], previous: links[1], data: data};
    }

    resource function get me/reports/claims/[string claimId](http:RequestContext ctx)
            returns ty:ExpenseClaim|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim?.manager != callerName {
            return notFound("no such claim of the caller's reports");
        }
        ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
        if wire is StoreError {
            return error("store failure");
        }
        return wire;
    }

    resource function get me/reports/receipts/[string receiptId](http:RequestContext ctx)
            returns http:Response|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ReceiptRow|StoreError receipt = appStore.getReceipt(receiptId);
        if receipt is StoreNotFoundErr {
            return notFound("no such receipt");
        }
        if receipt is StoreError {
            return error("store failure");
        }
        ty:ClaimRow|StoreError claim = claimOfLine(receipt.lineId);
        if claim is StoreNotFoundErr {
            return notFound("no such receipt on a claim of the caller's reports");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim?.manager != callerName {
            return notFound("no such receipt on a claim of the caller's reports");
        }
        byte[]|io:Error content = readReceiptBytes(receipt.objectKey);
        if content is io:Error {
            return notFound("no such receipt");
        }
        http:Response response = new;
        response.setBinaryPayload(content, receipt.contentType);
        return response;
    }

    resource function post me/reports/claims/[string claimId]/approve(http:RequestContext ctx, ty:ReviewApproval? payload)
            returns ty:ExpenseClaim|http:NotFound|http:Conflict|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim?.manager != callerName {
            return notFound("no such claim awaiting the caller");
        }
        if claim.status != "awaiting-manager" {
            return 'conflict("the claim is not awaiting the caller's approval");
        }
        time:Utc now = time:utcNow();
        claim.status = "awaiting-finance";
        claim.approvedAt = now;
        claim.updatedAt = now;
        StoreError? updated = appStore.updateClaim(claim);
        if updated is StoreError {
            return error("store failure");
        }
        notify(claim.claimant, "Claim approved by manager",
            "Your claim was approved by your manager and now awaits finance review: " + claim.title, claimId);
        ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
        if wire is StoreError {
            return error("store failure");
        }
        return wire;
    }

    resource function post me/reports/claims/[string claimId]/'return(http:RequestContext ctx, ty:ReviewDecision payload)
            returns ty:ExpenseClaim|http:BadRequest|http:NotFound|http:Conflict|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        if payload.comment.trim() == "" {
            return badRequest("a return comment is required");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim?.manager != callerName {
            return notFound("no such claim awaiting the caller");
        }
        if claim.status != "awaiting-manager" {
            return 'conflict("the claim is not awaiting the caller's approval");
        }
        time:Utc now = time:utcNow();
        claim.status = "returned";
        claim.returnedAt = now;
        claim.updatedAt = now;
        StoreError? updated = appStore.updateClaim(claim);
        if updated is StoreError {
            return error("store failure");
        }
        StoreError? commented = appStore.addComment({commentId: freshId("CMT"), claimId: claimId,
            author: callerName, stage: "manager", body: payload.comment, createdAt: now});
        if commented is StoreError {
            return error("store failure");
        }
        notify(claim.claimant, "Claim returned by manager",
            "Your claim was returned by your manager: " + payload.comment, claimId);
        ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
        if wire is StoreError {
            return error("store failure");
        }
        return wire;
    }

    // ---------- finance queue ----------

    resource function get claims(http:RequestContext ctx, string? status = (), string? claimant = (),
            int 'limit = 20, int offset = 0)
            returns ty:ClaimPage|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        _ = caller;
        int pageSize = clampLimit('limit);
        ClaimListResult|StoreError page = appStore.listClaimsForFinance(status, claimant, pageSize, offset);
        if page is StoreError {
            return error("store failure");
        }
        [string?, string?] links = pageLinks(page.count, pageSize, offset, "/claims");
        ty:ExpenseClaim[] data = [];
        foreach ty:ClaimRow claim in page.claims {
            ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
            if wire is ty:ExpenseClaim {
                data.push(wire);
            }
        }
        return {count: page.count, next: links[0], previous: links[1], data: data};
    }

    resource function get claims/[string claimId](http:RequestContext ctx)
            returns ty:ExpenseClaim|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        _ = caller;
        return loadWireClaim(claimId);
    }

    resource function post claims/[string claimId]/approve(http:RequestContext ctx, ty:ReviewApproval? payload)
            returns ty:ExpenseClaim|http:NotFound|http:Conflict|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.status != "awaiting-finance" {
            return 'conflict("the claim is not awaiting finance review");
        }
        time:Utc now = time:utcNow();
        claim.status = "ready-for-export";
        claim.updatedAt = now;
        StoreError? updated = appStore.updateClaim(claim);
        if updated is StoreError {
            return error("store failure");
        }
        notify(claim.claimant, "Claim approved for export",
            "Your claim was approved by finance and is queued for payroll export: " + claim.title, claimId);
        ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
        if wire is StoreError {
            return error("store failure");
        }
        return wire;
    }

    resource function post claims/[string claimId]/'return(http:RequestContext ctx, ty:ReviewDecision payload)
            returns ty:ExpenseClaim|http:BadRequest|http:NotFound|http:Conflict|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        if payload.comment.trim() == "" {
            return badRequest("a return comment is required");
        }
        ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
        if claim is StoreNotFoundErr {
            return notFound("no such claim");
        }
        if claim is StoreError {
            return error("store failure");
        }
        if claim.status != "awaiting-finance" {
            return 'conflict("the claim is not awaiting finance review");
        }
        time:Utc now = time:utcNow();
        claim.status = "returned";
        claim.returnedAt = now;
        claim.updatedAt = now;
        StoreError? updated = appStore.updateClaim(claim);
        if updated is StoreError {
            return error("store failure");
        }
        StoreError? commented = appStore.addComment({commentId: freshId("CMT"), claimId: claimId,
            author: callerName, stage: "finance", body: payload.comment, createdAt: now});
        if commented is StoreError {
            return error("store failure");
        }
        notify(claim.claimant, "Claim returned by finance",
            "Your claim was returned by finance: " + payload.comment, claimId);
        ty:ExpenseClaim|StoreError wire = loadWireClaimFromRow(claim);
        if wire is StoreError {
            return error("store failure");
        }
        return wire;
    }

    resource function get claims/receipts/[string receiptId](http:RequestContext ctx)
            returns http:Response|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        _ = caller;
        ty:ReceiptRow|StoreError receipt = appStore.getReceipt(receiptId);
        if receipt is StoreNotFoundErr {
            return notFound("no such receipt");
        }
        if receipt is StoreError {
            return error("store failure");
        }
        byte[]|io:Error content = readReceiptBytes(receipt.objectKey);
        if content is io:Error {
            return notFound("no such receipt");
        }
        http:Response response = new;
        response.setBinaryPayload(content, receipt.contentType);
        return response;
    }

    // ---------- payroll export ----------

    resource function post claims/exports(http:RequestContext ctx)
            returns ty:ExportRecord|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        string|http:InternalServerError callerName = requireCallerUsername(caller);
        if callerName is http:InternalServerError {
            return error("the gateway assertion carries no username");
        }
        ty:ClaimRow[]|StoreError readyClaims = appStore.listClaimsForExport();
        if readyClaims is StoreError {
            return error("store failure");
        }
        time:Utc now = time:utcNow();
        string exportId = freshId("EXP");
        decimal grandTotal = computeTotal(from ty:ClaimRow claim in readyClaims select claim.totalAmount);
        string csv = csvHeader();
        foreach ty:ClaimRow claim in readyClaims {
            ty:LineRow[]|StoreError lines = appStore.listLines(claim.claimId);
            if lines is StoreError {
                return error("store failure");
            }
            map<decimal> categoryTotals = {};
            foreach ty:LineRow line in lines {
                decimal current = categoryTotals[line.category] ?: 0;
                categoryTotals[line.category] = current + line.amount;
            }
            csv += csvRowForClaim(claim.claimant, claim.title, categoryTotals, claim.totalAmount);
        }
        ty:ExportRow exportRun = {exportId: exportId, exportedBy: callerName, exportedAt: now,
            fileFormat: "CSV", claimCount: readyClaims.length(), totalAmount: grandTotal};
        StoreError? created = appStore.createExport(exportRun);
        if created is StoreError {
            return error("store failure");
        }
        StoreError? saved = appStore.saveExportFile(exportId, csv);
        if saved is StoreError {
            return error("store failure");
        }
        StoreError? marked = appStore.markClaimsExported(readyClaims, exportId, now);
        if marked is StoreError {
            return error("store failure");
        }
        foreach ty:ClaimRow claim in readyClaims {
            notify(claim.claimant, "Claim exported to payroll",
                "Your claim was included in payroll export " + exportId + ": " + claim.title, claim.claimId);
        }
        return {exportId: exportRun.exportId, exportedBy: exportRun.exportedBy,
            exportedAt: time:utcToString(exportRun.exportedAt), fileFormat: exportRun.fileFormat,
            claimCount: exportRun.claimCount, totalAmount: exportRun.totalAmount};
    }

    resource function get claims/exports(http:RequestContext ctx, int 'limit = 20, int offset = 0)
            returns ty:ExportPage|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        _ = caller;
        int pageSize = clampLimit('limit);
        ty:ExportRow[]|StoreError rows = appStore.listExports(pageSize, offset);
        if rows is StoreError {
            return error("store failure");
        }
        [string?, string?] links = pageLinks(rows.length(), pageSize, offset, "/claims/exports");
        return {count: rows.length(), next: links[0], previous: links[1],
            data: from ty:ExportRow row in rows
                select {exportId: row.exportId, exportedBy: row.exportedBy,
                    exportedAt: time:utcToString(row.exportedAt), fileFormat: row.fileFormat,
                    claimCount: row.claimCount, totalAmount: row.totalAmount}};
    }

    resource function get claims/exports/[string exportId](http:RequestContext ctx)
            returns http:Response|http:NotFound|http:Unauthorized|error {
        GatewayCaller|http:Unauthorized caller = requireGatewayCaller(ctx);
        if caller is http:Unauthorized {
            return caller;
        }
        _ = caller;
        string|StoreError content = appStore.readExportFile(exportId);
        if content is StoreNotFoundErr {
            return notFound("no such export");
        }
        if content is StoreError {
            return error("store failure");
        }
        http:Response response = new;
        response.setPayload(content, "text/csv");
        return response;
    }
}

// ---------- helpers used across the service ----------

function badRequest(string message) returns http:BadRequest {
    return <http:BadRequest>{body: {code: 400, message: "bad request", description: message}};
}

function notFound(string message) returns http:NotFound {
    return <http:NotFound>{body: {code: 404, message: "not found", description: message}};
}

function 'conflict(string message) returns http:Conflict {
    return <http:Conflict>{body: {code: 409, message: "conflict", description: message}};
}



function managerOf(string claimant) returns string? {
    ty:PersonRow[]|StoreError people = appStore.listPeople();
    if people is StoreError {
        return ();
    }
    foreach ty:PersonRow person in people {
        if person.username == claimant {
            return person?.manager;
        }
    }
    return ();
}

function reTotal(ty:ClaimRow claim) returns StoreError? {
    ty:LineRow[]|StoreError lines = appStore.listLines(claim.claimId);
    if lines is StoreError {
        return lines;
    }
    claim.totalAmount = computeTotal(from ty:LineRow line in lines select line.amount);
    claim.updatedAt = time:utcNow();
    return appStore.updateClaim(claim);
}

function base64Decode(string content) returns byte[] {
    string cleaned = re `\s`.replaceAll(content, "");
    byte[]|error decoded = la:fromBase64(cleaned);
    if decoded is byte[] {
        return decoded;
    }
    return cleaned.toBytes().clone();
}

function writeReceiptBytes(string objectKey, byte[] content) returns io:Error? {
    return io:fileWriteBytes(receiptDir + "/" + objectKey, content);
}

function readReceiptBytes(string objectKey) returns byte[]|io:Error {
    return io:fileReadBytes(receiptDir + "/" + objectKey);
}
