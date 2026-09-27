# Expense Claims — PRD

## Problem Statement

Employees today reclaim out-of-pocket expenses by emailing spreadsheets and photographs of receipts. Managers approve over email with no queue, so approvals stall and decisions leave no audit trail. Finance then re-keys approved totals into payroll by hand, chases missing receipts, and cannot tell which claims have already been paid. The cost is slow reimbursements, lost receipts, claims that are missed or paid twice, and hours of re-work every payroll cycle.

## Solution

An internal expense-claims application. An employee signs in with company single sign-on, builds a claim from dated, categorized expense lines with receipt images, and submits it when it is ready. The claim routes automatically to the employee's manager as recorded in the app's own people data; once approved it joins a finance review queue, where a finance team member checks it against policy and either returns it with a comment or approves it for export. Finance downloads a file of approved claims and loads it into the payroll system themselves. Everyone sees claim status in one place, and every step notifies by email.

## Actors

- **Employee** — any staff member who spends their own money on company business: creates and submits claims, tracks their status, and corrects returned claims.
- **Manager** — an employee with direct reports: sees the claims awaiting their approval and approves or returns them. A manager's own claim goes to *their* manager.
- **Finance team member** — finance staff: reviews manager-approved claims, returns faulty ones for correction, and exports approved claims for payroll.

## User Stories

1. As an employee, I want to create an expense claim made up of several expense lines (date, category, amount, description) and submit it when it is ready, so that I can be reimbursed without emailing receipts around.
2. As an employee, I want to attach a receipt image to each expense line, so that my spending can be verified.
3. As an employee, I want to see where each of my claims stands (draft, awaiting manager, awaiting finance, ready for export, returned, exported), so that I can track reimbursement without chasing anyone.
4. As an employee, I want to correct and resubmit a claim that a manager or finance returned with a comment, so that it can be approved without starting from scratch.
5. As an employee, I want to receive an email when my claim is approved, returned or exported, so that I know its progress without checking the app.
6. As a manager, I want to see the claims my direct reports have submitted, awaiting my approval, so that I can review them in one place.
7. As a manager, I want to approve a claim or return it with a comment, so that only policy-compliant spending is reimbursed.
8. As a manager, I want to receive an email when a claim awaits my approval, so that approvals do not stall.
9. As a finance team member, I want to review manager-approved claims together with their receipts, so that I can check them before payment.
10. As a finance team member, I want to return a claim for correction with a comment, so that errors are fixed before export.
11. As a finance team member, I want to approve claims for export, so that only checked claims reach payroll.
12. As a finance team member, I want to download a file of all approved, not-yet-exported claims, so that payroll can load the reimbursements without re-typing them.
13. As a finance team member, I want to see which claims have been exported and when, so that no claim is reimbursed twice.

## Product Decisions

- Sign-in: staff sign in with the company's single sign-on through Thunder, the platform IDP.
- People and approvals: the app holds its own records of people and their managers, seeded with sample data in this build — a submitted claim routes automatically to the submitter's manager as recorded there, and no approver is ever picked by hand.
- Notifications: email only, generated and recorded by the app itself — mock delivery in this build, with no external email provider.
- Finance gate: after the manager approves, a finance team member reviews the claim and either returns it for correction or approves it for export; this is the second and final gate before payment.
- Payroll export: finance downloads a file containing all approved, not-yet-exported claims and loads it into the payroll system themselves — the app integrates with no payroll system.
- Claim structure: a claim is a bundle of expense lines, each with a date, category, amount and description, submitted and approved as one unit.
- Receipts: a receipt image is required for every expense line.
- Categories: expense lines are categorized from a fixed list maintained by finance (for example travel, meals, supplies, training, other). *assumed*
- Currencies: every amount is entered in the payroll currency.
- Approval levels: a single manager approval covers claims of any amount.
- Export timing: finance may export at any time; an export contains everything approved since the previous export.
- Editability: an employee can edit a claim until it is submitted; after that it changes only through the return-and-resubmit cycle. *assumed*

## Out of Scope

- Integration with any payroll system — export is a file finance downloads and loads themselves.
- External provider integrations — the company directory, email delivery and receipt storage run inside the app as mocks in this build; connecting real providers is a later change.
- Automated policy enforcement — per-category limits, duplicate detection and tax/VAT handling are not built; approvers and finance judge claims manually.
- Multi-currency conversion.
- Corporate-card feeds and automatic statement import.
- Approver delegation — a manager's claims wait for that manager; reassignment is a later feature.
- The reimbursement payment itself — payroll pays; this product stops at export.
- A dedicated mobile app.

## Open Questions

1. What import format does the payroll system require (for example CSV), and does it need a fixed column layout? — answered by finance; the answer shapes the export file at design.

