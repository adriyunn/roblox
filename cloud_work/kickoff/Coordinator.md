Adrian: resume. The weekly limit reset. Two things first, then a cloud handoff.

**Critical path, unchanged:**
1. Dev3 is resuming now and writes the W2.1 verdict to `handoffs/STATUS_Dev3_MSI.md`. Batch 1 waits only on it; announce "batch 1 done" to WordAgent when it is in.
2. Dev1 resumes its three stopped workflows from cache (the WS-D re-freeze consolidate, the X01 build, the held-fish review) and re-freezes. Then the FishingConfig chain check by FableDev, then batch 2 final, then "batch 2 final" to WordAgent for the rows file.

**Cloud handoff.** While the machines were offline, a cloud session (claude.ai/code) built an offline package on branch `claude/hello-b2aghd` of `adriyunn/roblox`. It is pulled to `%CW%`. Read `%CW%\HANDOFF_COORDINATOR.md`: section 0 is a 24-row routing table (item, owner, action, what it unblocks). Everything in it was written WITHOUT the project files: new modules are tested here (11 suites, 576 checks under the Luau CLI) but drafts against existing code must be fitted by the named dev. Nothing carries a size/hash pair; identity is the commit SHA.

**Rulings I need from you, in this order** (templates in `%CW%\design\templates\RULING_REQUEST_TEMPLATE.md`):
- R1 `process/REVIEW_BACKUP_RULE.md`: a reviewer paused > 2 h is reassigned to the named backup. Yes/no, and the backup table.
- R2 `process/TOKEN_AUDIT.md`: the ten settings (effort medium for relays, 3-agent reviews, 30-minute mtime monitor instead of the per-line monitor). Apply what you accept today; Oct 4 cost 6.6 M tokens.
- R3 `design/WSD_shallow_shore.md`: `HomeMinDepthM = 0.35` instead of the 0.74 m horizontal bubble (POOL-1). Ask me to check the V-clips for trout in water under 0.35 m before ruling.
- R4 `design/WSI_touch_gamepad.md`: the `InputMap` seam in F1 alongside Dev1's #4, device profiles in R1.
- R5 `design/WSH_options_panel_additions.md`: three cheap rows in F1 if Dev2 has a slot; FOV in R1.
- R6 `design/PARITY_rows_F2plus.md` ruling 1: per-player or shared world clock. It decides P07/P16/P17 and `WorldClock`.
- R7 `process/GIT_MIGRATION.md` and `process/CLOUD_QUOTA.md`: when (after batch 2 is my proposal) and what moves to cloud sessions.
- R8 `process/R1_FishingConfig_split.md`: queue as the first R1 item.

**Routing after the rulings:** send each session its queue; the cloud package has one ready per session in `%CW%\kickoff\` (I am pasting them). Keep relays to one line with the commit SHA.

**For me:** `%CW%\process\ADRIAN_WINDOW.md` batches my four hand steps; tell me when batch 1 and the re-freeze are both ready and I will run it once. The demo clip list (V42-V70) is mine; the SFX/art list waits on my approval.
