---
name: object-storage
description: How THIS organization stores uploaded files and images — always in an S3 bucket, declared as an external object-storage dependency and accessed with the S3 SDK. Apply whenever a requirement needs to persist an image, screenshot, photo, scan, upload, attachment, document, or any binary/blob — anything that "has to be stored somewhere". Do NOT put blobs in the database.
metadata:
  aep:
    kind: org
---

# Object storage (our org standard: S3)

## What this skill does

Our organization keeps all uploaded files and images in **Amazon S3**, never in
the application database. Whenever a requirement says something must be *stored*
— a screenshot, a photo, a scanned document, an upload, an attachment —
that object goes in an **S3 bucket**. This skill tells the agent to reach for S3
(as an external dependency) instead of inventing local disk storage, a database
BLOB column, or a different cloud provider.

## When to apply

Apply this skill when the design or a requirement involves persisting any of:

- an uploaded **image / screenshot / photo / scan**,
- a **file / document / attachment** a user submits,
- any **binary object / blob** that is not structured relational data.

If the thing to store is structured records (rows, fields, relationships), that
is a **database**, not this skill. Files and images → S3.

## How to consume it

1. **Declare an external object-storage dependency** on the component that owns
   the upload (the backend/API, not the web app). It is an `external` dependency
   (a third-party service reached with credentials), NOT a platform resource.

2. **The dependency supplies these connection values** (injected as environment
   variables into the component). Read them from the environment — never hardcode
   them:

   | Value | Env var | Notes |
   |---|---|---|
   | Access key id | `AWS_ACCESS_KEY_ID` | secret |
   | Secret access key | `AWS_SECRET_ACCESS_KEY` | secret |
   | Bucket name | `AWS_S3_BUCKET_NAME` | which bucket to write to |
   | Region | `AWS_REGION` | fixed to `us-east-1` — default to it if unset |

3. **Use the S3 SDK** for the component's language (e.g. the AWS SDK for Go/JS/
   Python, or any S3-compatible client) to `PutObject` on upload.

4. **Display a stored object via a short-lived presigned `GetObject` URL that the
   SPA fetches WITH auth.** A signed-in web app cannot show a protected file by
   pointing `<img src>` (or a download link) straight at the auth-gated backend
   endpoint: the browser attaches no bearer token to an `<img>`/navigation
   request, so the gateway rejects it (401) and the image silently never appears.
   Instead, the SPA calls the backend with a normal authenticated `fetch` (bearer
   attached) to obtain the presigned URL, then sets `<img src={presignedUrl}>`. S3
   serves the presigned URL directly — it carries its own signature, needs no
   header, and `<img>` rendering needs no CORS. Have the backend **return** the
   presigned URL (e.g. as JSON); do NOT `302`-redirect to it, since a redirect
   from a protected endpoint is just as unreachable by `<img>`.

5. **Store only the object key + metadata in the database** — e.g. the S3 key,
   content type, size, and who uploaded it. The bytes live in S3; the database
   row points at them. Never store the file bytes in the database.

## Conventions

- Give each object a stable, collision-free key, e.g.
  `<entity>/<entity-id>/<uuid>-<original-filename>`.
- Set the object's `Content-Type` from the upload so it renders correctly on
  retrieval.
- Treat the credentials as secrets: they arrive via the dependency's value
  entry, are injected as env vars, and are rotatable — the code only ever reads
  them from the environment.
