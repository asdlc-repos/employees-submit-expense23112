// Expense Claims — three roles, eleven screens, desktop

screen MyClaims "An employee tracks the status of every claim they have filed"
  navbar "Expense Claims"
  sidebar "My Claims -> MyClaims | Settings"
  row
    heading "My Claims"
    right
    button "New claim" primary -> NewClaim
  tabs "All | Draft | Awaiting approval | Returned"
  table "Claim | Total | Status | Submitted" -> MyClaimDetail
    row "Client workshop in Leeds | 214.60 | Awaiting manager | 20 Sep"
    row "Team lunch, sprint review | 86.40 | Ready for export | 19 Sep"
    row "Design conference ticket | 340.00 | Returned | 17 Sep"
    row "Printer paper for the office | 24.80 | Exported | 05 Sep"

screen NewClaim "An employee builds a new claim from expense lines with receipts"
  navbar "Expense Claims"
  sidebar "My Claims -> MyClaims | Settings"
  breadcrumb "My Claims / New claim"
  heading "New Claim"
  input "Claim title — e.g. Client workshop in Leeds"
  heading "Expense lines"
  table "Date | Category | Description | Amount | Receipt"
    row "10 Oct | Travel | Train to Leeds | 89.50 | ticket.jpg"
    row "10 Oct | Meals | Dinner with the client | 68.20 | dinner.png"
  card "Add an expense line"
    row
      input "Date — 14 Oct"
      select "Category: Travel"
    row
      input "Description — what was it for?"
      input "Amount — 0.00"
    row
      right
      button "Attach receipt"
      button "Add line"  // in place — appends the line to the table above
  text "Every line needs a receipt before the claim can be submitted."
  row
    right
    button "Submit claim" primary -> MyClaimDetail

screen MyClaimDetail "An employee follows one claim's review journey and corrects it when returned"
  navbar "Expense Claims"
  sidebar "My Claims -> MyClaims | Settings"
  breadcrumb "My Claims / Client workshop in Leeds"
  row
    heading "Client workshop in Leeds"
    badge "Returned" warning
  text "Total 214.60 — 2 expense lines"
  split 60/40
    left
      heading "Expense lines"
      table "Date | Category | Description | Amount | Receipt"
        row "10 Oct | Travel | Train to Leeds | 89.50 | View"
        row "10 Oct | Meals | Dinner with the client | 68.20 | View"
      row
        right
        button "Edit claim" primary -> EditClaim
    right
      card "Why it was returned"
        text "J. Weber (Manager) · 21 Oct: the amount doesn't match the dinner receipt."
      heading "Activity"
      text "20 Sep — submitted to J. Weber"
      text "21 Oct — returned by J. Weber for correction"

screen EditClaim "An employee corrects a returned claim and sends it back for review"
  navbar "Expense Claims"
  sidebar "My Claims -> MyClaims | Settings"
  breadcrumb "My Claims / Client workshop in Leeds / Edit"
  row
    heading "Correct returned claim"
    badge "Returned" warning
  card "Why it was returned"
    text "J. Weber (Manager) · 21 Oct: the amount doesn't match the dinner receipt."
  heading "Expense lines"
  table "Date | Category | Description | Amount | Receipt"
    row "10 Oct | Travel | Train to Leeds | 89.50 | View"
    row "10 Oct | Meals | Dinner with the client | 68.20 | View"
  text "Fix the lines above and attach any missing receipt, then send the claim back."
  row
    right
    button "Submit again" primary -> MyClaimDetail

screen ManagerQueue "A manager reviews the claims their direct reports have submitted"
  navbar "Expense Claims"
  sidebar "Team Claims -> ManagerQueue | My Claims -> MyClaims | Settings"
  row
    heading "Team Claims"
    right
    select "Filter: All reports"
  row
    card "Awaiting my approval | 5 | claims from 3 reports"
    card "Approved this month | 12 | 480.60 total"
    card "Returned for correction | 3 | back with their owners"
  row
    heading "Needs your approval"
    right
    button "Review next" primary -> ManagerClaimDetail
  table "Claimant | Claim | Total | Submitted" -> ManagerClaimDetail
    row "Maya Patel | Client workshop in Leeds | 214.60 | 20 Sep"
    row "Priya Nair | Team lunch, sprint review | 86.40 | 19 Sep"
    row "Ken Sato | Design conference ticket | 340.00 | 17 Sep"

screen ManagerClaimDetail "A manager checks one claim's lines and receipts, then approves or returns it"
  navbar "Expense Claims"
  sidebar "Team Claims -> ManagerQueue | My Claims -> MyClaims | Settings"
  breadcrumb "Team Claims / Maya Patel / Client workshop in Leeds"
  row
    heading "Client workshop in Leeds"
    badge "Awaiting manager" info
  text "Maya Patel — 2 expense lines — 214.60 total — submitted 20 Sep"
  split 60/40
    left
      heading "Expense lines"
      table "Date | Category | Description | Amount | Receipt"
        row "10 Oct | Travel | Train to Leeds | 89.50 | View"
        row "10 Oct | Meals | Dinner with the client | 68.20 | View"
      row
        right
        button "Return claim" -> ManagerReturnClaim
        button "Approve" primary -> ManagerQueue
    right
      heading "Activity"
      text "20 Sep — Maya submitted the claim"

screen ManagerReturnClaim "A manager sends a claim back with a comment for correction"
  navbar "Expense Claims"
  sidebar "Team Claims -> ManagerQueue | My Claims -> MyClaims | Settings"
  breadcrumb "Team Claims / Maya Patel / Return"
  heading "Return claim for correction"
  text "Client workshop in Leeds — Maya Patel — 214.60 total"
  textarea "Why is this being returned? — e.g. the amount doesn't match the receipt"
  row
    right
    button "Cancel" -> ManagerClaimDetail
    button "Return claim" primary -> ManagerQueue

screen FinanceQueue "A finance reviewer checks manager-approved claims before export"
  navbar "Expense Claims"
  sidebar "Finance Queue -> FinanceQueue | Exports -> FinanceExports | My Claims -> MyClaims | Settings"
  row
    heading "Finance Review"
    right
    select "Claimant: All"
  row
    card "Awaiting review | 9 | past manager approval"
    card "Ready for export | 6 | approved and waiting"
    card "Exported this month | 46 | across 2 payroll files"
  row
    heading "Claims past manager approval"
    right
    button "Review next" primary -> FinanceClaimDetail
  tabs "Awaiting review | Ready for export | Exported"
  table "Claimant | Claim | Total | Submitted" -> FinanceClaimDetail
    row "Maya Patel | Client workshop in Leeds | 214.60 | 20 Sep"
    row "Priya Nair | Team lunch, sprint review | 86.40 | 19 Sep"
    row "Ken Sato | Design conference ticket | 340.00 | 17 Sep"

screen FinanceClaimDetail "A finance reviewer checks a claim against policy and readies it for export"
  navbar "Expense Claims"
  sidebar "Finance Queue -> FinanceQueue | Exports -> FinanceExports | My Claims -> MyClaims | Settings"
  breadcrumb "Finance Review / Maya Patel / Client workshop in Leeds"
  row
    heading "Client workshop in Leeds"
    badge "Awaiting finance" info
  text "Maya Patel — approved by J. Weber — 214.60 total"
  split 60/40
    left
      heading "Expense lines"
      table "Date | Category | Description | Amount | Receipt"
        row "10 Oct | Travel | Train to Leeds | 89.50 | View"
        row "10 Oct | Meals | Dinner with the client | 68.20 | View"
      row
        right
        button "Return claim" -> FinanceReturnClaim
        button "Approve for export" primary -> FinanceQueue
    right
      heading "Activity"
      text "20 Sep — Maya submitted the claim"
      text "21 Sep — J. Weber approved it"

screen FinanceReturnClaim "A finance reviewer sends a claim back with a comment for correction"
  navbar "Expense Claims"
  sidebar "Finance Queue -> FinanceQueue | Exports -> FinanceExports | My Claims -> MyClaims | Settings"
  breadcrumb "Finance Review / Maya Patel / Return"
  heading "Return claim for correction"
  text "Client workshop in Leeds — Maya Patel — 214.60 total"
  textarea "Why is this being returned? — e.g. duplicate hotel night on 9 Oct"
  row
    right
    button "Cancel" -> FinanceClaimDetail
    button "Return claim" primary -> FinanceQueue

screen FinanceExports "A finance reviewer downloads the payroll file and audits past exports"
  navbar "Expense Claims"
  sidebar "Finance Queue -> FinanceQueue | Exports -> FinanceExports | My Claims -> MyClaims | Settings"
  breadcrumb "Finance Review / Exports"
  row
    heading "Payroll Exports"
    right
    button "Download payroll file" primary  // in place — downloads every approved claim not yet exported
  text "The file holds every approved claim that has not been exported yet. Downloading marks each included claim exported with the date, and every affected employee is emailed."
  heading "Past exports"
  table "Exported | Claims | Total | File"
    row "30 Sep 2026 | 46 | 3842.10 | CSV"
    row "15 Sep 2026 | 38 | 2954.75 | CSV"
  text "Each row's file can be downloaded again — check the exported date on a claim before re-loading a file, so nothing is reimbursed twice."

flow "Submit a claim"
  role "Employee"
  description "An employee drafts a claim with receipts, submits it and follows its journey"
  MyClaims
  NewClaim
  MyClaimDetail
  EditClaim

flow "Approve team claims"
  role "Manager"
  description "A manager reviews their reports' claims and approves or returns each one"
  ManagerQueue
  ManagerClaimDetail
  ManagerReturnClaim

flow "Finance review and export"
  role "FinanceReviewer"
  description "A finance reviewer checks approved claims, returns faulty ones and runs the payroll export"
  FinanceQueue
  FinanceClaimDetail
  FinanceReturnClaim
  FinanceExports