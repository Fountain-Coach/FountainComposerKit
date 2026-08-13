# FountainComposerKit

The FCIS-governed, product-neutral Swift contract for Copilot composer turns and remote attachment custody.

It defines text turns, image/file attachment manifests, idempotent admission receipts, revocation receipts, and
deterministic fixtures. It deliberately does not own Reframe views, model providers, FountainStore, PhotoKit, iCloud,
or a server filesystem. Reframe remains the product adapter; the remote Attachment Cloud remains the byte authority.
