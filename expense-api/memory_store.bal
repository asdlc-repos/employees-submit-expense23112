import ballerina/time;
import expense_api.types as ty;

// In-memory implementation of the Store contract. The journey/validation
// behaviour is identical to PostgresStore; the difference is only where rows
// live. Used where no live PostgreSQL is reachable.

public service class MemoryStore {
    *Store;

    private final map<ty:ClaimRow> claims;
    private final map<ty:LineRow> lines;
    private final map<ty:ReceiptRow> receipts;
    private final map<ty:CommentRow> comments;
    private final map<ty:NotificationRow> notifications;
    private final map<ty:ExportRow> exports;
    private final map<string> exportFiles;
    private final map<ty:PersonRow> people;

    public isolated function init() {
        self.claims = {};
        self.lines = {};
        self.receipts = {};
        self.comments = {};
        self.notifications = {};
        self.exports = {};
        self.exportFiles = {};
        self.people = {};
    }

    public isolated function initStore() returns StoreError? {
        foreach PersonSeed person in seedPeople() {
            self.people[person.username] = {username: person.username,
                displayName: person.displayName, email: person.email,
                manager: person?.manager};
        }
        return ();
    }

    public isolated function listPeople() returns ty:PersonRow[]|StoreError {
        return from var entry in self.people.entries()
            let ty:PersonRow person = entry[1]
            order by person.username
            select person;
    }

    public isolated function personByManager(string managerUsername) returns string[]|StoreError {
        return from var entry in self.people.entries()
            let ty:PersonRow person = entry[1]
            where person?.manager == managerUsername
            order by person.username
            select person.username;
    }

    public isolated function createClaim(ty:ClaimRow claim) returns StoreError? {
        self.claims[claim.claimId] = claim.clone();
        return ();
    }

    public isolated function getClaim(string claimId) returns ty:ClaimRow|StoreError {
        ty:ClaimRow? found = self.claims[claimId];
        if found is ty:ClaimRow {
            return found.clone();
        }
        return error StoreNotFoundErr("no such claim");
    }

    public isolated function updateClaim(ty:ClaimRow claim) returns StoreError? {
        self.claims[claim.claimId] = claim.clone();
        return ();
    }

    public isolated function deleteClaim(string claimId) returns StoreError? {
        _ = self.claims.remove(claimId);
        foreach var entry in self.lines.entries() {
            ty:LineRow line = entry[1];
            if line.claimId == claimId {
                _ = self.lines.remove(line.lineId);
                _ = self.receipts.removeIfHasKey(line.lineId);
            }
        }
        return ();
    }

    public isolated function listClaims(string owner, string? status, int 'limit, int offset)
            returns ClaimListResult|StoreError {
        ty:ClaimRow[] matching = from var entry in self.claims.entries()
            let ty:ClaimRow claim = entry[1]
            where claim.claimant == owner && (status is () || claim.status == status)
            order by claim.createdAt descending
            select claim;
        return self.pageOf(matching, 'limit, offset);
    }

    public isolated function listClaimsByClaimants(string[] claimants, string? status, int 'limit, int offset)
            returns ClaimListResult|StoreError {
        ty:ClaimRow[] matching = from var entry in self.claims.entries()
            let ty:ClaimRow claim = entry[1]
            where claimants.indexOf(claim.claimant) !is () && (status is () || claim.status == status)
            order by claim.createdAt descending
            select claim;
        return self.pageOf(matching, 'limit, offset);
    }

    public isolated function listClaimsForFinance(string? status, string? claimant, int 'limit, int offset)
            returns ClaimListResult|StoreError {
        string effectiveStatus = status is () ? "awaiting-finance" : status;
        ty:ClaimRow[] matching = from var entry in self.claims.entries()
            let ty:ClaimRow claim = entry[1]
            where claim.status == effectiveStatus && (claimant is () || claim.claimant == claimant)
            order by claim.createdAt descending
            select claim;
        return self.pageOf(matching, 'limit, offset);
    }

    public isolated function listClaimsForExport() returns ty:ClaimRow[]|StoreError {
        return from var entry in self.claims.entries()
            let ty:ClaimRow claim = entry[1]
            where claim.status == "ready-for-export"
            order by claim.claimId
            select claim.clone();
    }

    public isolated function createLine(ty:LineRow line) returns StoreError? {
        self.lines[line.lineId] = line.clone();
        return ();
    }

    public isolated function getLine(string claimId, string lineId) returns ty:LineRow|StoreError {
        ty:LineRow? found = self.lines[lineId];
        if found is ty:LineRow && found.claimId == claimId {
            return found.clone();
        }
        return error StoreNotFoundErr("no such line");
    }

    public isolated function getLineById(string lineId) returns ty:LineRow|StoreError {
        ty:LineRow? found = self.lines[lineId];
        if found is ty:LineRow {
            return found.clone();
        }
        return error StoreNotFoundErr("no such line");
    }

    public isolated function updateLine(ty:LineRow line) returns StoreError? {
        self.lines[line.lineId] = line.clone();
        return ();
    }

    public isolated function deleteLine(string claimId, string lineId) returns StoreError? {
        _ = self.lines.remove(lineId);
        _ = self.receipts.removeIfHasKey(lineId);
        return ();
    }

    public isolated function listLines(string claimId) returns ty:LineRow[]|StoreError {
        return from var entry in self.lines.entries()
            let ty:LineRow line = entry[1]
            where line.claimId == claimId
            order by line.lineId
            select line.clone();
    }

    public isolated function attachReceipt(ty:ReceiptRow receipt) returns StoreError? {
        self.receipts[receipt.lineId] = receipt.clone();
        return ();
    }

    public isolated function getReceiptByLine(string lineId) returns ty:ReceiptRow|StoreError {
        ty:ReceiptRow? found = self.receipts[lineId];
        if found is ty:ReceiptRow {
            return found.clone();
        }
        return error StoreNotFoundErr("no such receipt");
    }

    public isolated function getReceipt(string receiptId) returns ty:ReceiptRow|StoreError {
        foreach var entry in self.receipts.entries() {
            ty:ReceiptRow receipt = entry[1];
            if receipt.receiptId == receiptId {
                return receipt.clone();
            }
        }
        return error StoreNotFoundErr("no such receipt");
    }

    public isolated function replaceReceipt(ty:ReceiptRow receipt) returns StoreError? {
        self.receipts[receipt.lineId] = receipt.clone();
        return ();
    }

    public isolated function deleteReceiptsForLine(string lineId) returns StoreError? {
        _ = self.receipts.remove(lineId);
        return ();
    }

    public isolated function listReceiptsForClaim(string claimId) returns ty:ReceiptRow[]|StoreError {
        ty:ReceiptRow[] found = [];
        foreach var entry in self.lines.entries() {
            ty:LineRow line = entry[1];
            if line.claimId == claimId {
                ty:ReceiptRow? receipt = self.receipts[line.lineId];
                if receipt is ty:ReceiptRow {
                    found.push(receipt.clone());
                }
            }
        }
        return found;
    }

    public isolated function addComment(ty:CommentRow comment) returns StoreError? {
        self.comments[comment.commentId] = comment.clone();
        return ();
    }

    public isolated function listComments(string claimId) returns ty:CommentRow[]|StoreError {
        return from var entry in self.comments.entries()
            let ty:CommentRow comment = entry[1]
            where comment.claimId == claimId
            order by comment.createdAt
            select comment.clone();
    }

    public isolated function addNotification(ty:NotificationRow notification) returns StoreError? {
        self.notifications[notification.notificationId] = notification.clone();
        return ();
    }

    public isolated function listNotifications(string recipient, int 'limit, int offset)
            returns (ty:NotificationRow[] & readonly)|StoreError {
        ty:NotificationRow[] matching = from var entry in self.notifications.entries()
            let ty:NotificationRow notification = entry[1]
            where notification.recipient == recipient
            order by notification.sentAt descending
            select notification;
        return sliceNotificationRows(matching, 'limit, offset).cloneReadOnly();
    }

    public isolated function createExport(ty:ExportRow exportRun) returns StoreError? {
        self.exports[exportRun.exportId] = exportRun.clone();
        return ();
    }

    public isolated function getExport(string exportId) returns ty:ExportRow|StoreError {
        ty:ExportRow? found = self.exports[exportId];
        if found is ty:ExportRow {
            return found.clone();
        }
        return error StoreNotFoundErr("no such export");
    }

    public isolated function listExports(int 'limit, int offset) returns (ty:ExportRow[] & readonly)|StoreError {
        ty:ExportRow[] matching = from var entry in self.exports.entries()
            let ty:ExportRow exportRow = entry[1]
            order by exportRow.exportedAt descending
            select exportRow;
        return sliceExportRows(matching, 'limit, offset).cloneReadOnly();
    }

    public isolated function markClaimsExported(ty:ClaimRow[] claims, string exportId, time:Utc exportedAt)
            returns StoreError? {
        foreach ty:ClaimRow claim in claims {
            ty:ClaimRow? stored = self.claims[claim.claimId];
            if stored is ty:ClaimRow {
                ty:ClaimRow updated = stored.clone();
                updated.status = "exported";
                updated.exportedAt = exportedAt;
                updated.exportId = exportId;
                updated.updatedAt = exportedAt;
                self.claims[claim.claimId] = updated;
            }
        }
        return ();
    }

    public isolated function saveExportFile(string exportId, string content) returns StoreError? {
        self.exportFiles[exportId] = content;
        return ();
    }

    public isolated function readExportFile(string exportId) returns string|StoreError {
        string? content = self.exportFiles[exportId];
        if content is string {
            return content;
        }
        return error StoreNotFoundErr("no such export");
    }

    public isolated function close() returns StoreError? {
        return ();
    }

    private isolated function pageOf(ty:ClaimRow[] matching, int 'limit, int offset)
            returns ClaimListResult {
        return {claims: sliceClaimRows(matching, 'limit, offset), count: matching.length()};
    }
};

isolated function sliceClaimRows(ty:ClaimRow[] rows, int 'limit, int offset) returns ty:ClaimRow[] {
    [int, int] bounds = sliceBounds(rows.length(), 'limit, offset);
    return rows.slice(bounds[0], bounds[1]);
}

isolated function sliceNotificationRows(ty:NotificationRow[] rows, int 'limit, int offset) returns ty:NotificationRow[] {
    [int, int] bounds = sliceBounds(rows.length(), 'limit, offset);
    return rows.slice(bounds[0], bounds[1]);
}

isolated function sliceExportRows(ty:ExportRow[] rows, int 'limit, int offset) returns ty:ExportRow[] {
    [int, int] bounds = sliceBounds(rows.length(), 'limit, offset);
    return rows.slice(bounds[0], bounds[1]);
}

isolated function sliceBounds(int size, int 'limit, int offset) returns [int, int] {
    int beginAt = offset;
    if beginAt > size {
        beginAt = size;
    }
    int endAt = beginAt + 'limit;
    if endAt > size {
        endAt = size;
    }
    return [beginAt, endAt];
}
