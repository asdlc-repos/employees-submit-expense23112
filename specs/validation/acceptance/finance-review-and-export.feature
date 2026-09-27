Feature: Finance review and payroll export

  @story-9
  Rule: A finance team member reviews manager-approved claims together with their receipts

    Scenario: A manager-approved claim joins the finance queue
      Given Jonas has approved Maya's claim
      When Fatima from finance opens the review queue
      Then she sees Maya's claim with its expense lines and receipts

    @negative
    Scenario: A claim still awaiting its manager does not reach the finance queue
      Given Maya's claim stands awaiting Jonas's approval
      When Fatima opens the review queue
      Then Maya's claim is not in the queue

  @story-10
  Rule: Finance can return a claim for correction with a comment

    Scenario: Returning a claim sends it back to the employee
      Given Fatima's queue holds Maya's manager-approved claim
      When Fatima returns the claim with the comment "duplicate hotel night"
      Then the claim stands returned to Maya and shows the comment

  @story-11
  Rule: Finance approves a claim for export

    Scenario: Approving a claim readies it for export
      Given Fatima's queue holds Maya's manager-approved claim
      When Fatima approves the claim for export
      Then the claim stands ready for export

  @story-12
  Rule: The payroll export holds every approved claim that has not been exported yet

    Scenario: Exporting the approved claims
      Given 2 claims stand ready for export
      When Fatima downloads the payroll file
      Then the file holds both claims and each stands exported

    @negative
    Scenario: An exported claim is not exported a second time
      Given one claim has already been exported and no new claim is ready for export
      When Fatima downloads the payroll file
      Then the file does not hold the already-exported claim

  @story-13
  Rule: Finance can see which claims were exported and when

    Scenario: The export history shows past exports
      Given Fatima has downloaded a payroll file holding Maya's claim
      When Fatima opens the export history
      Then the history shows when Maya's claim was exported