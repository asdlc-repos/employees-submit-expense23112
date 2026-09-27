Feature: Claim notifications

  @story-5
  Rule: An employee is notified when their claim is approved, returned or exported

    Scenario: A manager approval notifies the employee
      Given Maya's claim stands awaiting her manager's approval
      When her manager Jonas approves the claim
      Then a notification about the approval is recorded for Maya

    Scenario: A finance return notifies the employee
      Given Maya's claim stands awaiting finance review
      When Fatima from finance returns the claim with a comment
      Then a notification about the return is recorded for Maya

    Scenario: An export notifies the employee
      Given Maya's claim stands ready for export
      When Fatima from finance downloads the payroll file including Maya's claim
      Then a notification about the export is recorded for Maya

  @story-8
  Rule: A manager is notified when a claim awaits their approval

    Scenario: Submission notifies the manager
      Given Maya reports to Jonas
      When Maya submits a claim
      Then a notification about the claim awaiting approval is recorded for Jonas

    @negative
    Scenario: A draft claim raises no manager notification
      Given Maya has drafted a claim but not submitted it
      Then no notification about the claim is recorded for Jonas