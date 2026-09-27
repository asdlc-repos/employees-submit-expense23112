import ballerina/time;
import ballerina/test;
import expense_api.types as ty;

// Pure domain logic: totals, the status journey and validation, with
// in-memory structures behind the store interface — no live PostgreSQL.

@test:Config {}
function testTotalIsSumOfLineAmounts() {
    decimal total = computeTotal([12.50d, 30.00d, 7.25d]);
    test:assertEquals(total, 49.75d);
}

@test:Config {}
function testTotalOfNoLinesIsZero() {
    test:assertEquals(computeTotal([]), 0d);
}

@test:Config {}
function testEditableOnlyWhileDraftOrReturned() {
    test:assertTrue(isEditable("draft"));
    test:assertTrue(isEditable("returned"));
    test:assertFalse(isEditable("awaiting-manager"));
    test:assertFalse(isEditable("awaiting-finance"));
    test:assertFalse(isEditable("ready-for-export"));
    test:assertFalse(isEditable("exported"));
}

@test:Config {}
function testSubmittableOnlyWhileDraftOrReturned() {
    test:assertTrue(isSubmittable("draft"));
    test:assertTrue(isSubmittable("returned"));
    test:assertFalse(isSubmittable("awaiting-manager"));
    test:assertFalse(isSubmittable("awaiting-finance"));
    test:assertFalse(isSubmittable("ready-for-export"));
    test:assertFalse(isSubmittable("exported"));
}

@test:Config {}
function testSubmissionRefusedWithNoLines() {
    string? blocker = submissionBlocker(0, 0);
    test:assertTrue(blocker is string, msg = "a claim with no lines must be refused");
}

@test:Config {}
function testSubmissionRefusedWhenALineLacksAReceipt() {
    string? blocker = submissionBlocker(2, 1);
    test:assertTrue(blocker is string, msg = "a line missing its receipt must be refused");
}

@test:Config {}
function testSubmissionAllowedWhenEveryLineHasAReceipt() {
    string? blocker = submissionBlocker(2, 2);
    test:assertTrue(blocker is (), msg = "a fully receipted claim must submit");
}

@test:Config {}
function testLineValidationAcceptsAGoodLine() {
    string? problem = validateLine("2026-09-01", "travel", 120.00d, "Taxi to airport");
    test:assertTrue(problem is (), msg = problem ?: "expected the line to validate");
}

@test:Config {}
function testLineValidationRejectsBadDates() {
    test:assertTrue(validateLine("2026-13-01", "travel", 10d, "x") is string);
    test:assertTrue(validateLine("01-09-2026", "travel", 10d, "x") is string);
    test:assertTrue(validateLine("", "travel", 10d, "x") is string);
}

@test:Config {}
function testLineValidationRejectsUnknownCategories() {
    test:assertTrue(validateLine("2026-09-01", "groceries", 10d, "x") is string);
}

@test:Config {}
function testLineValidationRejectsNonPositiveAmounts() {
    test:assertTrue(validateLine("2026-09-01", "travel", 0d, "x") is string);
    test:assertTrue(validateLine("2026-09-01", "travel", -5d, "x") is string);
}

@test:Config {}
function testLineValidationRejectsEmptyDescription() {
    test:assertTrue(validateLine("2026-09-01", "travel", 10d, "  ") is string);
}

@test:Config {}
function testSeedPeopleRouteApprovalsToRecordedManagers() {
    PersonSeed[] people = seedPeople();
    map<string?> managers = {};
    foreach PersonSeed person in people {
        managers[person.username] = person?.manager;
    }
    test:assertEquals(managers["test-employee"], "test-manager",
        msg = "the seeded employee must report to the seeded manager");
    test:assertEquals(managers["test-employee-2"], "test-manager");
    test:assertEquals(managers["test-manager"], "test-manager-2");
    test:assertEquals(managers["test-finance-reviewer"], "test-manager-2");
    test:assertTrue(managers["test-manager-2"] is (), msg = "the top of the chain has no manager");
}

@test:Config {}
function testSeedCategoriesAreTheFinanceList() {
    string[] categories = seedCategories();
    test:assertEquals(categories.length(), 5);
    foreach string category in categories {
        test:assertTrue(validCategories().indexOf(category) !is ());
    }
}

@test:Config {}
function testCsvRowsCarryClaimantClaimCategoryTotalsAndAmount() {
    map<decimal> categoryTotals = {"travel": 100d};
    string row = csvRowForClaim("test-employee", "Trip to Colombo", categoryTotals, 145.50d);
    string[] fields = re `,`.split(csvRowForClaim("test-employee", "Trip to Colombo",
        {"travel": 100d}, 145.50d).trim());
    test:assertEquals(fields[0], "test-employee");
    test:assertEquals(fields[1], "Trip to Colombo");
    test:assertEquals(fields[2], "100");
    test:assertEquals(fields[7], "145.50");
    test:assertTrue(row.endsWith("\n"), msg = "a CSV row must end with a newline");
}

@test:Config {}
function testCsvEscapesCommasInTitles() {
    string row = csvRowForClaim("alice", "Dinner, with client", {}, 25d);
    test:assertTrue(row.includes("\"Dinner, with client\""),
        msg = "a comma in a title must be quoted per CSV rules");
}

// ---------- journey over the in-memory store ----------

@test:Config {}
function testFullJourneyDraftToExported() {
    MemoryStore store = new;
    _ = checkpanic store.initStore();
    time:Utc now = time:utcNow();
    ty:ClaimRow claim = {claimId: "CLM-J1", title: "Journey", claimant: "test-employee",
        status: "draft", totalAmount: 0d, manager: (), submittedAt: (), approvedAt: (),
        returnedAt: (), exportedAt: (), createdAt: now, updatedAt: now};
    _ = checkpanic store.createClaim(claim);
    _ = checkpanic store.createLine({lineId: "L1", claimId: "CLM-J1", expenseDate: "2026-09-01",
        category: "travel", amount: 80d, description: "Train ticket"});
    _ = checkpanic store.createLine({lineId: "L2", claimId: "CLM-J1", expenseDate: "2026-09-02",
        category: "meals", amount: 20d, description: "Lunch"});
    _ = checkpanic store.replaceReceipt({receiptId: "R1", lineId: "L1", objectKey: "r1.bin",
        fileName: "train.png", contentType: "image/png", fileSize: 100, uploadedBy: "test-employee"});
    _ = checkpanic store.replaceReceipt({receiptId: "R2", lineId: "L2", objectKey: "r2.bin",
        fileName: "lunch.png", contentType: "image/png", fileSize: 90, uploadedBy: "test-employee"});

    // submit: both lines receipted, so it moves to awaiting-manager
    string? blocker = submissionBlocker(2, 2);
    test:assertTrue(blocker is ());
    claim.status = "awaiting-manager";
    claim.manager = "test-manager";
    claim.submittedAt = now;
    _ = checkpanic store.updateClaim(claim);

    // manager approves -> awaiting-finance
    claim.status = "awaiting-finance";
    _ = checkpanic store.updateClaim(claim);

    // finance approves -> ready-for-export
    claim.status = "ready-for-export";
    _ = checkpanic store.updateClaim(claim);

    // export marks every ready claim exported exactly once
    ty:ClaimRow[]|StoreError ready = store.listClaimsForExport();
    test:assertTrue(ready is ty:ClaimRow[]);
    if ready is ty:ClaimRow[] {
        _ = checkpanic store.markClaimsExported(ready, "EXP-1", now);
        ty:ClaimRow[]|StoreError secondPass = store.listClaimsForExport();
        if secondPass is ty:ClaimRow[] {
            test:assertEquals(secondPass.length(), 0,
                msg = "an exported claim must never enter a second export");
        }
        ty:ClaimRow|StoreError exported = store.getClaim("CLM-J1");
        test:assertTrue(exported is ty:ClaimRow && exported.status == "exported");
    }
}

@test:Config {}
function testReturnedClaimIsEditableAndResubmittable() {
    MemoryStore store = new;
    _ = checkpanic store.initStore();
    time:Utc now = time:utcNow();
    ty:ClaimRow claim = {claimId: "CLM-J2", title: "Rework", claimant: "test-employee-2",
        status: "awaiting-manager", totalAmount: 10d, manager: "test-manager",
        submittedAt: now, approvedAt: (), returnedAt: (), exportedAt: (),
        createdAt: now, updatedAt: now};
    _ = checkpanic store.createClaim(claim);
    claim.status = "returned";
    claim.returnedAt = now;
    _ = checkpanic store.updateClaim(claim);
    test:assertTrue(isEditable("returned"));
    test:assertTrue(isSubmittable("returned"));
}

@test:Config {}
function testManagerQueueScopesToDirectReports() {
    MemoryStore store = new;
    _ = checkpanic store.initStore();
    time:Utc now = time:utcNow();
    _ = checkpanic store.createClaim({claimId: "CLM-A", title: "Employee one", claimant: "test-employee",
        status: "awaiting-manager", totalAmount: 10d, manager: "test-manager",
        submittedAt: now, approvedAt: (), returnedAt: (), exportedAt: (), createdAt: now, updatedAt: now});
    _ = checkpanic store.createClaim({claimId: "CLM-B", title: "Employee two", claimant: "test-employee-2",
        status: "awaiting-manager", totalAmount: 20d, manager: "test-manager",
        submittedAt: now, approvedAt: (), returnedAt: (), exportedAt: (), createdAt: now, updatedAt: now});
    _ = checkpanic store.createClaim({claimId: "CLM-C", title: "Not a report", claimant: "test-manager",
        status: "awaiting-manager", totalAmount: 30d, manager: "test-manager-2",
        submittedAt: now, approvedAt: (), returnedAt: (), exportedAt: (), createdAt: now, updatedAt: now});
    string[]|StoreError reports = store.personByManager("test-manager");
    test:assertTrue(reports is string[]);
    if reports is string[] {
        test:assertEquals(reports.length(), 2);
        ClaimListResult|StoreError queue = store.listClaimsByClaimants(reports, "awaiting-manager", 20, 0);
        test:assertTrue(queue is ClaimListResult);
        if queue is ClaimListResult {
            test:assertEquals(queue.count, 2, msg = "only the reports' claims appear in the manager queue");
        }
    }
}

@test:Config {}
function testFinanceQueueDefaultsToAwaitingFinance() {
    MemoryStore store = new;
    _ = checkpanic store.initStore();
    time:Utc now = time:utcNow();
    _ = checkpanic store.createClaim({claimId: "CLM-F1", title: "Ready", claimant: "test-employee",
        status: "awaiting-finance", totalAmount: 10d, manager: "test-manager",
        submittedAt: now, approvedAt: now, returnedAt: (), exportedAt: (), createdAt: now, updatedAt: now});
    _ = checkpanic store.createClaim({claimId: "CLM-F2", title: "Still with manager", claimant: "test-employee",
        status: "awaiting-manager", totalAmount: 20d, manager: "test-manager",
        submittedAt: now, approvedAt: (), returnedAt: (), exportedAt: (), createdAt: now, updatedAt: now});
    ClaimListResult|StoreError queue = store.listClaimsForFinance((), (), 20, 0);
    test:assertTrue(queue is ClaimListResult);
    if queue is ClaimListResult {
        test:assertEquals(queue.count, 1, msg = "the finance queue lists only manager-approved claims");
        if queue.claims.length() == 1 {
            test:assertEquals(queue.claims[0].claimId, "CLM-F1");
        }
    }
}

@test:Config {}
function testNotificationsRecordPerRecipient() {
    MemoryStore store = new;
    _ = checkpanic store.initStore();
    time:Utc now = time:utcNow();
    _ = checkpanic store.addNotification({notificationId: "N1", recipient: "test-manager",
        claimId: "CLM-A", subject: "Claim submitted", body: "please review", sentAt: now});
    _ = checkpanic store.addNotification({notificationId: "N2", recipient: "test-employee",
        claimId: "CLM-A", subject: "Claim approved", body: "approved", sentAt: now});
    ty:NotificationRow[]|StoreError managerRows = store.listNotifications("test-manager", 20, 0);
    test:assertTrue(managerRows is ty:NotificationRow[]);
    if managerRows is ty:NotificationRow[] {
        test:assertEquals(managerRows.length(), 1);
    }
}