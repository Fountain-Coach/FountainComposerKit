# FountainComposerKit

The FCIS-governed, product-neutral Swift contract for Copilot composer turns and remote attachment custody.

It defines text turns, image/file attachment manifests, idempotent admission receipts, revocation receipts, a typed
HTTPS client/handler, and a filesystem-backed Attachment Cloud store. It deliberately does not own Reframe views,
model providers, FountainStore, PhotoKit, or iCloud. Reframe remains the product adapter; the remote Attachment Cloud
remains the byte authority.

The hosted seam is `POST /v1/attachments/admit`. The request carries a typed `AttachmentAdmissionRequest`; the
response is an `AttachmentReceipt`. The server persists bytes and the idempotency receipt remotely before Reframe
keeps the attachment reference in its composer state.

## Composer intake ceiling

The shared contract is intentionally generous but finite: one turn may contain up to **8 attachments**, each up to
**50 MiB**, with **200 MiB total**. Reframe validates a complete selection or paste batch before the first network
call, so an over-limit batch cannot partially enter the turn. The Attachment Cloud independently enforces the
per-object limit and rejects oversized transport requests. These are admission limits, not model-context limits.
