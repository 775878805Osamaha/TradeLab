# Pine integration continuation — 2026-11-27

Owner requested report mid-session. Do not merge into main or test/flutter-all-fixes-20261116. Integration-only merges authorized after actual CI success. No further APK (one-off already built). Do not edit ahv10.pine or add strategy-specific execution. No tolerance relaxation, no disabled tests. Original base fdf4b5da726b69d69b74d69e4611e198ddae62f9, last base CI 45998632828 1148/0/1. Integration before this doc b338b873242184872fa29bedc340787d149687a7. Original fixture blob efd3b24b629fbfa5baf0a22b01af9a4ba078ace1 verified.

## Verified merges into integration/pine-v10
- #654 CI 45510639021 (1153/0/1, historical PR head before retarget; subsequent combined CI confirms suite).
- #660 CI 46000885068 (one migration safety gate passes; desktop FFI synthetic archive; not real phone).
- #655 CI 46001135285 (1183/0/1).
- #659 CI 46001652706 (1210/0/1, 19 V2 columns with zero numeric/na mismatches; direct library, not whole strategy).
- #663 CI 46002089509 (1214/0/1): real Pine scalar scripts on V2 OHLC, independent oracle, poison replay. floor/sign/sum promoted; string/time/color subset not full support.
- #664 CI 46002645835 (1218/0/1): actual Pine barssince/pivot, call history with strict full-bar execution, poison replay. High ties and conditional local call history unresolved. AHV10 169 known_unimplemented, 17 syntax notices, 0 errors, 443 lines visited.

## Next action: repair #665 without merging failed head
Head 04988ce6be2f8b8a958d6d5e8d1476b0a26cf89c, target integration. First CI 46002910424 failed analyzer (2 unused imports removed). Second CI 46003160944: 1197 pass, 10 fail, 1 skipped in main; extra groups not run, incomplete suite. Four syntax tests in pine_v10_01_syntax_test.dart still assert runtime rejects now implemented valid tuple/comma forms. Replace only obsolete rejection assertions with actual execution/expected outputs, retain AST span, shape, duplicate and invalid cases, ensure unknown tuple shapes rejected. Six legacy/general-stage3b EMA regressions: new dispatch routes old AST EMA paths to SMA seed by default, breaking existing first-close semantics. Must preserve old default route (including pre-existing general AST scripts) and introduce explicit, testable opt-in selection of SMA-seeded EMA; new tuple MACD uses separate seeded candidates. Verify UI routing later, do not silently alter old output or loosen tolerance. CI has candidate 167 known_unimplemented and 14 syntax notices, not accepted until full green. New candidate observations from logs below:
TV_V2_INTERPRETER {"name":"macdL","rows":5334,"na_mismatches":0,"numeric_mismatches":0,"max_abs_error":5.243339096239197e-11,"max_index":243}
TV_V2_INTERPRETER {"name":"macdS","rows":5334,"na_mismatches":0,"numeric_mismatches":0,"max_abs_error":5.298517180563067e-11,"max_index":1890}
TV_V2_INTERPRETER {"name":"macdH","rows":5334,"na_mismatches":0,"numeric_mismatches":0,"max_abs_error":5.099032307498419e-11,"max_index":2321}
TV_V2_INTERPRETER {"name":"diP","rows":5334,"na_mismatches":0,"numeric_mismatches":0,"max_abs_error":4.999378688808065e-11,"max_index":600}
TV_V2_INTERPRETER {"name":"diM","rows":5334,"na_mismatches":0,"numeric_mismatches":0,"max_abs_error":4.9976023319686647e-11,"max_index":2512}
TV_V2_INTERPRETER {"name":"adx","rows":5334,"na_mismatches":0,"numeric_mismatches":0,"max_abs_error":4.999378688808065e-11,"max_index":3046}
TV_V2_INTERPRETER {"name":"stV","rows":5334,"na_mismatches":0,"numeric_mismatches":0,"max_abs_error":5.002220859751105e-11,"max_index":415}
TV_V2_INTERPRETER {"name":"stD","rows":5334,"na_mismatches":0,"numeric_mismatches":0,"max_abs_error":0.0,"max_index":0}
EMA_COMPAT {"length":3,"na_mismatch":2,"numeric_over_1e6":19,"last_affected_index":20,"affected":21}
EMA_COMPAT {"length":20,"na_mismatch":19,"numeric_over_1e6":160,"last_affected_index":178,"affected":179}
EMA_COMPAT {"length":50,"na_mismatch":49,"numeric_over_1e6":402,"last_affected_index":450,"affected":451}
EMA_COMPAT {"length":200,"na_mismatch":199,"numeric_over_1e6":1673,"last_affected_index":1871,"affected":1872}
No promotion claimed from failed PR. Run full suite again and compare exact tree before merging. User had authorized three serious distinct repair attempts; analyzer import fix and semantic compatibility repair are separate; no claim of exhausting attempts yet.

Then stage 2 inputs/context/maps, stage 3 local HA/security, stage 4 broker, stage 5 display, stage 6 UI, stage 7 warmup/isolate 50k, stage 8 unchanged AHV10 acceptance. For strategy reference data see #662 docs and append-only capture (not run in TradingView yet). No blanket TradingView parity claim. Need real List of Trades, settings, logs for broker tie cases. #658 temporary never merge. Do not start further new phases until #665 successful.

APK build run 46000698276 succeeded from exact original base, artifact 15197933103, applicationId com.example.tradelab_flutter.pinetest20261127, label TradeLab Test, debug signing, allowBackup=false, no sharedUserId, OAuth custom callback removed to avoid conflict (cTrader sign-in callback unavailable in QA). No physical device test. APK is not integration build and AHV10 cannot execute. No further build authorized by this one-off request.
