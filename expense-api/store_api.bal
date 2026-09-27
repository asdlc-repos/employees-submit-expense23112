import ballerina/time;
import expense_api.types as ty;

// The persistence contract. PostgresStore is the real implementation; the
// in-memory store exists so the journey/validation logic stays testable where
// no live PostgreSQL is available.

public type StoreError distinct error;

public type StoreNotFoundErr distinct StoreError;

public type ClaimListResult record {|
    ty:ClaimRow[] claims;
    int count;
|};

# The persistence surface the service layer talks to.
public type Store object {
    public function initStore() returns StoreError?;

    public function listPeople() returns ty:PersonRow[]|StoreError;

    public function personByManager(string managerUsername) returns string[]|StoreError;

    public function createClaim(ty:ClaimRow claim) returns StoreError?;

    public function getClaim(string claimId) returns ty:ClaimRow|StoreError;

    public function updateClaim(ty:ClaimRow claim) returns StoreError?;

    public function deleteClaim(string claimId) returns StoreError?;

    public function listClaims(string owner, string? status, int 'limit, int offset)
        returns ClaimListResult|StoreError;

    public function listClaimsByClaimants(string[] claimants, string? status, int 'limit, int offset)
        returns ClaimListResult|StoreError;

    public function listClaimsForFinance(string? status, string? claimant, int 'limit, int offset)
        returns ClaimListResult|StoreError;

    public function listClaimsForExport() returns ty:ClaimRow[]|StoreError;

    public function createLine(ty:LineRow line) returns StoreError?;

    public function getLine(string claimId, string lineId) returns ty:LineRow|StoreError;

    public function getLineById(string lineId) returns ty:LineRow|StoreError;

    public function updateLine(ty:LineRow line) returns StoreError?;

    public function deleteLine(string claimId, string lineId) returns StoreError?;

    public function listLines(string claimId) returns ty:LineRow[]|StoreError;

    public function attachReceipt(ty:ReceiptRow receipt) returns StoreError?;

    public function getReceiptByLine(string lineId) returns ty:ReceiptRow|StoreError;

    public function getReceipt(string receiptId) returns ty:ReceiptRow|StoreError;

    public function replaceReceipt(ty:ReceiptRow receipt) returns StoreError?;

    public function deleteReceiptsForLine(string lineId) returns StoreError?;

    public function listReceiptsForClaim(string claimId) returns ty:ReceiptRow[]|StoreError;

    public function addComment(ty:CommentRow comment) returns StoreError?;

    public function listComments(string claimId) returns ty:CommentRow[]|StoreError;

    public function addNotification(ty:NotificationRow notification) returns StoreError?;

    public function listNotifications(string recipient, int 'limit, int offset)
        returns (ty:NotificationRow[] & readonly)|StoreError;

    public function createExport(ty:ExportRow exportRun) returns StoreError?;

    public function getExport(string exportId) returns ty:ExportRow|StoreError;

    public function listExports(int 'limit, int offset) returns (ty:ExportRow[] & readonly)|StoreError;

    public function markClaimsExported(ty:ClaimRow[] claims, string exportId, time:Utc exportedAt)
        returns StoreError?;

    public function saveExportFile(string exportId, string content) returns StoreError?;

    public function readExportFile(string exportId) returns string|StoreError;

    public function close() returns StoreError?;
};