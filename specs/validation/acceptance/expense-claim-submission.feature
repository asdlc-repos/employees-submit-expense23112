Feature: Submitting expense claims

  @story-1
  Rule: An employee submits a claim as a bundle of dated, categorized expense lines

    Scenario: Submitting a claim with several lines
      Given Maya is an employee who has drafted a claim titled uniquely for this run
      And the claim holds 3 expense lines, each dated, categorized, priced and described
      When Maya submits the claim
      Then the claim stands awaiting her manager's approval
      And the claim's total is the sum of its 3 line amounts

    @negative
    Scenario: A claim with no expense lines is refused
      Given Maya has drafted a claim with no expense lines
      When Maya tries to submit the claim
      Then the claim does not leave draft

  @story-2
  Rule: Every expense line carries a receipt image before the claim can be submitted

    Scenario: Submitting a claim whose lines all have receipts
      Given Maya has drafted a claim with 2 expense lines, each with a receipt image attached
      When Maya submits the claim
      Then the claim stands awaiting her manager's approval

    @negative
    Scenario: A line without a receipt blocks submission
      Given Maya has drafted a claim with 2 expense lines and only one has a receipt attached
      When Maya tries to submit the claim
      Then the claim does not leave draft

  @story-1
  Rule: An employee may keep editing a claim until it is submitted

    Scenario: Editing a draft claim
      Given Maya has drafted a claim
      When Maya adds another expense line to the draft
      Then the draft holds the added line

    @negative
    Scenario: A submitted claim can no longer be edited
      Given Maya's claim stands awaiting her manager's approval
      When Maya tries to change one of its expense lines
      Then the claim's lines are unchanged

  @story-3
  Rule: An employee can see where each of their claims stands

    Scenario: The employee sees the status of a submitted claim
      Given Maya has submitted a claim
      When Maya opens her claims
      Then she sees the claim standing awaiting her manager's approval

    @negative
    Scenario: An employee sees only their own claims
      Given Maya has submitted a claim and Leo has drafted his own claim
      When Maya opens her claims
      Then she sees her claim and not Leo's