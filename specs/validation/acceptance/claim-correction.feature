Feature: Correcting returned claims

  @story-4
  Rule: Only the employee who owns a returned claim can correct it

    Scenario: The owner corrects and resubmits
      Given Maya's claim has been returned with the comment "receipt for the taxi is missing"
      When Maya attaches the missing receipt and resubmits the claim
      Then the claim stands awaiting her manager's approval again

    @negative
    Scenario: Another employee cannot correct someone else's claim
      Given a claim owned by Maya has been returned
      When Leo, another employee, tries to open the claim for editing
      Then Leo cannot see Maya's claim

  @story-4
  Rule: A returned claim keeps its lines and comments through correction

    Scenario: The returned claim still holds what the employee filed
      Given Maya's claim with 3 expense lines has been returned with a comment
      When Maya opens the claim to correct it
      Then the claim still holds those 3 lines and shows the return comment