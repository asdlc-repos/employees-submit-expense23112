Feature: Manager approval

  @story-6
  Rule: A manager reviews the claims their direct reports have submitted

    Scenario: The manager's queue lists a report's submitted claim
      Given Maya reports to Jonas and has submitted a claim
      When Jonas opens his claims awaiting approval
      Then he sees Maya's claim in the queue

    @negative
    Scenario: A manager does not see claims from outside their reports
      Given Maya reports to Jonas and Priya reports to Ken
      And Priya has submitted a claim
      When Jonas opens his claims awaiting approval
      Then he does not see Priya's claim

  @story-7
  Rule: A manager approves or returns a submitted claim

    Scenario: Approving a claim sends it to finance review
      Given Jonas's queue holds Maya's submitted claim
      When Jonas approves the claim
      Then the claim stands awaiting finance review

    Scenario: Returning a claim sends it back with a comment
      Given Jonas's queue holds Maya's submitted claim
      When Jonas returns the claim with the comment "amount doesn't match the receipt"
      Then the claim stands returned to Maya
      And the claim shows the comment

    @negative
    Scenario: A claim already approved cannot be approved again
      Given Jonas has already approved Maya's claim and it stands awaiting finance review
      When Jonas tries to approve the claim again
      Then the claim's history holds exactly one approval by Jonas