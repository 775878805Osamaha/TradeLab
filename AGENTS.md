# AGENTS.md — Mandatory GitHub Continuation / Handoff Protocol

This repository contains an owner-requested durable handoff system. **Every AI coding agent (ChatGPT, Claude, Codex, etc.) must read and follow it.** Applies to edits made by an agent, including UI changes, refactors, tests, code/config uploads, PRs, merges, CI reruns, build/release/deploy actions, and failed attempts. Do not depend on prior conversation history.

## Before changing anything
1. Read [docs/HANDOFF.md](docs/HANDOFF.md) and the latest entries in [docs/CHANGE_REPORTS.md](docs/CHANGE_REPORTS.md) **on the relevant working branch**.
2. Check current remote branch HEAD, current PRs and the actual GitHub Actions result. Do not assume the static HEAD snapshot in a handoff file is still current.
3. Inspect actual source, permissions, secrets exposure and current test status before making claims. Distinguish verified from planned, failed, pending and untested.

## Mandatory REPORT + SAVE after every action
- After each meaningful **edit, commit, push/upload, branch creation, PR open/update/merge, CI/test/build/release/deploy**, append a dated event to `docs/CHANGE_REPORTS.md` and refresh `docs/HANDOFF.md` on the branch carrying the work. Prefer committing the report **with the code change**. If a merge creates a different SHA, add a follow-up report containing the actual merge SHA and CI URL/outcome.
- Every event must record: UTC date/time, action and result, repo+branch, actual commit SHA/PR/run/URL, changed files, exact behavior, validation (PASS/FAIL/PENDING/NOT RUN), blockers and **one next executable step**. A doc-only change also gets an entry.
- After saving, fetch the committed files from GitHub to verify they exist, then include their permanent URL in the response. If saving fails, clearly state that the handoff is not persisted; retry later rather than claim success.
- Update the status **after** external operations settle. Never mark pending CI as passed; log failures and correction commits, not just successes. Never erase historical log entries.
- Redact all API keys, passwords, auth tokens, emails, client/customer records, personal data and full broker account identifiers.
- **Do not add an auto-running GitHub Actions workflow for these reports**: quota/cost matters. This is a mandatory action for agents performing the change, not an automatically running background process. Never trigger paid builds just to update a Markdown report.

## Project guardrails
- XAUUSD والـForex عبر cTrader، والكريبتو عبر Binance؛ لا تُنشئ أسعار أو شموع وهمية، ولا تكشف بيانات Replay المستقبلية.
- التداول ورقي/تدريبي فقط؛ لا فتح صفقات بأموال حقيقية.
- لا APK أو Release تلقائيًا قبل اكتمال التطبيق. استثناء تاريخ 2026-11-20: طلب المستخدم نسخة APK واحدة للتجربة، ونُشرت بنجاح في [Release](https://github.com/775878805Osamaha/TradeLab/releases/tag/tradelab-phone-test-6cecd765d1c2)؛ انتهى هذا التفويض. أي بناء جديد يحتاج إذنًا صريحًا آخر؛ اترك `main` دون تغيير.
- لا ادعاء بنجاح اختبار جهاز حقيقي اعتمادًا على CI وحده.

## Resume entrypoints for a new chat
- [TradeLab](https://github.com/775878805Osamaha/TradeLab/blob/test/flutter-all-fixes-20261116/docs/HANDOFF.md)
- [OMX ERP](https://github.com/775878805Osamaha/omx-erp/blob/main/docs/HANDOFF.md)
- [OMEX Store](https://github.com/775878805Osamaha/omex-mobile-app/blob/main/docs/HANDOFF.md)

Start by verifying the active branch and latest documentation. A source change is incomplete until its handoff report is committed and linked.