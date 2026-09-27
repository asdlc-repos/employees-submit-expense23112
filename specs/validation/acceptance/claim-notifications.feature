Feature: Claim notifications

  @story-5
  Rule: An employee receives an email when their claim is approved, returned or exported

    Scenario: A manager approval reaches the employee by email
      Given Maya's claim stands awaiting her manager's approval
      When her manager Jonas approves the claim
      Then an email about the approval is sent to Maya

    Scenario: A finance return reaches the employee by email
      Given Maya's claim stands awaiting finance review
      When Fatima from finance returns the claim with a comment
      Then an email about the return is sent to Maya

    Scenario: An export reaches the employee by email
      Given Maya's claim stands ready for export
      When Fatima from finance downloads the payroll file including Maya's claim
      Then an email about the export is sent to Maya

  @story-8
  Rule: A manager receives an email when a claim awaits their approval

    Scenario: Submission alerts the manager
      Given Maya reports to Jonas
      When Maya submits a claim
      Then an email about the claim awaiting approval is sent to Jonas

    @negative
    Scenario: A draft claim raises no manager email
      Given Maya has drafted a claim but not submitted it
      Then Jonas receives no email about the claim