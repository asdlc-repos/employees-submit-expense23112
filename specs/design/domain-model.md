# Expense Claims — Domain Model

Expense claims and their lines, the two review gates that move them, and the export that hands approved claims to payroll. People, teams and managers live in the company directory — this database stores only stable references to them.

```mermaid
erDiagram
    APP_USER ||--o{ EXPENSE_CLAIM : submits
    EXPENSE_CLAIM ||--o{ EXPENSE_LINE : contains
    EXPENSE_LINE ||--o| RECEIPT : "backed by"
    EXPENSE_CLAIM ||--o{ REVIEW_COMMENT : "collects"
    EXPENSE_EXPORT |o--o{ EXPENSE_CLAIM : includes
    APP_USER ||--o{ EXPENSE_EXPORT : runs

    APP_USER {
        string username PK "username key in the company directory"
        string displayName
        string email
        string managerUsername FK "reference to the directory record of the manager"
    }
    EXPENSE_CLAIM {
        string claimId PK
        string title
        string claimantUsername FK
        string status "draft, awaiting-manager, awaiting-finance, ready-for-export, returned, exported"
        decimal totalAmount "payroll currency"
        string managerUsername FK "manager the claim was routed to"
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
        string s3Key "object key in the receipts bucket"
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
```

- Receipt bytes live in S3; the database stores only the object key and upload metadata.
- A submitted claim routes to the claimant's manager as recorded in the directory; manager approval moves it to the finance queue, finance approval readies it for export.
- An employee may edit a claim only while it is a draft or returned; everything after submission happens through the review gates.