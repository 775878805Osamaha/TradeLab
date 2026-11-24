# AHV10 acceptance gap audit — step 1 only
Owner-provided exact source, 443 logical lines including blank/comment lines, no appended terminal newline. Original Git blob `efd3b24b629fbfa5baf0a22b01af9a4ba078ace1`. First line `//@version=6`; last line:
```pine
    strategy.exit((buy or inLong) ? "BUY EXIT" : "SELL EXIT", from_entry=(buy or inLong) ? "BUY" : "SELL", stop=curStop, limit=targetLine)
```
Audit branch based on #648 `498c15ab1303d6df61f9160c83212327d9ece9eb`; no runtime/library/parser changes, no merge or APK. #647 merged by owner at `fd1ca51393a39df278502f5d6647cd125d69c4bb`: [CI](https://github.com/775878805Osamaha/TradeLab/actions/runs/45503113968) 1068 PASS/0 FAIL. #648 retargeted to integration, mergeable clean, [exact head CI](https://github.com/775878805Osamaha/TradeLab/actions/runs/45408293712) 1099 PASS/0 FAIL/1 optional JSON SKIP; 10 CSV tests passed. Base tree equals #647 tested tree; retarget itself did not trigger fresh CI. #648 remains unmerged.
## Real canonical analysis
[Run 45503505713](https://github.com/775878805Osamaha/TradeLab/actions/runs/45503505713), head `8bcac03e2b2b9288af5d348feeb5b521a4557a8f`: 1 diagnostic audit test passed, no execution of AHV10. Status invalid; 7343 tokens, 383 recovery AST statements; 13 parser and 48 semantic diagnostics, no lexer diagnostics. Semantic analyzer stops at 48 (last reported line 221); not a complete semantic pass. Compiler refused at 127:22. Raw diagnostic records: `docs/evidence/PINE_AHV10_FRONTEND_CI_45503505713.json`. Some undefined names are cascading from failed tuple binding; not independent missing features.
- parser:trailing_tokens 127:22 — Unexpected tokens after statement
- parser:trailing_tokens 142:23 — Unexpected tokens after statement
- parser:trailing_tokens 143:20 — Unexpected tokens after statement
- parser:trailing_tokens 144:16 — Unexpected tokens after statement
- parser:trailing_tokens 223:10 — Unexpected tokens after statement
- parser:expected_expression 378:11 — Expected Pine expression
- parser:expected_token 379:8 — Expected =
- parser:expected_token 380:8 — Expected =
- parser:expected_token 381:8 — Expected =
- parser:expected_token 382:8 — Expected =
- parser:expected_expression 393:35 — Expected Pine expression
- parser:expected_token 405:11 — Expected =
- parser:trailing_tokens 441:79 — Trailing tokens in local block
- semantic:logical_type 116:10 — Expected boolType, found stringType
- semantic:logical_type 116:49 — Expected boolType, found stringType
- semantic:condition_type 119:37 — Expected boolType, found stringType
- semantic:logical_type 124:36 — Expected boolType, found stringType
- semantic:unknown_function 126:30 — Unknown Pine function: ticker.standard
- semantic:unknown_function 126:12 — Unknown Pine function: ticker.heikinashi
- semantic:undefined_name 127:2 — Undeclared Pine identifier: haO
- semantic:undefined_name 127:7 — Undeclared Pine identifier: haH
- semantic:undefined_name 127:12 — Undeclared Pine identifier: haL
- semantic:undefined_name 127:17 — Undeclared Pine identifier: haC
- semantic:arithmetic_type 128:17 — Arithmetic requires numeric arguments
- semantic:undefined_name 129:13 — Undeclared Pine identifier: haC
- semantic:undefined_name 129:19 — Undeclared Pine identifier: haO
- semantic:undefined_name 129:29 — Undeclared Pine identifier: haC
- semantic:undefined_name 129:35 — Undeclared Pine identifier: haO
- semantic:undefined_name 130:42 — Undeclared Pine identifier: haO
- semantic:undefined_name 130:47 — Undeclared Pine identifier: haC
- semantic:undefined_name 130:54 — Undeclared Pine identifier: haL
- semantic:undefined_name 131:34 — Undeclared Pine identifier: haH
- semantic:undefined_name 131:49 — Undeclared Pine identifier: haO
- semantic:undefined_name 131:54 — Undeclared Pine identifier: haC
- semantic:undefined_name 132:66 — Undeclared Pine identifier: haC
- semantic:undefined_name 132:72 — Undeclared Pine identifier: haH
- semantic:undefined_name 133:66 — Undeclared Pine identifier: haC
- semantic:undefined_name 133:72 — Undeclared Pine identifier: haL
- semantic:undefined_name 140:108 — Undeclared Pine identifier: barmerge
- semantic:undefined_name 142:2 — Undeclared Pine identifier: macdL
- semantic:undefined_name 142:9 — Undeclared Pine identifier: macdS
- semantic:undefined_name 142:16 — Undeclared Pine identifier: macdH
- semantic:undefined_name 143:2 — Undeclared Pine identifier: diP
- semantic:undefined_name 143:7 — Undeclared Pine identifier: diM
- semantic:undefined_name 143:12 — Undeclared Pine identifier: adxVal
- semantic:undefined_name 144:2 — Undeclared Pine identifier: stVal
- semantic:undefined_name 144:9 — Undeclared Pine identifier: stDir
- semantic:invalid_callee 149:14 — Expected function name
- semantic:invalid_callee 170:13 — Expected function name
- semantic:invalid_callee 171:13 — Expected function name
- semantic:invalid_callee 172:12 — Expected function name
- semantic:invalid_callee 173:12 — Expected function name
- semantic:logical_type 221:38 — Expected boolType, found stringType
- semantic:logical_type 221:66 — Expected boolType, found stringType
- semantic:logical_type 221:114 — Expected boolType, found stringType
- semantic:logical_type 221:141 — Expected boolType, found stringType
- semantic:logical_type 221:191 — Expected boolType, found stringType
- semantic:logical_type 221:218 — Expected boolType, found stringType
- semantic:condition_type 221:267 — Expected boolType, found stringType
- semantic:condition_type 221:313 — Expected boolType, found stringType
- semantic:condition_type 221:359 — Expected boolType, found stringType
## Static gap inventory (separate from actual diagnostics)
`docs/evidence/PINE_AHV10_STATIC_SITES_2026-11-25.json` contains exact 1-based line/column source locations for candidate missing/partial support across the whole file, including repeated sites, not 1:1 independent features. Cross-checked against canonical parser, semantic and advanced executor allowlist. Counts: {"strategy":19,"لغة":286,"عرض":168,"مكتبة":69,"بيانات":19,"request.security":8}. No claim that all diagnostics after the cap were emitted or that unlisted constructs have proven parity. Numeric inputs return defaults only, named series history already supported within bounds (e.g. emaMid[slopeBars]), generic expression history not. Current parser treats na as literal before postfix calls; actual invalid_callee sites confirm the defect. The runtime permits na/nz but canonical parser path must work. String equality exists but + is numeric-only. Member expressions have no runtime evaluation route; semantic types for str.contains, syminfo.mintick, timeframe.isminutes and other builtins need correction. TA already has EMA/RSI/ATR/SMA/highest/lowest numeric paths, not verified in this strategy. MACD library-only, DMI/Supertrend absent. Strategy declaration, entries/exits and position/closedtrade state absent from advanced executor. No strategy.close call in this source. Plot handle needs independent rendering representation; five plot calls, twelve plotshape, one fill, one bgcolor, one table.new, 32 table.cell, one alert. Table/map state and chart viewport require isolation from trades.
- strategy declaration, orders, state and statistics (19 sites): 2:1, 281:73, 282:74, 285:126, 304:10, 305:11, 306:9, 307:11, 359:13, 362:28, 362:72, 362:128, 371:11, 372:13, 423:55, 441:5, 441:48, 441:64, 443:5
- numeric input returns default only (43 sites): 14:13, 16:13, 17:10, 20:13, 22:11, 24:9, 26:11, 28:10, 32:10, 33:13, 37:10, 38:12, 41:10, 43:12, 45:11, 48:11, 49:10, 50:13, 52:10, 53:12, 54:13, 56:9, 59:12, 60:9, 62:10, 64:12, 66:12, 68:12, 70:15, 74:10, 75:10, 78:10, 80:10, 81:11, 83:10, 86:13, 87:10, 88:11, 89:11, 91:10, 92:9, 94:11, 95:10
- input metadata not enforced/option array not executable (161 sites): 14:59, 14:71, 14:81, 15:72, 16:66, 16:82, 17:64, 17:74, 17:85, 18:65, 18:138, 19:60, 20:63, 20:73, 20:84, 21:61, 22:68, 22:78, 22:89, 23:77, 24:53, 24:65, 25:60, 26:80, 26:90, 26:101, 27:75, 28:71, 28:81, 29:60, 30:69, 31:62, 32:35, 32:45, 33:50, 33:62, 34:55, 35:52, 36:74, 37:35, 37:45, 38:74, 38:86, 38:99, 39:73, 40:56, 41:45, 41:57, 42:65, 43:60, 43:72, 43:82, 44:70, 45:60, 45:72, 45:86, 46:95, 47:78, 48:43, 48:53, 49:43, 49:53, 50:62, 50:72, 50:83, 51:72, 52:54, 52:64, 52:75, 53:57, 53:67, 53:78, 54:63, 54:75, 54:89, 55:68, 56:54, 56:64, 56:76, 57:80, 58:57, 59:77, 59:89, 59:99, 60:41, 60:51, 61:87, 62:65, 62:77, 62:87, 63:72, 64:62, 64:75, 64:89, 65:92, 66:64, 66:74, 66:85, 67:64, 68:67, 68:77, 68:89, 69:74, 70:69, 70:79, 70:91, 71:66, 72:57, 72:85, 73:65, 74:57, 74:67, 74:79, 75:44, 75:54, 75:66, 76:63, 77:58, 78:60, 78:70, 78:82, 79:65, 80:43, 80:53, 80:65, 81:63, 81:75, 81:85, 82:69, 83:67, 83:77, 83:89, 84:85, 85:54, 85:94, 86:69, 86:81, 87:84, 87:96, 87:106, 88:51, 88:63, 89:62, 89:74, 89:88, 90:55, 91:59, 91:71, 92:71, 92:83, 93:54, 94:67, 94:79, 95:69, 95:81, 96:54, 97:62, 98:84, 99:58, 100:50, 100:87
- other input forms (44 sites): 15:15, 18:13, 19:12, 21:13, 23:9, 25:11, 27:12, 29:10, 30:9, 31:10, 34:14, 35:11, 36:10, 39:11, 40:10, 42:11, 44:11, 46:14, 47:12, 51:12, 55:9, 57:9, 58:9, 61:10, 63:12, 65:11, 67:12, 69:15, 71:10, 72:11, 73:13, 76:10, 77:10, 79:10, 82:10, 84:9, 85:14, 90:9, 93:12, 96:13, 97:14, 98:11, 99:13, 100:11
- qualified visual constants/functions and visible range (115 sites): 101:31, 101:65, 101:79, 321:68, 321:101, 322:74, 322:107, 323:48, 323:73, 323:86, 326:61, 326:84, 326:109, 326:126, 327:61, 327:84, 327:109, 327:125, 328:47, 328:71, 328:96, 328:119, 328:137, 329:50, 329:76, 329:101, 329:122, 329:140, 330:72, 330:99, 330:124, 330:143, 331:72, 331:101, 331:126, 331:145, 332:70, 332:97, 332:122, 332:141, 333:70, 333:99, 333:124, 333:143, 334:70, 334:97, 334:122, 334:139, 335:70, 335:99, 335:124, 335:141, 336:70, 336:97, 336:122, 336:141, 337:70, 337:99, 337:124, 337:143, 346:60, 346:91, 347:53, 347:83, 348:57, 348:88, 349:26, 349:36, 392:11, 405:34, 405:69, 405:79, 405:110, 406:69, 406:109, 406:119, 407:67, 407:107, 407:117, 408:67, 409:84, 410:67, 411:86, 412:73, 413:92, 414:72, 415:88, 416:74, 417:89, 418:74, 419:97, 419:110, 420:71, 421:101, 421:114, 422:72, 423:100, 424:75, 425:65, 426:81, 427:87, 428:80, 429:87, 430:73, 431:95, 432:75, 433:87, 434:75, 435:89, 436:81, 437:95, 441:166, 441:223, 441:317, 441:429
- string functions; contains also has wrong semantic return type (35 sites): 116:10, 116:49, 118:9, 221:38, 221:66, 221:114, 221:141, 221:191, 221:218, 221:267, 221:313, 221:359, 221:405, 370:25, 403:26, 403:57, 409:42, 411:42, 413:42, 415:42, 417:42, 419:42, 421:42, 423:42, 427:43, 429:43, 431:43, 433:43, 435:43, 437:43, 441:146, 441:199, 441:255, 441:351, 441:401
- symbol/timeframe/bar state/session/volume data (19 sites): 116:23, 116:62, 117:11, 118:22, 124:14, 124:36, 125:28, 126:46, 127:51, 128:19, 145:17, 149:17, 149:22, 220:6, 223:37, 242:157, 378:27, 385:9, 441:114
- security/context/ticker/merge semantics (8 sites): 126:12, 126:30, 127:24, 127:105, 140:10, 140:108, 223:12, 223:78
- tuple declaration (5 sites): 127:1, 142:1, 143:1, 144:1, 223:1
- MACD tuple (1 sites): 142:25
- TA not in registry (16 sites): 143:22, 144:18, 168:9, 169:8, 180:15, 181:15, 194:13, 195:13, 196:13, 197:13, 206:13, 207:13, 214:13, 215:13, 230:13, 231:13
- na() token parsed as literal rather than callable (12 sites): 149:14, 170:13, 171:13, 172:12, 173:12, 237:14, 238:14, 271:7, 280:17, 384:14, 393:11, 401:10
- history of function result (5 sites): 150:9, 151:9, 152:16, 155:10, 156:9
- math functions outside runtime allowlist (5 sites): 150:9, 151:9, 362:118, 378:15, 393:39
- plot options and handle vs numeric output (5 sites): 321:13, 322:13, 346:1, 347:1, 348:1
- display primitives and table (48 sites): 323:1, 326:1, 327:1, 328:1, 329:1, 330:1, 331:1, 332:1, 333:1, 334:1, 335:1, 336:1, 337:1, 349:1, 405:24, 406:1, 407:1, 408:1, 409:1, 410:1, 411:1, 412:1, 413:1, 414:1, 415:1, 416:1, 417:1, 418:1, 419:1, 420:1, 421:1, 422:1, 423:1, 424:1, 425:1, 426:1, 427:1, 428:1, 429:1, 430:1, 431:1, 432:1, 433:1, 434:1, 435:1, 436:1, 437:1, 441:81
- int() cast (2 sites): 378:11, 393:35
- typed map declaration/constructor (8 sites): 379:5, 379:29, 380:5, 380:31, 381:5, 381:31, 382:5, 382:32
- mutable map operations (12 sites): 386:1, 386:28, 387:1, 387:30, 388:1, 388:30, 389:1, 389:31, 394:12, 395:14, 396:14, 397:15
- string concatenation requires string + (runtime numeric only) (4 sites): 403:13, 413:42, 437:43, 441:81
- typed table declaration (1 sites): 405:1
- comma-separated statements (1 sites): 441:79
## All security requests and Replay
- 127:24 same-timeframe HA tuple, no expression offset, lookahead_off. Safe at confirmed chart close if HA derived causally from matching standard OHLC and same timestamp/session, no future prefix reads. Need historical HA seed alignment. HA for signal only; fills on standard prices.
- 140:10 htfDir, lookahead_on, all four open/close references use [1] INSIDE requested context. For strictly higher TF this is TradingView's documented non-repainting pattern: previous confirmed higher-timeframe bar, available from start of next HTF interval. Default htfTf=60 on GOLD 1h is EQUAL TF, reads previous same-TF HA bar; no future leak. If user chooses lower TF, lookahead_on historical first intrabar vs realtime last intrabar can diverge; do not claim same semantics or change script. Explicit unsupported-context error or implement/test lower-TF separately, subject to owner decision. Aggregate standard bars by correct exchange session then compute HA in target context, do not aggregate HA candles or confuse [1] with chart offset.
- 223:12 second symbol SMT, same TF, no offset, lookahead_off. Safe only with timestamp-aligned closed secondary bars and cutoff; default gaps_off handling must never use future/partial secondary data. Gold maps to OANDA:XAGUSD. Unconditional call even if kSmt=false; smcPack enables kSmt; showSmc can display SMT even when filter off. Missing data when enabled must error explicitly; disabled-filter behavior and missing display data need explicit diagnostic/decision, no fake prices or quiet substitution. Test late/missing/gapped symbols, timestamp alignment and deliberate future poison.
Official refs: https://www.tradingview.com/pine-script-docs/faq/other-data-and-timeframes/ ; https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/ ; https://www.tradingview.com/pine-script-docs/concepts/repainting/ ; https://www.tradingview.com/pine-script-docs/concepts/non-standard-charts-data/ ; https://www.tradingview.com/pine-script-docs/concepts/strategies/ ; https://www.tradingview.com/pine-script-docs/concepts/chart-information/ .
## Proposed PR dependencies (not implementation)
1. Parser/type baseline: tuple declarations, callable na/int, comma statement sequence, typed generic/table declarations; diagnostic recovery cap remains explicit; AST and semantic tests, small slices, no V10-specific logic.
2. Input/builtins/string: bool/string/session/timeframe/symbol/options/group, valid overrides and qualifiers, typed symbol/timeframe/barstate, string ops/format, numeric casts. Parallel with TA formula work after shared signatures agreed.
3. Series history + TA: per-call expression history, barssince, pivots (confirm only after right bars), math.sum, MACD tuple binding, DMI/Supertrend independent reference fixtures. Can build numerical functions in parallel with parser, integrate only after tuple binding/typing. Regression existing GOLD reference.
4. Timestamped OHLCV and symbol/session contract, HA, then security same-TF and HTF alignment; parallel data work with language/TA. Tests deliberate future injection, gaps, offset in requested context. Second-symbol SMT follows security and data contract.
5. Strategy declarations, deterministic broker emulator, market/stop/limit orders and same-bar phase ordering, then position/closedtrade stats and adapters to paper/backtest. Can design and test standalone order engine in parallel after agreeing data and execution contract; do not reuse paper engine blindly. V10 entry+exit in same calculation with process_orders_on_close=true, pyramiding=0; do not retroactively apply new stops to earlier intrabar highs/lows; resolve stop/limit collision per documented assumptions, preserve phase visibility of position_size. No automatic trade in live market.
6. Map/time/week data and presentation, plot handles/styles/shapes/fill/bgcolor, table and alerts. Map state replay-isolated; visible-bar timestamp must not affect trading or disclose future, table update explicit fallback if not implemented. Presentation can proceed independently after output contract, stats after strategy.
7. Original acceptance runs with user-approved settings; separate log-only capture and trade list; HA/state/signals/trades comparison, absolute scoped results; no implementation before approval.
Effort relative sizing: language large (several small PRs), TA large, data medium-large, security very large, strategy very large, presentation large. No effort/date guarantee. Integration order respects dependency edges; concurrent branches should be rebased and tested, no owner merge by assistant.
