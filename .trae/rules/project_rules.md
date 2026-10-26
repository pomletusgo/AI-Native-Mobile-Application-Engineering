# CamCardClone project rules
Read PROJECT_RULES.md, docs/规格说明书.md and the current openspec/ artifacts before editing.
Read all artifacts of replicate-camcard-core-slice.
Scope is limited to the CamCard card-digitization and contact-management slice; do not add account, membership, payment, cloud sync, CRM, QR or AI-intelligence features.
Use ADDED for the new app-shell, card-library, card-holder and card-scanner capabilities; there is no MODIFIED baseline.
Keep the BusinessCard schema and BusinessCardRepository protocol stable across weeks.
Never let AI fabricate a field that is absent on the card; unknown fields stay nil.
Keep deterministic behaviour aligned with reference tests T01-T20; score OCR with the fixed Ground Truth set.
The first ScannerEntryView is a placeholder that only validates T02/T12.
Record real test/build results. Blocked checks stay unchecked. Do not archive prematurely.
