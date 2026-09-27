# Finance review and payroll export

A finance team member reviews manager-approved claims against policy, returns faulty ones for correction, approves the rest for export, and downloads the payroll file of everything approved.

```mermaid
sequenceDiagram
    actor Finance as "Finance Team Member"
    participant expense-webapp
    participant expense-api
    participant email as "Email Service"

    Finance->>expense-webapp: open the finance review queue
    expense-webapp->>expense-api: list manager-approved claims
    expense-api-->>expense-webapp: claims with lines and receipts
    Finance->>expense-webapp: check a claim against policy, then decide
    expense-webapp->>expense-api: approve for export or return the claim
    alt approve for export
        expense-api->>expense-api: set status ready-for-export
        expense-api->>email: send finance approval email to the employee
    else return with a comment
        expense-api->>expense-api: set status returned and store the comment
        expense-api->>email: send return email to the employee
    end
    Finance->>expense-webapp: download the payroll file
    expense-webapp->>expense-api: export the claims ready for export
    expense-api->>expense-api: mark the claims exported with the date
    expense-api-->>expense-webapp: payroll file download
    expense-api->>email: send exported emails to the employees
```