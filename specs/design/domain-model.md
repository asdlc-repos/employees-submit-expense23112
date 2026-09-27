# Expense Claims — Domain Model

Expense claims and their lines, the two review gates that move them, and the export that hands approved claims to payroll. In this build the app is self-contained: it holds its own people records — seeded with sample data standing in for the company directory — and records its email notices in its own database instead of delivering them.

```mermaid
erDiagram
    PERSON ||--o{ EXPENSE_CLAIM : "submits as claimant"
    PERSON ||--o{ EXPENSE_CLAIM : "reviews as routed manager"
    PERSON ||--o{ EXPENSE_EXPORT : runs
    PERSON ||--o{ NOTIFICATION : receives
    EXPENSE_CLAIM ||--o{ EXPENSE_LINE : contains
    EXPENSE_LINE ||--o| RECEIPT : "backed by"
    EXPENSE_CLAIM ||--o{ REVIEW_COMMENT : "collects"
    EXPENSE_CLAIM ||--o{ NOTIFICATION : "is about"
    EXPENSE_EXPORT |o--o{ EXPENSE_CLAIM : includes

    PERSON {
        string username PK "the app's own people record, seeded sample data in this build"
        string displayName
        string email
        string managerUsername FK "nullable — the person's manager, the top of the chain has none"
    }
    EXPENSE_CLAIM {
        string claimId PK
        string title
        string claimantUsername FK
        string status "draft, awaiting-manager, awaiting-finance, ready-for-export, returned, exported"
        decimal totalAmount "payroll currency"
        string managerUsername FK "seeded manager the claim was routed to"
        datetime submittedAt
        datetime approvedAt
        datetime returnedAt
        datetime exportedAt
        datetime updatedAt
    }
    EXPENSE_LINE {
        string lineId PK
        string claimId FK
        date expenseDate
        string category "from the finance-maintained list"
        decimal amount "payroll currency"
        string description
    }
    RECEIPT {
        string receiptId PK
        string lineId FK
        string objectKey "stored inside the API's own storage in this build"
        string fileName
        string contentType
        int fileSize
        string uploadedBy FK
    }
    REVIEW_COMMENT {
        string commentId PK
        string claimId FK
        string authorUsername FK
        string stage "manager or finance"
        string body
        datetime createdAt
    }
    EXPENSE_EXPORT {
        string exportId PK
        string exportedBy FK
        datetime exportedAt
        string fileFormat "CSV by default"
        int claimCount
        decimal totalAmount
    }
    NOTIFICATION {
        string notificationId PK
        string recipientUsername FK
        string claimId FK "the claim the notice is about"
        string subject
        string body
        datetime sentAt
    }
```

- Receipt bytes stay inside the API's own storage in this build; the database stores only the object key and upload metadata.
- A submitted claim routes to the claimant's manager as recorded in the app's people data; manager approval moves it to the finance queue, finance approval readies it for export.
- Notifications are recorded, not delivered: the API writes a notification row for each recipient at every step, standing in for email.
- An employee may edit a claim only while it is a draft or returned; everything after submission happens through the review gates.