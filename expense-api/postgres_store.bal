import ballerina/io;
import ballerina/log;
import ballerina/time;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;
import ballerina/sql;
import expense_api.types as ty;

// The real store: platform-managed PostgreSQL via the expense-db dependency.
// Receipt bytes stay on disk; the DB stores only the object key and upload
// metadata.

public const string STORE_NOT_FOUND = "store-not-found";

# Migrations run on startup, idempotent. This module owns its schema.
isolated function migrations() returns sql:ParameterizedQuery[] {
    return [
    `CREATE TABLE IF NOT EXISTS people (
        username VARCHAR(64) PRIMARY KEY,
        display_name VARCHAR(128) NOT NULL,
        email VARCHAR(256) NOT NULL,
        manager_username VARCHAR(64) REFERENCES people(username)
    )`,
    `CREATE TABLE IF NOT EXISTS categories (
        name VARCHAR(64) PRIMARY KEY
    )`,
    `CREATE TABLE IF NOT EXISTS claims (
        claim_id VARCHAR(64) PRIMARY KEY,
        title VARCHAR(256) NOT NULL,
        claimant VARCHAR(64) NOT NULL REFERENCES people(username),
        status VARCHAR(32) NOT NULL,
        total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
        manager_username VARCHAR(64) REFERENCES people(username),
        submitted_at TIMESTAMPTZ,
        approved_at TIMESTAMPTZ,
        returned_at TIMESTAMPTZ,
        exported_at TIMESTAMPTZ,
        export_id VARCHAR(64),
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS expense_lines (
        line_id VARCHAR(64) PRIMARY KEY,
        claim_id VARCHAR(64) NOT NULL REFERENCES claims(claim_id) ON DELETE CASCADE,
        expense_date DATE NOT NULL,
        category VARCHAR(64) NOT NULL,
        amount NUMERIC(12,2) NOT NULL,
        description TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS receipts (
        receipt_id VARCHAR(64) PRIMARY KEY,
        line_id VARCHAR(64) UNIQUE NOT NULL REFERENCES expense_lines(line_id) ON DELETE CASCADE,
        object_key VARCHAR(512) NOT NULL,
        file_name VARCHAR(512) NOT NULL,
        content_type VARCHAR(128) NOT NULL,
        file_size INT NOT NULL,
        uploaded_by VARCHAR(64) NOT NULL,
        uploaded_at TIMESTAMPTZ NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS review_comments (
        comment_id VARCHAR(64) PRIMARY KEY,
        claim_id VARCHAR(64) NOT NULL REFERENCES claims(claim_id) ON DELETE CASCADE,
        author_username VARCHAR(64) NOT NULL,
        stage VARCHAR(16) NOT NULL,
        body TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS notifications (
        notification_id VARCHAR(64) PRIMARY KEY,
        recipient_username VARCHAR(64) NOT NULL REFERENCES people(username),
        claim_id VARCHAR(64),
        subject VARCHAR(256) NOT NULL,
        body TEXT NOT NULL,
        sent_at TIMESTAMPTZ NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS exports (
        export_id VARCHAR(64) PRIMARY KEY,
        exported_by VARCHAR(64) NOT NULL,
        exported_at TIMESTAMPTZ NOT NULL,
        file_format VARCHAR(16) NOT NULL,
        claim_count INT NOT NULL,
        total_amount NUMERIC(14,2) NOT NULL,
        file_path VARCHAR(512) NOT NULL
    )`
    ];
}

public service class PostgresStore {
    *Store;

    private postgresql:Client dbClient;
    private string exportDir;

    public isolated function init(postgresql:Client dbClient, string exportDir) {
        self.dbClient = dbClient;
        self.exportDir = exportDir;
    }

    public isolated function initStore() returns StoreError? {
        foreach sql:ParameterizedQuery migration in migrations() {
            sql:ExecutionResult|sql:Error result = self.dbClient->execute(migration);
            if result is sql:Error {
                return error StoreError("migration failed", result);
            }
        }
        return self.seedIfEmpty();
    }

    isolated function seedIfEmpty() returns StoreError? {
        int? existingCount = checkpanic self.dbClient->queryRow(
            `SELECT COUNT(*) FROM people`);
        int peopleCount = existingCount ?: 0;
        if peopleCount > 0 {
            return ();
        }
        foreach PersonSeed person in seedPeople() {
            sql:ExecutionResult|sql:Error inserted = self.dbClient->execute(
                `INSERT INTO people (username, display_name, email, manager_username)
                 VALUES (${person.username}, ${person.displayName}, ${person.email},
                         ${person?.manager})`);
            if inserted is sql:Error {
                return error StoreError("people seed failed", inserted);
            }
        }
        foreach string category in seedCategories() {
            sql:ExecutionResult|sql:Error inserted = self.dbClient->execute(
                `INSERT INTO categories (name) VALUES (${category})
                 ON CONFLICT (name) DO NOTHING`);
            if inserted is sql:Error {
                return error StoreError("category seed failed", inserted);
            }
        }
        log:printInfo("expense-api seeded sample people and categories");
        return ();
    }

    public isolated function listPeople() returns ty:PersonRow[]|StoreError {
        stream<PersonDb, sql:Error?> peopleStream = self.dbClient->query(
            `SELECT username, display_name, email, manager_username FROM people
             ORDER BY username`, PersonDb);
        anydata|StoreError collectedResult = collectTypedRows(PersonDb, peopleStream);
        if collectedResult is StoreError {
            return collectedResult;
        }
        PersonDb[] collected = <PersonDb[]> collectedResult;
        return from PersonDb person in collected
            select {username: person.username, displayName: person.display_name,
                email: person.email, manager: person.manager_username};
    }

    public isolated function personByManager(string managerUsername) returns string[]|StoreError {
        stream<record {| string username; |}, sql:Error?> reportsStream = self.dbClient->query(
            `SELECT username FROM people WHERE manager_username = ${managerUsername}
             ORDER BY username`);
        string[] reports = [];
        var next = reportsStream.next();
        while next !is () {
            if next is sql:Error {
                return error StoreError("reports query failed", next);
            }
            record {| record {| string username; |} value; |} wrapped = next;
            reports.push(wrapped.value.username);
            next = reportsStream.next();
        }
        _ = checkpanic reportsStream.close();
        return reports;
    }

    public isolated function createClaim(ty:ClaimRow claim) returns StoreError? {
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `INSERT INTO claims (claim_id, title, claimant, status, total_amount,
             manager_username, submitted_at, approved_at, returned_at, exported_at,
             export_id, created_at, updated_at)
             VALUES (${claim.claimId}, ${claim.title}, ${claim.claimant}, ${claim.status},
             ${claim.totalAmount}, ${claim?.manager}, ${claim?.submittedAt},
             ${claim?.approvedAt}, ${claim?.returnedAt}, ${claim?.exportedAt},
             ${claim?.exportId}, ${claim.createdAt}, ${claim.updatedAt})`);
        if result is sql:Error {
            return error StoreError("create claim failed", result);
        }
        return ();
    }

    public isolated function getClaim(string claimId) returns ty:ClaimRow|StoreError {
        ClaimDb|sql:Error found = self.dbClient->queryRow(
            `SELECT claim_id, title, claimant, status, total_amount, manager_username,
             submitted_at, approved_at, returned_at, exported_at, export_id,
             created_at, updated_at FROM claims WHERE claim_id = ${claimId}`, ClaimDb);
        if found is sql:Error {
            if found is sql:NoRowsError {
                return error StoreNotFoundErr("not found");
            }
            return error StoreError("get claim failed", found);
        }
        return claimRowFromDb(found);
    }

    public isolated function updateClaim(ty:ClaimRow claim) returns StoreError? {
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `UPDATE claims SET title = ${claim.title}, status = ${claim.status},
             total_amount = ${claim.totalAmount}, manager_username = ${claim?.manager},
             submitted_at = ${claim?.submittedAt}, approved_at = ${claim?.approvedAt},
             returned_at = ${claim?.returnedAt}, exported_at = ${claim?.exportedAt},
             export_id = ${claim?.exportId}, updated_at = ${claim.updatedAt}
             WHERE claim_id = ${claim.claimId}`);
        if result is sql:Error {
            return error StoreError("update claim failed", result);
        }
        return ();
    }

    public isolated function deleteClaim(string claimId) returns StoreError? {
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `DELETE FROM claims WHERE claim_id = ${claimId}`);
        if result is sql:Error {
            return error StoreError("delete claim failed", result);
        }
        return ();
    }

    public isolated function listClaims(string owner, string? status, int 'limit, int offset)
            returns ClaimListResult|StoreError {
        sql:ParameterizedQuery base = `SELECT claim_id, title, claimant, status,
            total_amount, manager_username, submitted_at, approved_at, returned_at,
            exported_at, export_id, created_at, updated_at FROM claims
            WHERE claimant = ${owner}`;
        sql:ParameterizedQuery withStatus = status is string
            ? sql:queryConcat(base, ` AND status = ${status}`)
            : base;
        return self.pageClaims(withStatus, 'limit, offset);
    }

    public isolated function listClaimsByClaimants(string[] claimants, string? status, int 'limit, int offset)
            returns ClaimListResult|StoreError {
        if claimants.length() == 0 {
            return {claims: [], count: 0};
        }
        sql:ParameterizedQuery flat = sql:queryConcat(`SELECT claim_id, title, claimant,
            status, total_amount, manager_username, submitted_at, approved_at,
            returned_at, exported_at, export_id, created_at, updated_at FROM claims
            WHERE claimant IN (`, sql:arrayFlattenQuery(claimants), `)`);
        sql:ParameterizedQuery withStatus = status is string
            ? sql:queryConcat(flat, ` AND status = ${status}`)
            : flat;
        return self.pageClaims(withStatus, 'limit, offset);
    }

    public isolated function listClaimsForFinance(string? status, string? claimant, int 'limit, int offset)
            returns ClaimListResult|StoreError {
        string effectiveStatus = status is string ? status : "awaiting-finance";
        sql:ParameterizedQuery base = `SELECT claim_id, title, claimant, status,
            total_amount, manager_username, submitted_at, approved_at, returned_at,
            exported_at, export_id, created_at, updated_at FROM claims
            WHERE status = ${effectiveStatus}`;
        sql:ParameterizedQuery withClaimant = claimant is string
            ? sql:queryConcat(base, ` AND claimant = ${claimant}`)
            : base;
        return self.pageClaims(withClaimant, 'limit, offset);
    }

    public isolated function listClaimsForExport() returns ty:ClaimRow[]|StoreError {
        stream<ClaimDb, sql:Error?> claimsStream = self.dbClient->query(
            `SELECT claim_id, title, claimant, status, total_amount, manager_username,
             submitted_at, approved_at, returned_at, exported_at, export_id,
             created_at, updated_at FROM claims WHERE status = 'ready-for-export'
             ORDER BY claim_id`, ClaimDb);
        anydata|StoreError collectedResult = collectTypedRows(ClaimDb, claimsStream);
        if collectedResult is StoreError {
            return collectedResult;
        }
        ClaimDb[] collected = <ClaimDb[]> collectedResult;
        return from ClaimDb claim in collected select claimRowFromDb(claim);
    }

    isolated function pageClaims(sql:ParameterizedQuery filterBase, int 'limit, int offset)
            returns ClaimListResult|StoreError {
        sql:ParameterizedQuery countQuery = sql:queryConcat(
            sql:queryConcat(`SELECT COUNT(*) FROM (`, filterBase), `) AS matching`);
        int|sql:Error countResult = self.dbClient->queryRow(countQuery);
        if countResult is sql:Error {
            return error StoreError("count failed", countResult);
        }
        sql:ParameterizedQuery pageQuery = sql:queryConcat(filterBase,
            ` ORDER BY created_at DESC LIMIT ${'limit} OFFSET ${offset}`);
        stream<ClaimDb, sql:Error?> claimsStream = self.dbClient->query(pageQuery, ClaimDb);
        anydata|StoreError collectedResult = collectTypedRows(ClaimDb, claimsStream);
        if collectedResult is StoreError {
            return collectedResult;
        }
        ClaimDb[] collected = <ClaimDb[]> collectedResult;
        return {claims: from ClaimDb claim in collected select claimRowFromDb(claim),
            count: countResult};
    }

    public isolated function createLine(ty:LineRow line) returns StoreError? {
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `INSERT INTO expense_lines (line_id, claim_id, expense_date, category,
             amount, description) VALUES (${line.lineId}, ${line.claimId},
             ${line.expenseDate}, ${line.category}, ${line.amount}, ${line.description})`);
        if result is sql:Error {
            return error StoreError("create line failed", result);
        }
        return ();
    }

    public isolated function getLine(string claimId, string lineId) returns ty:LineRow|StoreError {
        LineDb|sql:Error found = self.dbClient->queryRow(
            `SELECT line_id, claim_id, expense_date, category, amount, description
             FROM expense_lines WHERE claim_id = ${claimId} AND line_id = ${lineId}`,
             LineDb);
        if found is sql:Error {
            if found is sql:NoRowsError {
                return error StoreNotFoundErr("not found");
            }
            return error StoreError("get line failed", found);
        }
        return {lineId: found.line_id, claimId: found.claim_id,
            expenseDate: found.expense_date, category: found.category,
            amount: found.amount, description: found.description};
    }

    public isolated function getLineById(string lineId) returns ty:LineRow|StoreError {
        LineDb|sql:Error found = self.dbClient->queryRow(
            `SELECT line_id, claim_id, expense_date, category, amount, description
             FROM expense_lines WHERE line_id = ${lineId}`, LineDb);
        if found is sql:Error {
            if found is sql:NoRowsError {
                return error StoreNotFoundErr("no such line");
            }
            return error StoreError("get line failed", found);
        }
        return {lineId: found.line_id, claimId: found.claim_id,
            expenseDate: found.expense_date, category: found.category,
            amount: found.amount, description: found.description};
    }

    public isolated function updateLine(ty:LineRow line) returns StoreError? {
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `UPDATE expense_lines SET expense_date = ${line.expenseDate},
             category = ${line.category}, amount = ${line.amount},
             description = ${line.description} WHERE line_id = ${line.lineId}`);
        if result is sql:Error {
            return error StoreError("update line failed", result);
        }
        return ();
    }

    public isolated function deleteLine(string claimId, string lineId) returns StoreError? {
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `DELETE FROM expense_lines WHERE claim_id = ${claimId} AND line_id = ${lineId}`);
        if result is sql:Error {
            return error StoreError("delete line failed", result);
        }
        return ();
    }

    public isolated function listLines(string claimId) returns ty:LineRow[]|StoreError {
        stream<LineDb, sql:Error?> linesStream = self.dbClient->query(
            `SELECT line_id, claim_id, expense_date, category, amount, description
             FROM expense_lines WHERE claim_id = ${claimId} ORDER BY line_id`, LineDb);
        anydata|StoreError collectedResult = collectTypedRows(LineDb, linesStream);
        if collectedResult is StoreError {
            return collectedResult;
        }
        LineDb[] collected = <LineDb[]> collectedResult;
        return from LineDb line in collected
            select {lineId: line.line_id, claimId: line.claim_id,
                expenseDate: line.expense_date, category: line.category,
                amount: line.amount, description: line.description};
    }

    public isolated function attachReceipt(ty:ReceiptRow receipt) returns StoreError? {
        time:Utc now = time:utcNow();
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `INSERT INTO receipts (receipt_id, line_id, object_key, file_name,
             content_type, file_size, uploaded_by, uploaded_at) VALUES
             (${receipt.receiptId}, ${receipt.lineId}, ${receipt.objectKey},
             ${receipt.fileName}, ${receipt.contentType}, ${receipt.fileSize},
             ${receipt.uploadedBy}, ${now})`);
        if result is sql:Error {
            return error StoreError("attach receipt failed", result);
        }
        return ();
    }

    public isolated function getReceiptByLine(string lineId) returns ty:ReceiptRow|StoreError {
        ReceiptDb|sql:Error found = self.dbClient->queryRow(
            `SELECT receipt_id, line_id, object_key, file_name, content_type,
             file_size, uploaded_by FROM receipts WHERE line_id = ${lineId}`, ReceiptDb);
        if found is sql:Error {
            if found is sql:NoRowsError {
                return error StoreNotFoundErr("not found");
            }
            return error StoreError("get receipt failed", found);
        }
        return receiptRowFromDb(found);
    }

    public isolated function getReceipt(string receiptId) returns ty:ReceiptRow|StoreError {
        ReceiptDb|sql:Error found = self.dbClient->queryRow(
            `SELECT receipt_id, line_id, object_key, file_name, content_type,
             file_size, uploaded_by FROM receipts WHERE receipt_id = ${receiptId}`,
             ReceiptDb);
        if found is sql:Error {
            if found is sql:NoRowsError {
                return error StoreNotFoundErr("not found");
            }
            return error StoreError("get receipt failed", found);
        }
        return receiptRowFromDb(found);
    }

    public isolated function replaceReceipt(ty:ReceiptRow receipt) returns StoreError? {
        time:Utc now = time:utcNow();
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `INSERT INTO receipts (receipt_id, line_id, object_key, file_name,
             content_type, file_size, uploaded_by, uploaded_at) VALUES
             (${receipt.receiptId}, ${receipt.lineId}, ${receipt.objectKey},
             ${receipt.fileName}, ${receipt.contentType}, ${receipt.fileSize},
             ${receipt.uploadedBy}, ${now})
             ON CONFLICT (line_id) DO UPDATE SET receipt_id = ${receipt.receiptId},
             object_key = ${receipt.objectKey}, file_name = ${receipt.fileName},
             content_type = ${receipt.contentType}, file_size = ${receipt.fileSize},
             uploaded_by = ${receipt.uploadedBy}, uploaded_at = ${now}`);
        if result is sql:Error {
            return error StoreError("replace receipt failed", result);
        }
        return ();
    }

    public isolated function deleteReceiptsForLine(string lineId) returns StoreError? {
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `DELETE FROM receipts WHERE line_id = ${lineId}`);
        if result is sql:Error {
            return error StoreError("delete receipt failed", result);
        }
        return ();
    }

    public isolated function listReceiptsForClaim(string claimId) returns ty:ReceiptRow[]|StoreError {
        stream<ReceiptDb, sql:Error?> receiptsStream = self.dbClient->query(
            `SELECT r.receipt_id, r.line_id, r.object_key, r.file_name, r.content_type,
             r.file_size, r.uploaded_by FROM receipts r
             JOIN expense_lines l ON l.line_id = r.line_id
             WHERE l.claim_id = ${claimId} ORDER BY r.receipt_id`, ReceiptDb);
        anydata|StoreError collectedResult = collectTypedRows(ReceiptDb, receiptsStream);
        if collectedResult is StoreError {
            return collectedResult;
        }
        ReceiptDb[] collected = <ReceiptDb[]> collectedResult;
        return from ReceiptDb receipt in collected select receiptRowFromDb(receipt);
    }

    public isolated function addComment(ty:CommentRow comment) returns StoreError? {
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `INSERT INTO review_comments (comment_id, claim_id, author_username,
             stage, body, created_at) VALUES (${comment.commentId}, ${comment.claimId},
             ${comment.author}, ${comment.stage}, ${comment.body}, ${comment.createdAt})`);
        if result is sql:Error {
            return error StoreError("add comment failed", result);
        }
        return ();
    }

    public isolated function listComments(string claimId) returns ty:CommentRow[]|StoreError {
        stream<CommentDb, sql:Error?> commentsStream = self.dbClient->query(
            `SELECT comment_id, claim_id, author_username, stage, body, created_at
             FROM review_comments WHERE claim_id = ${claimId} ORDER BY created_at`,
             CommentDb);
        anydata|StoreError collectedResult = collectTypedRows(CommentDb, commentsStream);
        if collectedResult is StoreError {
            return collectedResult;
        }
        CommentDb[] collected = <CommentDb[]> collectedResult;
        return from CommentDb comment in collected
            select {commentId: comment.comment_id, claimId: comment.claim_id,
                author: comment.author_username, stage: comment.stage,
                body: comment.body, createdAt: comment.created_at};
    }

    public isolated function addNotification(ty:NotificationRow notification) returns StoreError? {
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `INSERT INTO notifications (notification_id, recipient_username, claim_id,
             subject, body, sent_at) VALUES (${notification.notificationId},
             ${notification.recipient}, ${notification?.claimId}, ${notification.subject},
             ${notification.body}, ${notification.sentAt})`);
        if result is sql:Error {
            return error StoreError("add notification failed", result);
        }
        return ();
    }

    public isolated function listNotifications(string recipient, int 'limit, int offset)
            returns (ty:NotificationRow[] & readonly)|StoreError {
        int|sql:Error countResult = self.dbClient->queryRow(
            `SELECT COUNT(*) FROM notifications WHERE recipient_username = ${recipient}`);
        if countResult is sql:Error {
            return error StoreError("notification count failed", countResult);
        }
        stream<NotificationDb, sql:Error?> notificationsStream = self.dbClient->query(
            `SELECT notification_id, recipient_username, claim_id, subject, body, sent_at
             FROM notifications WHERE recipient_username = ${recipient}
             ORDER BY sent_at DESC LIMIT ${'limit} OFFSET ${offset}`, NotificationDb);
        anydata|StoreError collectedResult = collectTypedRows(NotificationDb, notificationsStream);
        if collectedResult is StoreError {
            return collectedResult;
        }
        NotificationDb[] collected = <NotificationDb[]> collectedResult;
        ty:NotificationRow[] rows = from NotificationDb notification in collected
            select {notificationId: notification.notification_id,
                recipient: notification.recipient_username,
                claimId: notification.claim_id, subject: notification.subject,
                body: notification.body, sentAt: notification.sent_at};
        return rows.cloneReadOnly();
    }

    public isolated function createExport(ty:ExportRow exportRun) returns StoreError? {
        string filePath = self.exportDir + "/" + exportRun.exportId + ".csv";
        sql:ExecutionResult|sql:Error result = self.dbClient->execute(
            `INSERT INTO exports (export_id, exported_by, exported_at, file_format,
             claim_count, total_amount, file_path) VALUES (${exportRun.exportId},
             ${exportRun.exportedBy}, ${exportRun.exportedAt}, ${exportRun.fileFormat},
             ${exportRun.claimCount}, ${exportRun.totalAmount}, ${filePath})`);
        if result is sql:Error {
            return error StoreError("create export failed", result);
        }
        return ();
    }

    public isolated function getExport(string exportId) returns ty:ExportRow|StoreError {
        ExportDb|sql:Error found = self.dbClient->queryRow(
            `SELECT export_id, exported_by, exported_at, file_format, claim_count,
             total_amount FROM exports WHERE export_id = ${exportId}`, ExportDb);
        if found is sql:Error {
            if found is sql:NoRowsError {
                return error StoreNotFoundErr("not found");
            }
            return error StoreError("get export failed", found);
        }
        return {exportId: found.export_id, exportedBy: found.exported_by,
            exportedAt: found.exported_at, fileFormat: found.file_format,
            claimCount: found.claim_count, totalAmount: found.total_amount};
    }

    public isolated function listExports(int 'limit, int offset) returns (ty:ExportRow[] & readonly)|StoreError {
        stream<ExportDb, sql:Error?> exportsStream = self.dbClient->query(
            `SELECT export_id, exported_by, exported_at, file_format, claim_count,
             total_amount FROM exports ORDER BY exported_at DESC
             LIMIT ${'limit} OFFSET ${offset}`, ExportDb);
        anydata|StoreError collectedResult = collectTypedRows(ExportDb, exportsStream);
        if collectedResult is StoreError {
            return collectedResult;
        }
        ExportDb[] collected = <ExportDb[]> collectedResult;
        ty:ExportRow[] rows = from ExportDb exportRow in collected
            select {exportId: exportRow.export_id, exportedBy: exportRow.exported_by,
                exportedAt: exportRow.exported_at, fileFormat: exportRow.file_format,
                claimCount: exportRow.claim_count, totalAmount: exportRow.total_amount};
        return rows.cloneReadOnly();
    }

    public isolated function markClaimsExported(ty:ClaimRow[] claims, string exportId, time:Utc exportedAt)
            returns StoreError? {
        foreach ty:ClaimRow claim in claims {
            sql:ExecutionResult|sql:Error result = self.dbClient->execute(
                `UPDATE claims SET status = 'exported', exported_at = ${exportedAt},
                 export_id = ${exportId}, updated_at = ${exportedAt}
                 WHERE claim_id = ${claim.claimId} AND status = 'ready-for-export'`);
            if result is sql:Error {
                return error StoreError("mark exported failed", result);
            }
        }
        return ();
    }

    public isolated function saveExportFile(string exportId, string content) returns StoreError? {
        ExportFilePath|sql:Error found = self.dbClient->queryRow(
            `SELECT file_path FROM exports WHERE export_id = ${exportId}`, ExportFilePath);
        if found is sql:Error {
            return error StoreError("export file path lookup failed", found);
        }
        io:Error? writeResult = io:fileWriteBytes(found.file_path, content.toBytes());
        if writeResult is io:Error {
            return error StoreError("export file write failed", writeResult);
        }
        return ();
    }

    public isolated function readExportFile(string exportId) returns string|StoreError {
        ExportFilePath|sql:Error found = self.dbClient->queryRow(
            `SELECT file_path FROM exports WHERE export_id = ${exportId}`, ExportFilePath);
        if found is sql:Error {
            if found is sql:NoRowsError {
                return error StoreNotFoundErr("not found");
            }
            return error StoreError("export file path lookup failed", found);
        }
        readonly & byte[]|io:Error content = io:fileReadBytes(found.file_path);
        if content is io:Error {
            return error StoreError("export file read failed", content);
        }
        string|error decoded = string:fromBytes(content);
        if decoded is error {
            return error StoreError("export file decode failed", decoded);
        }
        return decoded;
    }

    public isolated function close() returns StoreError? {
        sql:Error? closed = self.dbClient.close();
        if closed is sql:Error {
            return error StoreError("close failed", closed);
        }
        return ();
    }
};

type PersonDb record {|
    string username;
    string display_name;
    string email;
    string? manager_username;
|};

type ClaimDb record {|
    string claim_id;
    string title;
    string claimant;
    string status;
    decimal total_amount;
    string? manager_username;
    time:Utc? submitted_at;
    time:Utc? approved_at;
    time:Utc? returned_at;
    time:Utc? exported_at;
    string? export_id;
    time:Utc created_at;
    time:Utc updated_at;
|};

type LineDb record {|
    string line_id;
    string claim_id;
    string expense_date;
    string category;
    decimal amount;
    string description;
|};

type ReceiptDb record {|
    string receipt_id;
    string line_id;
    string object_key;
    string file_name;
    string content_type;
    int file_size;
    string uploaded_by;
|};

type CommentDb record {|
    string comment_id;
    string claim_id;
    string author_username;
    string stage;
    string body;
    time:Utc created_at;
|};

type NotificationDb record {|
    string notification_id;
    string recipient_username;
    string? claim_id;
    string subject;
    string body;
    time:Utc sent_at;
|};

type ExportDb record {|
    string export_id;
    string exported_by;
    time:Utc exported_at;
    string file_format;
    int claim_count;
    decimal total_amount;
|};

type ExportFilePath record {|
    string file_path;
|};

isolated function claimRowFromDb(ClaimDb found) returns ty:ClaimRow {
    return {claimId: found.claim_id, title: found.title, claimant: found.claimant,
        status: found.status, totalAmount: found.total_amount,
        manager: found.manager_username, submittedAt: found.submitted_at,
        approvedAt: found.approved_at, returnedAt: found.returned_at,
        exportedAt: found.exported_at, exportId: found.export_id,
        createdAt: found.created_at, updatedAt: found.updated_at};
}

isolated function receiptRowFromDb(ReceiptDb found) returns ty:ReceiptRow {
    return {receiptId: found.receipt_id, lineId: found.line_id,
        objectKey: found.object_key, fileName: found.file_name,
        contentType: found.content_type, fileSize: found.file_size,
        uploadedBy: found.uploaded_by};
}

isolated function collectRows(stream<record {}, sql:Error?> rowStream) returns record {}[]|StoreError {
    record {}[] rows = [];
    record {}|sql:Error? nextRow = rowStream.next();
    while nextRow is record {} {
        rows.push(nextRow.clone());
        nextRow = rowStream.next();
    }
    if nextRow is sql:Error {
        return error StoreError("row iteration failed", nextRow);
    }
    _ = checkpanic rowStream.close();
    return rows;
}

isolated function collectTypedRows(typedesc<anydata> rowType, stream<record {}, sql:Error?> rowStream)
        returns anydata|StoreError {
    var collected = collectRows(rowStream);
    if collected is StoreError {
        return collected;
    }
    anydata converted = checkpanic collected.cloneWithType(rowType);
    return converted;
}