## 2026-11-24 — Stage 3a rebase audit (PR #645)

Base: `75800b4eba7a11835c7235f016e02d6420e0d940`; original Stage 3a head: `65a72eac0cc1ec1f347cfa504b0cfb7948ad80f5`; pre-Stage-3a canonical checkpoint: `a8f7db3e99123489771d260727a839c1e4e7e2a9`. Backup `backup/pine-stage3a-before-rebase-20261124`. #643 merged; #644 API reports merged into the Stage 1 branch, so retain compatibility frontend until separate audit.

- Transplant only Stage 3a delta (10 paths), not obsolete Stage 2 history. Reuse exact blobs for runtime, engine, semantic rules, canonical tests and Stage 3a reports.
- `chart_indicator_library.dart`: transplant Stage 3a compiler and diagnostic fallback, retain `PineFrontendAnalysis frontendAnalysis`, alternative import and existing Arabic diagnostic suffix.
- `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`: preserve base history and append Stage 3a historical entries; prior CI numbers refer to old heads only.
- `verify-flutter-range.yml` and `pine-v6-stage3a-no-apk.yml`: retain both frontends, Stage 1 and Stage 3a in the established no-APK regression gate.
- `pine_frontend_v6_test.dart`: update old assertion that supported var/if is rejected by chart; compatibility analyzer remains analysis-only. No tests deleted.
- No main changes, no APK, no merge by assistant. CI and differential result pending. Stage 3b blocked until owner merges #645 and cleanup PR.
