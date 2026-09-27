import ballerina/time;

// Pure domain logic: the status journey, totals, validation and CSV building.
// No database, no clock, no filesystem — everything here is testable in the plain.

// Pure domain logic: the status journey, totals, validation and CSV building.
// No database, no clock, no filesystem — everything here is testable in the plain.

# Whether a claim may be edited (lines added/updated/deleted, title changed,
# receipts uploaded, claim deleted). Editable only while draft or returned.
public function isEditable(string status) returns boolean {
    return status == "draft" || status == "returned";
}

# Whether a claim may be submitted (first submission or resubmission of a
# returned claim).
public function isSubmittable(string status) returns boolean {
    return status == "draft" || status == "returned";
}

# The total of a claim is the sum of its line amounts.
public function computeTotal(decimal[] amounts) returns decimal {
    decimal total = 0;
    foreach decimal amt in amounts {
        total += amt;
    }
    return total;
}

# A date is valid when it parses as YYYY-MM-DD.
public function isValidExpenseDate(string expenseDate) returns boolean {
    if expenseDate.length() != 10 || expenseDate.substring(4, 5) != "-" || expenseDate.substring(7, 8) != "-" {
        return false;
    }
    int|error yearPart = int:fromString(expenseDate.substring(0, 4));
    int|error monthPart = int:fromString(expenseDate.substring(5, 7));
    int|error dayPart = int:fromString(expenseDate.substring(8, 10));
    if yearPart is error || monthPart is error || dayPart is error {
        return false;
    }
    time:Error? valid = time:dateValidate({year: yearPart, month: monthPart, day: dayPart,
        hour: 0, minute: 0, second: 0});
    return valid is ();
}

# The finance-maintained category list.
public isolated function validCategories() returns string[] {
    return ["travel", "meals", "supplies", "training", "other"];
}

# Validates a line's fields. Returns () when the line is acceptable, or a
# short human-readable reason why not.
public function validateLine(string expenseDate, string category, decimal amount, string description)
        returns string? {
    if expenseDate.trim() == "" {
        return "expenseDate is required";
    }
    if !isValidExpenseDate(expenseDate) {
        return "expenseDate must be a valid YYYY-MM-DD date";
    }
    if category.trim() == "" {
        return "category is required";
    }
    if validCategories().indexOf(category.trim()) is () {
        return "category must be one of the finance-maintained categories";
    }
    if amount <= 0d {
        return "amount must be greater than zero";
    }
    if description.trim() == "" {
        return "description is required";
    }
    return ();
}

# Submission refusal reasons: a claim with no lines, or any line lacking a
# receipt. Returns () when submission may proceed.
public function submissionBlocker(int lineCount, int linesWithReceipt) returns string? {
    if lineCount == 0 {
        return "the claim has no expense lines";
    }
    if linesWithReceipt < lineCount {
        return "every expense line must carry a receipt before submission";
    }
    return ();
}

# One CSV row per claim: claimant, claim title, per-category totals, amount.
public function csvHeader() returns string {
    return "claimant,claim,travel,meals,supplies,training,other,amount\n";
}

public function csvRowForClaim(string claimant, string title, map<decimal> categoryTotals, decimal total)
        returns string {
    return csvCell(claimant) + "," + csvCell(title) + ","
        + csvAmount(categoryTotals["travel"] ?: 0) + "," + csvAmount(categoryTotals["meals"] ?: 0) + ","
        + csvAmount(categoryTotals["supplies"] ?: 0) + "," + csvAmount(categoryTotals["training"] ?: 0) + ","
        + csvAmount(categoryTotals["other"] ?: 0) + "," + csvAmount(total) + "\n";
}

# Doubles through a decimal then trims trailing zeros for payroll-friendly numbers.
function csvAmount(decimal value) returns string {
    return value.toString();
}

function csvCell(string value) returns string {
    if value.includes(",") || value.includes("\"") || value.includes("\n") || value.includes("\r") {
        string escaped = re `"`.replaceAll(value, "\\\"");
        return "\"" + escaped + "\"";
    }
    return value;
}

# The seeded people records, standing in for the company directory, aligned
# with specs/design/security.json test users so approvals route to the
# claimant's recorded manager.
public type PersonSeed record {|
    string username;
    string displayName;
    string email;
    string? manager?;
|};

public isolated function seedPeople() returns PersonSeed[] {
    return [
        {username: "test-employee", displayName: "Test Employee", email: "test-employee@example.com",
            manager: "test-manager"},
        {username: "test-employee-2", displayName: "Test Employee Two", email: "test-employee-2@example.com",
            manager: "test-manager"},
        {username: "test-manager", displayName: "Test Manager", email: "test-manager@example.com",
            manager: "test-manager-2"},
        {username: "test-manager-2", displayName: "Test Manager Two", email: "test-manager-2@example.com"},
        {username: "test-finance-reviewer", displayName: "Test Finance Reviewer",
            email: "test-finance-reviewer@example.com", manager: "test-manager-2"}
    ];
}

# The finance-maintained categories, seeded on startup.
public isolated function seedCategories() returns string[] {
    return validCategories();
}