import ballerina/os;

# PostgreSQL connection, assembled from the expense-db platform-resource bindings.
# Every setting has a sensible default so the service starts with none set.
configurable string expenseDbHost = envOrDefault("EXPENSE_DB_HOST", "localhost");
configurable string expenseDbPort = envOrDefault("EXPENSE_DB_PORT", "5432");
configurable string expenseDbUser = envOrDefault("EXPENSE_DB_USER", "postgres");
configurable string expenseDbPassword = envOrDefault("EXPENSE_DB_PASSWORD", "postgres");
configurable string expenseDbName = envOrDefault("EXPENSE_DB_DBNAME", "expense");

# Where receipt images live on disk. Kept outside the DB on purpose: the DB
# stores only the object key and upload metadata.
configurable string receiptDir = envOrDefault("EXPENSE_RECEIPT_DIR", "data/receipts");

function envOrDefault(string envVar, string default) returns string {
    string? rawValue = os:getEnv(envVar);
    if rawValue is string && rawValue.trim() != "" {
        return rawValue;
    }
    return default;
}

function expenseDbPortNumber() returns int {
    int|error parsedPort = int:fromString(expenseDbPort.trim());
    if parsedPort is int {
        return parsedPort;
    }
    return 5432;
}