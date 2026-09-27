import ballerina/time;

public type ClaimStatus "draft"|"awaiting-manager"|"awaiting-finance"|"ready-for-export"|"returned"|"exported";

public type Receipt record {|
    string receiptId;
    string fileName;
    string contentType;
    int fileSize;
|};

public type ExpenseLine record {|
    string lineId;
    string expenseDate;
    string category;
    decimal amount;
    string description;
    Receipt? receipt?;
|};

public type ReviewComment record {|
    string commentId;
    string author;
    string stage;
    string body;
    string createdAt;
|};

public type ExpenseClaim record {|
    string claimId;
    string title;
    string claimant;
    ClaimStatus status;
    decimal totalAmount;
    ExpenseLine[] lines;
    ReviewComment[] comments?;
    string? submittedAt?;
    string? returnedAt?;
    string? exportedAt?;
    string createdAt;
    string updatedAt;
|};

public type ClaimPage record {|
    int count;
    string? next?;
    string? previous?;
    ExpenseClaim[] data;
|};

public type ClaimCreate record {|
    string title;
|};

public type LineCreate record {|
    string expenseDate;
    string category;
    decimal amount;
    string description;
|};

public type ReceiptUpload record {|
    string fileName;
    string contentType;
    int fileSize;
    string content;
|};

public type Person record {|
    string username;
    string displayName;
    string email;
    string? manager?;
|};

public type Notification record {|
    string notificationId;
    string recipient;
    string subject;
    string body;
    string? claimId?;
    string sentAt;
|};

public type NotificationPage record {|
    int count;
    string? next?;
    string? previous?;
    Notification[] data;
|};

public type ReviewDecision record {|
    string comment;
|};

public type ReviewApproval record {|
|};

public type ExportRecord record {|
    string exportId;
    string exportedBy;
    string exportedAt;
    string fileFormat;
    int claimCount;
    decimal totalAmount;
|};

public type ExportPage record {|
    int count;
    string? next?;
    string? previous?;
    ExportRecord[] data;
|};

public type ErrorBody record {|
    int code;
    string message;
    string description?;
    string moreInfo?;
|};

# Internal row shapes. The wire records above mirror openapi.yaml exactly;
# these carry the database columns the store maps onto them.

public type ClaimRow record {|
    string claimId;
    string title;
    string claimant;
    string status;
    decimal totalAmount;
    string? manager;
    time:Utc? submittedAt;
    time:Utc? approvedAt;
    time:Utc? returnedAt;
    time:Utc? exportedAt;
    string exportId?;
    time:Utc createdAt;
    time:Utc updatedAt;
|};

public type LineRow record {|
    string lineId;
    string claimId;
    string expenseDate;
    string category;
    decimal amount;
    string description;
|};

public type ReceiptRow record {|
    string receiptId;
    string lineId;
    string objectKey;
    string fileName;
    string contentType;
    int fileSize;
    string uploadedBy;
|};

public type CommentRow record {|
    string commentId;
    string claimId;
    string author;
    string stage;
    string body;
    time:Utc createdAt;
|};

public type NotificationRow record {|
    string notificationId;
    string recipient;
    string? claimId;
    string subject;
    string body;
    time:Utc sentAt;
|};

public type ExportRow record {|
    string exportId;
    string exportedBy;
    time:Utc exportedAt;
    string fileFormat;
    int claimCount;
    decimal totalAmount;
|};

public type PersonRow record {|
    string username;
    string displayName;
    string email;
    string? manager;
|};