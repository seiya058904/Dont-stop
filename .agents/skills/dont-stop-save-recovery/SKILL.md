---
name: dont-stop-save-recovery
description: Use when editing or auditing save persistence, Demo.gd, Don't stop/game/config/CampSaveStore.gd, SaveDialog.gd, cross-process recovery journals (.recovery/.previous/.recovered-*), or Web bad-save UX in Don't stop.
---

# Don't Stop Save Durability & Cross-Process Recovery

## 1. Corrupt-Save Serial Transaction (`creating_new_save`)
- Entering `creating_new_save` pauses gameplay, disables exit, locks focus, and rejects all gameplay/save mutations until IndexedDB/disk confirmation completes or rolls back `.previous`.
- Cross-process recovery uses `.recovery` SHA-256 journals, `.previous`, and legacy `.recovered-<SHA256>.json`; never classify or delete them as caches.

## 2. Targeted Verification & Claim Boundaries
- Run `R1RecoveryJournal` and `python3 "Don't stop/tools/test-cross-process-recovery.py" --godot <path>`.
- Verified scope covers software faults/races/process interruption; do **not** claim verified protection against sudden power loss, OS kernel crash, or hardware storage corruption.
- **Known residual risk (`RISK-WEB-BACKUP-CONFIRM`)**: `Demo.gd:export_bad_save()` uses `download_buffer()`, which cannot prove the browser actually saved the downloaded file to disk — surface honestly in UX/reports without claiming confirmed local backup.
