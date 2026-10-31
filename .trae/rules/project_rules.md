# CamCardClone project rules
Read PROJECT_RULES.md, docs/规格说明书.md and the current openspec/ artifacts before editing.
Read all artifacts of replicate-camcard-core-slice.
Scope is limited to the CamCard card-digitization and contact-management slice; do not add account, membership, payment, cloud sync, CRM, QR or AI-intelligence features.
Use ADDED for the new app-shell, card-library, card-holder and card-scanner capabilities; there is no MODIFIED baseline.
Keep the BusinessCard schema and BusinessCardRepository protocol stable across weeks.
Never let AI fabricate a field that is absent on the card; unknown fields stay nil.
Keep deterministic behaviour aligned with reference tests T01-T20; score OCR with the fixed Ground Truth set.
ScannerEntryView is no longer a placeholder: step 4 of 3.1 replaced it with a real capture page (preview, capture, photo import, retake/cancel, with permission and cancel semantics unit-tested in ScannerEntryViewModel). Detection, OCR, field extraction and save are not wired to that page yet, so do not present it as a working recognition loop.
Record real test/build results. Blocked checks stay unchecked. Do not archive prematurely.
