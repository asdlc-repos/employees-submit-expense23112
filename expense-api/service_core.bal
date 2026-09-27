import ballerina/file;
import ballerina/log;
import ballerina/time;
import ballerina/sql;
import ballerinax/postgresql;
import expense_api.types as ty;

// The store this process serves from: PostgreSQL when the platform wires the
// expense-db resource, the in-memory implementation when it cannot be reached
// so the service still starts with no env vars set.
Store appStore = initStoreOrFallback();

function initStoreOrFallback() returns Store {
    postgresql:Client|sql:Error dbClient = new (host = expenseDbHost,
        username = expenseDbUser, password = expenseDbPassword,
        database = expenseDbName, port = expenseDbPortNumber());
    if dbClient is postgresql:Client {
        PostgresStore store = new (dbClient, receiptDir);
        StoreError? migrated = store.initStore();
        if migrated is () {
            ensureExportDir();
            log:printInfo("expense-api serving from PostgreSQL");
            return store;
        }
        log:printError("expense-api could not migrate the expense database, falling back to in-memory storage", 'error = migrated);
    } else {
        log:printError("expense-api cannot reach the expense database, falling back to in-memory storage", 'error = dbClient);
    }
    MemoryStore fallback = new;
    _ = checkpanic fallback.initStore();
    ensureExportDir();
    log:printWarn("expense-api is running on in-memory storage: claims will not survive a restart");
    return fallback;
}

function ensureExportDir() {
    file:Error? made = file:createDir(receiptDir, file:RECURSIVE);
    if made is file:Error {
        log:printWarn("could not create the receipt directory", 'error = made);
    }
}

// ---------- id helpers ----------

int idCounter = 0;

function freshId(string prefix) returns string {
    lock {
        idCounter += 1;
    }
    string stamp = time:utcToString(time:utcNow());
    string compact = re `[-:TZ.]`.replaceAll(stamp, "");
    return prefix + "-" + compact + "-" + idCounter.toString();
}

// ---------- mapping ----------

function toWireClaim(ty:ClaimRow claim, ty:LineRow[] lines, ty:ReceiptRow[] receipts,
        ty:CommentRow[] comments) returns ty:ExpenseClaim {
    ty:ExpenseLine[] wireLines = [];
    foreach ty:LineRow line in lines {
        ty:Receipt? receipt = ();
        foreach ty:ReceiptRow candidate in receipts {
            if candidate.lineId == line.lineId {
                receipt = {receiptId: candidate.receiptId, fileName: candidate.fileName,
                    contentType: candidate.contentType, fileSize: candidate.fileSize};
            }
        }
        if receipt is ty:Receipt {
            wireLines.push({lineId: line.lineId, expenseDate: line.expenseDate,
                category: line.category, amount: line.amount, description: line.description,
                receipt: receipt});
        } else {
            wireLines.push({lineId: line.lineId, expenseDate: line.expenseDate,
                category: line.category, amount: line.amount, description: line.description});
        }
    }
    ty:ReviewComment[] wireComments = [];
    foreach ty:CommentRow comment in comments {
        wireComments.push({commentId: comment.commentId, author: comment.author,
            stage: comment.stage, body: comment.body, createdAt: time:utcToString(comment.createdAt)});
    }
    return {claimId: claim.claimId, title: claim.title, claimant: claim.claimant,
        status: <ty:ClaimStatus> claim.status, totalAmount: claim.totalAmount,
        lines: wireLines, comments: wireComments,
        submittedAt: utcString(claim?.submittedAt), returnedAt: utcString(claim?.returnedAt),
        exportedAt: utcString(claim?.exportedAt), createdAt: time:utcToString(claim.createdAt),
        updatedAt: time:utcToString(claim.updatedAt)};
}

function utcString(time:Utc? instant) returns string? {
    if instant is time:Utc {
        return time:utcToString(instant);
    }
    return ();
}

function loadWireClaim(string claimId) returns ty:ExpenseClaim|StoreError {
    ty:ClaimRow|StoreError claim = appStore.getClaim(claimId);
    if claim is StoreError {
        return claim;
    }
    return loadWireClaimFromRow(claim);
}

function loadWireClaimFromRow(ty:ClaimRow claim) returns ty:ExpenseClaim|StoreError {
    ty:LineRow[]|StoreError lines = appStore.listLines(claim.claimId);
    if lines is StoreError {
        return lines;
    }
    ty:ReceiptRow[]|StoreError receipts = appStore.listReceiptsForClaim(claim.claimId);
    if receipts is StoreError {
        return receipts;
    }
    ty:CommentRow[]|StoreError comments = appStore.listComments(claim.claimId);
    if comments is StoreError {
        return comments;
    }
    return toWireClaim(claim, lines, receipts, comments);
}

// ---------- pagination ----------

function clampLimit(int 'limit) returns int {
    if 'limit < 1 {
        return 20;
    }
    if 'limit > 100 {
        return 100;
    }
    return 'limit;
}

function pageLinks(int count, int 'limit, int offset, string basePath) returns [string?, string?] {
    string? next = ();
    if offset + 'limit < count {
        next = basePath + "?limit=" + 'limit.toString() + "&offset=" + (offset + 'limit).toString();
    }
    string? previous = ();
    if offset > 0 {
        int previousOffset = offset - 'limit;
        if previousOffset < 0 {
            previousOffset = 0;
        }
        previous = basePath + "?limit=" + 'limit.toString() + "&offset=" + previousOffset.toString();
    }
    return [next, previous];
}

// ---------- notifications ----------

function notify(string recipient, string subject, string body, string? claimId) {
    ty:NotificationRow notification = {notificationId: freshId("NTF"), recipient: recipient,
        subject: subject, body: body, claimId: claimId, sentAt: time:utcNow()};
    StoreError? recorded = appStore.addNotification(notification);
    if recorded is StoreError {
        log:printError("failed to record notification", recipient = recipient, 'error = recorded);
    }
}