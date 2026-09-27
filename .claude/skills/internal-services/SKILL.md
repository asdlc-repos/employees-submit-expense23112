---
name: internal-services
description: "How THIS organization handles data and capabilities that another internal service already owns — the people/teams/org directory, and email/notifications. Never rebuild, re-model, re-seed, or hardcode that data, and never stand up your own mailer. Apply whenever a requirement needs employees, teams, managers, org structure, who-owns-what, or sending a notification/email — consume the existing service as a cross-project org-service dependency and discover its real API contract from the platform, and never guess endpoints."
metadata:
  aep:
    kind: org
---

# Internal services (our org standard: reuse, don't rebuild)

## What this skill does

Our organization already runs internal services that are the **systems of record**
for shared data and the providers of shared capabilities: a **company directory**
(people, teams, managers, org structure, who-owns-what) and a **notification
service** (sending email). When an app needs any of these, it must **consume the
existing service** rather than model, store, seed, or rebuild that data itself —
and it must not stand up its own mailer or its own copy of the directory.

## When to apply

Apply this skill when a requirement involves:

- **people / employees / teams / managers / org structure / who-owns-what** → the
  company **directory** service owns this.
- **sending email / notifying someone / alerting a person on an event** → the
  **notification / email** service provides this.

If the data is genuinely new and owned by THIS app (the records, uploads, and
decisions this app itself creates), that is the app's own database — not this skill.
This skill is only for data or capabilities that another internal service already
owns.

## How to consume it

1. **Do not rebuild the data or the capability.** Never create tables, seed rosters,
   or hardcode lists of people and teams; never write your own SMTP client. That all
   lives in an existing service.

2. **Declare a cross-project org-service dependency** on the existing service, from
   the component that needs it (the backend/API, not the web app). The dependency's
   `name` is the provider's EXACT component name as returned by the platform's
   endpoint discovery (`list_org_endpoints`), copied verbatim. The role words this
   skill uses — "directory", "notification service" — are DESCRIPTIONS, not names:
   the real component is usually named differently (the "directory" may be
   `employee-service`, "notifications" `email-service`). Look the name up; never
   coin one from the role — a coined name matches no provider and fails the build.

3. **Discover the real API contract from the platform** — use the platform's endpoint
   discovery to read the service's actual operations and schemas. **Never guess
   endpoint paths, request/response shapes, or the provider's name.**

4. **Call the discovered endpoints** to read directory data or to send a
   notification. Keep only a **reference** (an id) to that external data in this app's
   own database — never a duplicated copy of it.

## Conventions

- Resolve people/teams/managers through the directory at request time; persist the
  id/reference, not a copied record.
- For notifications, hand the recipient/subject/body to the existing email service;
  don't configure SMTP yourself.
- Treat these services as owned by other teams: depend only on their published
  contract as discovered from the platform, and don't assume undocumented behavior.
- To identify the signed-in caller — mapping them to a directory person for
  role/team scoping — see the [`identity-access`](../identity-access/SKILL.md) skill.
