# TradeLab — سجل تقارير التطوير في GitHub

### 2026-11-22 — Visual QA screenshots of real Flutter chart widget (CI PENDING)
- Added dedicated Flutter screenshot test and economical path-scoped GitHub Actions workflow. Captures dark/light viewport variants and crosshair, using source-shaped deterministic test-only BTC fixture (not production price history).
- Output is a GitHub Actions artifact for comparison with `docs/chart-reference/reference.png`. Never present synthetic test fixture as live broker data or claim Android pixel parity from Linux output.
- No APK, main or Vercel production changes. Await CI upload validation.



### 2026-11-22 — Offscreen price-axis chart parity (CI PENDING)
- Repaired legitimate empty-time-viewport behavior: do not erase y-axis and show fake market price 0–1 while valid cTrader/Binance candles exist outside viewport. Retain last chart-specific authenticated source scale or use a bounded nearest-edge real-price fallback.
- Time-axis dates remain absent when no source candle is visible; Replay only reads its revealed prefix and no synthetic BID/timestamps are emitted. Painter and scale cache covered by unit tests and CI.
- This is TradingView-style functional parity, not verified 100% Android pixel equivalence. main/prod/APK unchanged.


### 2026-11-22 — إغلاق #629 بنجاح: إصلاح انزلاق خطوط زمن الشارت
- [PR #629 MERGED](https://github.com/775878805Osamaha/TradeLab/pull/629) عند `81f1c0284f924cbd10d8b2ae6f2c7b36a660d8e1`؛ [CI #45057243714 success](https://github.com/775878805Osamaha/TradeLab/actions/runs/45057243714): **837+11 tests passed** وFlutter analyze.
- حركة خطوط وتواريخ المحور أصبحت مرتبطة بالشموع الحقيقية أثناء pan/pinch؛ اختبارات 45px anchor, pinch center, 120k/3px, Range source UTC, Replay no-future. عالجنا إخفاق اختبار أولي خاطئ اعتبر scrollBars=0 غير صالح؛ أعيد تشغيل CI ونجح.
- دون لقطات Android مطابقة أو APK، لا يمكن الادعاء بأن مطابقة TradingView اكتملت أو مقياس الأداء مماثل.


### 2026-11-22 — TradingView parity: خطوط/علامات الوقت تتحرك مع شموع المصدر (قيد CI)
- كان المحور الزمني يثبت خطوطه وتسمياته في 4 نقاط شاشة ثابتة، ما يجعل علاقة الشموع بالوقت تقفز أثناء pan/pinch. استبدلناه بعلامات مرتبطة بمؤشر شمعة أصلية وموضع `ChartViewport.chartX`، لا بإحداثي شاشة ثابت.
- المسافة البصرية 84px على الأقل باستخدام معاملات 1/2/5/10، دون تعديل أسعار cTrader/Binance أو دمج شموع Replay/Range أو اختلاق timestamps. ترسم الشبكة والتسميات من المصدر الواحد نفسه.
- اختبار 120k bars و3px/pinch/pan/future whitespace/irregular BID + إضافة للـCI. المطابقة 100% لا تُعلن قبل screenshots من الجهاز الحقيقي؛ CI PENDING.


### 2026-11-22 — PR #628 MERGED: منع عودة حساب cTrader قديم بعد فتح التطبيق
- [PR #628](https://github.com/775878805Osamaha/TradeLab/pull/628) squash `29cdfb48153e234e6f1ea0c0a9de29c701fab81c` في dev؛ [CI #45055981156 success](https://github.com/775878805Osamaha/TradeLab/actions/runs/45055981156): **831 tests passed** و**11 tests passed** إضافية، مع Flutter analyze وYemen timezone.
- `chooseAccount` الآن يسلسل كتابة التفضيل، و`disconnect` يحذف الاختيار فقط بعد اكتمال الكتابات السابقة، فيبقى آخر حساب مختار هو المُعتمد. `completeOAuth` يحتفظ بالمحدد LIVE ما دام ضمن تصريح OAuth، وإلا ينتقل إلى حساب مصرح ويحفظ التفضيل الجديد؛ لا عودة خفية للحساب القديم بعد restart.
- لا APK ولا main أو prod، ولا اختبار اتصال حقيقي بالوسيط أو إثبات مطابقة شاشة TradingView.


### 2026-11-22 — حماية اختيار حساب cTrader من سباق كتابة التخزين (قيد CI)
- مصدر الخلل: `chooseAccount` يطلق writes دون await، و`disconnect` يحذف الحساب المختار دون انتظارها؛ قد ينتهي write A بعد اختيار B أو الخروج فيُستعاد حساب غير مطلوب بعد restart.
- تعميم سياسة كتابة serial الآمنة نفسها المستخدمة في Token OAuth إلى `selectedAccountKey`؛ ضمان last selection wins بعد A→B→A، وdelete logout ينتظر كل writes.
- أثناء OAuth جديد يُحتفظ بالحساب Live المختار فقط إذا ظل ضمن authorized accounts؛ في غير ذلك يُختار أول حساب مصرح له وتُحفظ النتيجة بدل التفضيل القديم. عرض خطأ واضح إن فشل حفظ التفضيل مع بقاء التفويض صالحًا.
- اختبارات generic writer + MarketController restart/re-link، CI مطلوب. لا تعديل main/prod/APK.


### 2026-11-22 — PR #627 MERGED: ربط تاريخ الشموع بتفويض cTrader + طابور حفظ الجلسة
- [PR #627 MERGED](https://github.com/775878805Osamaha/TradeLab/pull/627) SHA `ae4a854cf33c96199d1087b0c6f641f8319dd906`، [Actions #45055339815 success](https://github.com/775878805Osamaha/TradeLab/actions/runs/45055339815) — 827 اختبارات حزمة الشارت/Range/Replay + 11 فحوص أخرى، Flutter analyze ناجح.
- تم إغلاق تسرب ردود cTrader القديمة عند A→B→A وعند OAuth إعادة ربط بالحساب نفسه، ورفض انتحال session عبر headers القديمة أو ردود 401/JSON فاسدة، وتأمين حفظ/حذف credential من سباق عمليات التخزين. أصبح ChartScreen يعيد تحميل بياناته عند تبدّل جيل التفويض حتى لو لم يتغير accountId.
- لم يتم بناء APK أو تعديل main/prod، ولا يمكن اعتبار الوصول الحي لـBID أو FPS مثبتًا من unit/widget tests.


### 2026-11-22 — تثبيت جيل التفويض في cTrader History/Range (قيد CI)
- **تحصين تخزين الجلسة:** `CTraderSessionTokenWriteQueue` يضمن الترتيب عند secure-storage write/delete، وعدم استعادة التوكن القديم بعد خروج المستخدم، مع تمييز OAuth re-auth pending ومنع قبول history/headers القديمة أثناءه؛ اختبارات عقد التأخير والفشل/recover وin-flight request أثناء OAuth. لم تُعدّل أدوات الإنتاج أو APK. CI على أحدث head مطلوب.

- **CI الأول #45054416987:** 821 passed / 1 failed (اختبار token rotation عند injected MarketApi). التحديد من سجلات الاختبار: تهيئة `MarketController(api: custom)` لم تُسجّل callback كما تفعل التهيئة الافتراضية. إصلاح root cause في constructor وMarketApi mutable callback، وإضافة 401/JSON safety test؛ انتظار إعادة الاختبار قبل merge.

- **السبب المثبت بالكود:** مقياس A→B→A يحمي BID/ASK فقط، بينما history وBID وpoint-size كانت ترجع البيانات القديمة من طلب بدأ قبل تبديل/إعادة تفويض حساب cTrader.
- تحديث MarketController لحراسة كل ردود history/BID/metadata عبر `ctraderAuthorizationRevision`؛ تحديث ChartScreen لملاحظة نفس رقم الحساب مع تفويض جديد وإعادة تحميل المصدر؛ منع headers القديمة من إعادة كتابة token في MarketApi بعد logout/re-auth، وتأجيل refresh إلى ما بعد النجاح والتحليل الصحيح لرد HTTP.
- اختبارات A→B→A لجميع مسارات candle/range/point، وإعادة OAuth لنفس الحساب وحالة update token المشروع، وإعادة تحميل واجهة Flutter. تمنع خلط broker history أو رسمه بعد تغير صلاحية الجلسة، دون اختراع شموع.
- CI PENDING، لا main/APK/production.


### 2026-11-22 — إغلاق #626 بعد اختبار Android Flutter Range refresh
- **الدمج:** [PR #626 MERGED](https://github.com/775878805Osamaha/TradeLab/pull/626) SHA `3de00b3003d073e388f0c80c20db2f7b79071ebf`؛ [CI 45051268783 success](https://github.com/775878805Osamaha/TradeLab/actions/runs/45051268783) على commit `e26daf7ddf104ead7ff6c2b7c8dae17d85597bb1`، شاملاً widget عند فشل تحديث broker واختبارات سلامة حساب/رمز/point-size/Replay.
- **النتيجة:** إبقاء Range BID الحقيقي الذي سبق التحقق منه مرئيًا خلال تحديث الحساب/الرمز/المقاس نفسه، مع حالة ظاهرة وزر تحديث، ومسح فوري عند اختلاف المصدر أو المقاس. فشل التحديث لا يختلق شموعًا ولا يحجب بيانات تاريخية موثوقة.
- **معلّق للتحقق على الجهاز:** أول بيانات cTrader BID من production، gap/feed diagnosis، وسلاسة pan/pinch على Android. `main`/APK/Vercel production غير معدلة.


### 2026-11-22 — الاحتفاظ الآمن بشموع Range أثناء إعادة جلب cTrader (قيد CI)
- سبب موثّق: `ChartScreen._loadRealHistory` كان يفرّغ الشموع الموثقة قبل رد BID، فيحوّل فشل تحديث عابر إلى شارت فارغ.
- تمت إضافة `RangeRefreshRetention` وفحص source-account/symbol/priceDistance/timeline ورفض الاحتفاظ عند Replay أو مصدر غير موثوق؛ ترميز أصل snapshot عند نشره؛ تحديث الحالة المرئية وزر تحديث BID في شاشة الإعدادات.
- اختبارات pure policy + Flutter widget مع حالة broker failure، في بوابة CI، مع منع إظهار مصدر حساب آخر أو شموع للمقاس الخطأ.
- هذه العملية لا تصلح تلقائيًا غياب بيانات BID لدى الوسيط أو بوابة Vercel production القديمة؛ لا APK/main/prod، CI pending.


### 2026-11-22 — إغلاق PR #625 بنجاح بعد اختبار Range/Replay
- **التسليم:** [PR #625 MERGED](https://github.com/775878805Osamaha/TradeLab/pull/625) عند `40ff5f6468e7890dde316c93183b2ee3dfa160a8` في dev، و[GitHub Actions #45050329496 success](https://github.com/775878805Osamaha/TradeLab/actions/runs/45050329496). تحقق Flutter analyze واختبارات BID/Range/Replay وRTL/Yemen.
- **الأثر البرمجي:** استعادة HTTP 429/502/503/504 للصفحة الحقيقية نفسها، بما فيها cTrader `REQUEST_FREQUENCY_EXCEEDED` فقط دون باقي أكواد الرفض؛ تغيير lookback 24–72h إلى 6h chunks مع استمرار سلامة جلب التاريخ والشموع المكتملة.
- **المعلّق:** اختبار أول BID Range من بوابة cTrader الإنتاجية مع حساب حقيقي، ومطابقة الشارت/لمس الهاتف والـFPS. `main`/production unchanged، لا APK جديد.


### 2026-11-22 — TradeLab Range BID: retry مؤقت آمن + تقسيم 6h (قيد CI)
- كود Flutter سابقًا لم يعالج transient HTTP 429/502/503/504 عند طلب BID؛ إضافة حد 3 محاولات للصفحة نفسها فقط مع backoff. استثناء وحيد لرفض broker: `REQUEST_FREQUENCY_EXCEEDED` مُعرّف من البوابة ويدل على معدل طلبات مؤقت، فيعاد 2 مرات بعد 750/1500ms؛ بقية الرفض/فساد المصدر/401 بلا retry، ولا تُقبل صفحات ناقصة أو مختلطة.
- Startup من 24h إلى 72h يستخدم 6h Verified BID pages، ثم 12h حتى 6 أيام، للحد من أحجام صفحات سوق الجمعة الكثيفة قبل أول عرض. التكاليف المقابلة: طلبات أكثر في عطلات السوق، مع بقاء قيم المصدر وتسلسل الأحداث ومؤشرات Replay ثابتة.
- اختبارات مصدر لكل status وsafe-stop، واختبار الجمعة بعد سوق الأحد مع verify window contiguity. لا اختبار جهاز Android حقيقي، ولا إثبات نجاح بيانات cTrader الحية أو قياس FPS.
- التعديل بفرع `fix/range-bid-retry-and-six-hour-first-source-20261122`، لا main/APK/Production. تحقق Vercel: آخر prod READY @ `b4ddfa6` أقدم من تطوير Flutter وgateway.


### 2026-11-22 — دمج #624: إظهار صفقات Replay الفردية بنتائج Flutter
- **الحالة:** [PR #624 MERGED](https://github.com/775878805Osamaha/TradeLab/pull/624) عند `6f9d40bcbb246c0504d19e378f54ec51bafb393f`. 
- **الملفات:** `flutter_app/lib/replay/replay_training_archive.dart`, `flutter_app/lib/screens/results_screen.dart`, `flutter_app/test/replay_training_archive_test.dart`, `flutter_app/test/results_connection_test.dart` إضافة إلى تقرير الترحيل هذا و`docs/HANDOFF.md`.
- **المنجز:** بعد حفظ جلسة Replay، تُعرض تفاصيل كل صفقة مفتوحة ومغلقة وأرقام الدخول/الخروج والكمية، مع زر 20 صفًا إضافيًا عند الحاجة ودون تسريب معرّف الحساب أو خلط PnL فرق السعر بالأرباح بالدولار.
- **الفحص:** أول CI 45047956076 فشل في اختبار زر pagination خارج شاشة 320×760dp (808 نجاح، فشل واحد). الاختبار صُحّح وعاد [CI 45048285190](https://github.com/775878805Osamaha/TradeLab/actions/runs/45048285190) ناجحًا بالكامل + Flutter analyze. لم يُجرَ اختبار جهاز حقيقي أو بناء APK جديد.
- **معلّق منفصل:** أول تحميل BID لشموع Range والفجوات من بوابة cTrader production، مع ضرورة عدم اصطناع الأسعار. `main` والإنتاج لا تغيير.


### 2026-11-22 — تفاصيل صفقات Replay داخل النتائج (قيد CI)
- التحقق المصدرّي: صفحة النتائج السابقة تُظهر **ملخص الجلسات** فقط، وليس أوامر Replay المفتوحة والمغلقة منفردة. هذا نقص عرض إضافي بعد إصلاحات #617/#621/#622.
- تحديث سجل SQLite: projection منظّف لكل صفقة يحفظ جهة الدخول والسعر والكمية والخروج والنتيجة، مع التحقق من النوع وسلامة الأرقام ودون تمرير accountId أو sourceKey إلى صف الصفقة.
- تحديث واجهة Flutter: آخر 3 صفقات مرئية مباشرة داخل الجلسة، وPagination تدرّجي 20 صفًا، مع فصل صريح عن دفتر تداول الدولار. اختبارات archive/widget/320dp أضيفت للمراجعة.
- لا APK، ولا تحديث main، ولا نشر بوابة cTrader. انتظار CI الفعلي قبل اعتبار الإصلاح مُتحققًا.


### 2026-11-22 — إغلاق أربع PRs حقيقية لعيوب Android + CI النهائي
- **الصور المرسلة:** نتائج Replay لا تعكس صفقات التدريب، فراغ بعد اختيار البداية، وRange 1000 لا يظهر. الإصلاحات مدمجة للكود مع حدود إثباتها: #620 Replay blank-space، #621 SQLite write/read barrier، #622 Replay-count overview link، #623 إعادة بناء Range من BID المحفوظ.
- **الدمج/التحقق:** #620 `64cf670b9b6c945386aa3b84b8f6695171d00eaf` / CI 45042568943 ناجح؛ #621 `bfde66f7373334f428b32befa79c2d4541fcef8e` / 45043404745 ناجح؛ #622 `b436b94cd16770ae33c94c5c3c9d78141d18e73b` / 45043777734 ناجح؛ #623 `ddc4248c9b476c45c6acb145e2a706e8a0ac4c9d` / 45044435487 ناجح على head `90c0ff9`. أول مرتين لـ#623 فشل Flutter analyze بسبب علامتي null-assertion غير ضروريتين، ثم أُصلحت وأعيدت كل الفحوص بنجاح.
- **ما لا يزال غير مثبت:** نجاح تحميل أول BID Range لدى حقيقي cTrader، تنزيل الإصلاحات إلى الهاتف، FPS/التكبير/مطابقة TradingView، وبوابة production التي مازالت قديمة. No main changes/No APK/No production deploy.



### 2026-11-22 — Range size reuse BID الحقيقي محليًا (CI PENDING)
- الفجوة المثبتة: تبديل مدى 1000→25 يعيد طلب ودمج نفس BID الموّثق لكل النوافذ عند وجود المصدر على الهاتف، ويزيد انتظار الشمعة الأولى.
- إصلاح: RangeSizeReuse يتحقق من timeline/source boundaries and account-ready guard ويعيد بناء Range من نفس source في isolate عند الحاجة، دون network. فشل rebuild يرجع للمقاس والشموع الصحيحة السابقة، لا أسعار وهمية أو كشف future.
- اختبارات source invariants, same-price alternative size, original source immutable, forming bar excluded from Replay.
- branch `perf/range-rebuild-verified-ticks-on-size-change-20261122` من `bfde66f7373334f428b32befa79c2d4541fcef8e`، CI pending، no APK/main/prod.

### 2026-11-22 — Replay discoverability في Overview (PENDING)
- رابط صريح تحت USD Hero إلى `صفقات Replay` مع عداد open/closed في أحدث جلسات Replay المحفوظة. لا تعديل على USD Journal أو حساب broker.
- Widget regression 320dp وخاصية onTap إلى تبويب Replay، مع تنبيه أنها صفقات تاريخية.
- branch `fix/replay-overview-shortcut-20261122` من `64cf670b9b6c945386aa3b84b8f6695171d00eaf`، CI PENDING، no APK or main.
### 2026-11-22 — ضمان ظهور Replay في النتائج بعد آخر صفقة مباشرة (PENDING)
- الـSQLite SELECT في نتائج Replay قد يسبق `_recordTraining` المؤجل حتى مع ظهور تبويب جديد؛ الحل يسجّل pending-write barrier ويُجبر flush عند تبديل chart active→inactive.
- اختبارات Futures معلقة/فشل ثم تعافٍ وread-after-save قبل await، مع سلامة `PaperLedger` وReplay.
- Vercel production بقي عند main 20 نوفمبر؛ preview READY الجديدة لا تحل مشكلة التطبيق الذي يستعمل `tradelab-vercel-gateway.vercel.app` في الإنتاج. سجل /v1/spot فيه unclassified errors؛ لا دليل منه أن /v1/ticks فشل بسبب ذلك. لا نشر إنتاج بلا تحقق منفصل.
- branch `fix/replay-results-write-read-barrier-20261122` من `64cf670b9b6c945386aa3b84b8f6695171d00eaf`، CI PENDING، لا APK/main.

### 2026-11-22 — Replay confirmation horizontal blank space (CI pending)
- Identified negative scrollBars from chart_screen._confirmReplayStart retaining selection-source x after hiding future history; new afterConfirmingReplayStart puts last verified revealed candle near price ruler, with a max 20% right margin for tight/maximum zoom.
- Tests for 259/329dp and 3/10/60px, autoplay stable, no future index reveal, invalid geometry; no OHLC or broker data changed.
- Branch fix/replay-confirm-whitespace-20261122 base ef56ee11d2fb4d98ac18d393425f5e4ab747488b; CI pending and no APK.


### 2026-11-22 — Range الأحد: تقسيم نافذة 24–72 ساعة الكبيرة (CI PENDING)
- تم التحقق من كود RangeStartupLoader: قفزة 24h→72h كانت تطلب نافذة 48h قد تضم تيكات XAUUSD كثيفة قبل ظهور أول Snapshot. عبر 12h cumulative slices حتى 6 أيام، يظل كل BID موثقاً وحقيقياً ولا يُختلق نشاط في عطلات السوق.
- اختبارات range_startup_loader_test.dart أضيفت لأحد Nov 22 وتاريخ جمعة عمره 42 ساعة وللحد 12h وتجاور النوافذ/عدم التكرار. قياسات السرعة الحقيقية لدى cTrader لم تنفذ. لا يغير وحده API مصدر الوسيط أو صلاحيات الحساب.
- PR/CI pending. لا APK ولا تعديل main.


### 2026-11-22 — تشخيص صفحة cTrader فارغة موسومة hasMore (CI PENDING)
- User Android screenshot matches MarketApi guard empty `hasMore=true`; exact broker cause not measured.
- Gateway retries bounded documented count-back once on empty truncated response, with provenance and upper cutoff kept; test weekend/empty fallback; Node CI on PR.
- Does NOT synthesize candles, does not repair BID tick source on its own, does not deploy live gateway, no APK or main.

### 2026-11-22 UTC — بناء APK تجريبي مستقل ناجح من TradeLab HEAD b389bf6
- **الطلب:** المستخدم يريد تثبيت أحدث تعديلات TradeLab على Android لاختبارها.
- **مصدر البناء:** `test/flutter-all-fixes-20261116` @ `b389bf6cd19044d47ba9e350e19a5365fda5820e`؛ branch خاص `test/build-tradelab-phone-20261122` @ `545ae0cc0ba12f98b5256bdc9a3a7173e0b19790`؛ تغيير وحيد ملف `.github/workflows/build-tradelab-phone-test-20261122.yml` بنطاق push مرة أولى. تركنا workflows العادية الخاصة ببناء APK معطلة ولم نعدل `main`.
- **التشغيل:** https://github.com/775878805Osamaha/TradeLab/actions/runs/45030261658 **completed/success**؛ نجح `flutter analyze` والاختبارات المجمعة وفحص OAuth و`flutter build apk --release` و`unzip -t` و`apksigner verify` و`aapt dump badging` ورفع ملف APK ثم إصدار GitHub.
- **الأثر:** https://github.com/775878805Osamaha/TradeLab/releases/tag/tradelab-phone-test-545ae0cc0ba1 ؛ ملف `TradeLab-Phone-20261122.apk` بحجم 59,358,487 بايت (APK مباشر: https://github.com/775878805Osamaha/TradeLab/releases/download/tradelab-phone-test-545ae0cc0ba1/TradeLab-Phone-20261122.apk) مع SHA256 منشور. حزمة منفصلة `com.example.tradelab_flutter.phone20261122`/اسم `TradeLab Phone Test` فلا تحذف بيانات التطبيقات القديمة.
- **المخاطر:** شهادة التوقيع Debug مؤقتة لتجربة فقط، ولا دليل من CI على Android حقيقي أو نجاح cTrader OAuth أو مقارنة TradingView أو قياسات Frame P95. التغيير التالي يعتمد على ملاحظات تثبيت واختبار المستخدم، ولا إصدار مدفوع.


### 2026-11-22 UTC — إغلاق PR #616 بنجاح بعد تصحيح اختبار قديم
- **فرع التطوير:** `test/flutter-all-fixes-20261116`. قبل `0f3c0cd231ee9dfd5c1f7c8ff941b23b5fc9fba5`؛ بعد الدمج `1811159410f4a499be9f03c06ff05e7e6e054ac1`. لا `main` أو APK/Release.
- **المشكلة المثبتة:** `_refreshDisplayedQuote` كان يطلق `_chartRepaint.value++` لكل تغير BID/ASK أو timestamp حتى عندما `ChartScaleSettings.bidAsk` مخفي افتراضياً ولا توجد تسميات مرئية؛ يتسبب بعمل Canvas/شموع غير ضروري.
- **الملفات:** `flutter_app/lib/chart/chart_feed_health.dart`، `lib/screens/chart_screen.dart`، اختبارات `test/chart_feed_health_test.dart`، `test/chart_paint_only_pan_test.dart`، وتقارير handoff. بقي تحديث source/header وإثباتات التأخر وReplay كما هي.
- **CI تاريخي أول:** https://github.com/775878805Osamaha/TradeLab/actions/runs/45027351182 **failure: 794 passed / 1 failed**. فشل اختبار widget قديم كان يطالب بإعادة الرسم عند السعر المخفي، بينما نجح analyzer وجميع اختبارات الصحة الجديدة. لا دليل لفشل سعر cTrader أو BINANCE.
- **CI معتمد نهائي:** https://github.com/775878805Osamaha/TradeLab/actions/runs/45027698225 **completed/success** على `d7e4ce43cc9bfedfba09f1ec06b1ec93b22e7d6b`. https://github.com/775878805Osamaha/TradeLab/pull/616 **MERGED** عند `1811159410f4a499be9f03c06ff05e7e6e054ac1`.
- **عدد العمليات لا الزمن:** اختبار 240 تحديث سعر مخفي يمنع طلب canvas repaint، واختبار widget 20 تحديثًا يتأكد من عدم إعادة قراءة السعر أثناء paint واحتفاظ header بهويته. لا نقول تحسّن FPS أو live broker latency دون اختبار Android.
- **التالي:** جمع real-world p95/p99 pan/pinch/raster وفصل broker/cache/Range latency، ثم تطوير أكبر bottleneck مثبت. امتنع عن APK حتى يُطلب أو تُعتمد مرحلة الاختبار.


### 2026-11-22 UTC — PR #616: الفشل الأول في اختبار واجهة قديم وتصحيح معيار القبول
- **CI الأولى:** https://github.com/775878805Osamaha/TradeLab/actions/runs/45027351182 **failed** في `Verify historical tick archive and chart interactions` مع **794 tests passed, 1 failed**. `flutter analyze` نجح، وجميع اختبارات `chart_feed_health_test.dart` الجديدة نجحت.
- **السبب المثبت حرفياً من سجل GitHub:** الاختبار `chart_paint_only_pan_test.dart: streaming price changes repaint chart, not entire controls` توقع زيادة `market.reads` مع كل تحديث مصدر حتى لو كان `ChartScaleSettings.bidAsk = hidden`. الإصلاح يعمد إلى **عدم إعادة الرسم في هذا الوضع الافتراضي**؛ لذلك توقع الاختبار القديم يناقض السلوك المطلوب، لا يوجد دليل أن فشلًا في بيانات السوق حدث.
- **التصحيح:** تحديث عنوان الاختبار والتوقع: `market.reads` يجب أن يظل كما هو خلال 20 source revisions مخفية. يظل التحقق من ثبات header ومن خلو أخطاء Flutter كما هو. اختبارات `chart_feed_health_test.dart` تغطي إعادة الرسم عند ظهور أسعار BID/ASK وتغيرها وانتهاء صلاحيتها، وتحديث تحذير التأخر حتى حين يكون السعر مخفياً.
- **الحالة:** commit تصحيح الاختبار، CI النهائي **PENDING**؛ يمنع الدمج حتى تؤكد GitHub Actions جميع اختبارات الشارت وRange وReplay. لا Android FPS حقيقي ولا APK.


### 2026-11-22 — تقليل quote-only redraw عندما BID/ASK مخفي (CI PENDING)
- **المصدر/الفرع:** `test/flutter-all-fixes-20261116` عند `0f3c0cd231ee9dfd5c1f7c8ff941b23b5fc9fba5` → `perf/tradelab-quote-no-candle-repaint-20261122`، لا `main` أو APK.
- **الخلل:** عند كل `ChartFeedHealth.quoteChanged` يدفع `_refreshDisplayedQuote` رسم الشارت كاملًا رغم إخفاء BID/ASK افتراضياً؛ كما أن تغير `timestampMs` وحده لا يغير أي بكسل في هذه التسميات.
- **الإصلاح:** إضافة قرار واضح `quoteAffectsChartCanvas(previous,next,bidAskLabelsVisible)` وتطبيقه حول `_chartRepaint.value++` فقط؛ الاحتفاظ باستدعاء `quoteHeaderEvidenceChanged` منفصلاً حتى لا تتوقف تحذيرات تأخر OHLC وتجدد دقيقة/اتصال cTrader. بيانات المصدر والخادم وReplay لا تتغير.
- **الاختبار:** 240 revisions لسعر مخفي بلا repaint decision، مع ظهور واختفاء سعر مرئي/تحديث timestamp ومخاطر header؛ اختبار `chart_feed_health_test.dart` مسجّل أصلاً ببوابة CI.
- **الحالة:** PR/CI قيد الفحص؛ لا قياسات Android FPS ولا نسبة زمنية مثبَتة.


### 2026-11-22 UTC — إغلاق #614: رفض الرسومات التاريخية قبل تحويل X بنجاح
- **قبل:** `test/flutter-all-fixes-20261116` @ `d6ec4302533870795ca01e678bae8b5510d06e73`؛ **الدمج:** `7f3f2f0653f7c5982f604ffeab068828c8a881e0`؛ **رأس الفرع وقت المراجعة:** `3f87046910627475190347c098fde8671d3e2034`؛ لا تعديل `main` ولا APK.
- **PR/CI:** https://github.com/775878805Osamaha/TradeLab/pull/614 **MERGED**، https://github.com/775878805Osamaha/TradeLab/actions/runs/45024043207 **completed/success** عند `8cc0dd71de5e9be5e5ca811a3b1df7f8480e8e22`، بما فيها `flutter analyze` وRange/Replay والشارت وأدوات الرسم وتوقيت اليمن.
- **الملفات الفنية:** `flutter_app/lib/chart/chart_line_geometry.dart` و`chart_drawing_hit_test.dart` و`screens/chart_screen.dart`؛ اختبارات `chart_line_geometry_test.dart`, `chart_drawing_hit_test_test.dart`. لم يتغير مصدر أسعار cTrader/Binance أو تاريخ UTC.
- **الفائدة القابلة للقياس في الاختبار:** مع 120k فهرس شمعة و6000 رسمة تاريخية يصبح اختبار لمس الرسم المرئي بحاجة إلى 2 حساب `sourceX` بدلاً من 12002؛ تتحقق الاختبارات من أن قص الفهارس لا يخفي أي خط مرئي هندسياً في الأبعاد والتكبيرات المختبرة. الفائدة Runtime FPS لم تُقس على الهاتف.
- **مخاطر/ما لم يتأكد:** عرض TradingView طبق الأصل، جودة اللمس الفعلية، Frame P95/P99، والوقت الحقيقي لتحميل cTrader/Range على Android كلها لم تُثبت؛ لا APK أحدث. الخطوة التالية اختبار Android Profile باستخدام مساري `ChartFrameProfiler` و`ChartLoadProfiler` الموجودين، والحفاظ على المصدر/Replay guard.


### 2026-11-22 — إغلاق نتائج #614 و#615 بعد نجاح CI والدمج
- **فرع التنفيذ:** `test/flutter-all-fixes-20261116`. **PR #614** https://github.com/775878805Osamaha/TradeLab/pull/614 → merge `7f3f2f0653f7c5982f604ffeab068828c8a881e0`، CI `45024043207` https://github.com/775878805Osamaha/TradeLab/actions/runs/45024043207 **completed/success** على `8cc0dd71de5e9be5e5ca811a3b1df7f8480e8e22`.
- **PR #615** https://github.com/775878805Osamaha/TradeLab/pull/615 → merge `8707e6c5fc08a555f82285b61b591380f4971c84`، CI `45024347884` https://github.com/775878805Osamaha/TradeLab/actions/runs/45024347884 **completed/success** على `de5ee27e56cc31896b852b31392962ae3a25c2c5`.
- **التغييرات:** قص رسومات تاريخية محدودة قبل `chartX` و`scale.y` في الرسم/اللمس؛ LOG محور السعر يحسب لوغاريتم حدوده مرة واحدة لكل إعادة رسم، لا عند كل شمعة/فتيل. ملفات: `chart_line_geometry.dart`, `chart_drawing_hit_test.dart`, `screens/chart_screen.dart`, `chart_viewport.dart` واختبارات `chart_line_geometry_test.dart`, `chart_drawing_hit_test_test.dart`, `chart_logarithmic_price_scale_test.dart`.
- **ما تحقق فعليًا:** نجاح Flutter analyze وجميع مراحل اختبار chart/Range/Replay/history/Long/Short/Info Line/Trend Angle/TZ؛ regression 120k شمعة/6000 رسم يقيس sourceX 2 بدل 12002 لحالة اللمس المفردة؛ مطابقة Y حسابية ضمن 1e-10px على 320/390/640 مع LOG/Inverted/Linear. **لا نتائج FPS هاتف**.
- **ما لم يحدث:** لم يُبْن APK، لم يُعدّل `main`، لم تُغيّر أسعار cTrader/Binance ولا مصادر BID ولا حدود Replay؛ لم يجرِ Live cTrader أو A/B Android screenshot/raster profiling. آخر APK منشور 2026-11-20 يسبق التغييرات.
- **الخطوة التالية:** ملف `docs/PERFORMANCE_FOLLOWUP_2026-11-22.md` لخطة فصل تحميل البيانات عن تكلفة paint/touch؛ التعديلات القادمة يجب أن تستند إلى قياسات فعلية متى أمكن.


### 2026-11-22 — تهيئة ثوابت LOG مرة واحدة لكل Canvas repaint (CI PENDING)
- **أساس/فرع:** `d6ec4302533870795ca01e678bae8b5510d06e73` → `perf/chart-log-price-projection-20261122`. **PR/CI قيد التحقق**.
- **تكرار مثبت:** `ChartPriceScale.y` ينفذ لوغاريتمي `maximum` و`minimum` لكل شمعة/فتيل/رسم في `_CandleChartPainter` حتى لو ظل مقياس الأسعار ثابتاً طوال الإطار؛ تقليل O(n) حسابات حدود المقياس إلى O(1) لكل frame، دون تعديل لوغاريتم سعر كل OHLC عند الحاجة.
- **الملفات:** `chart_viewport.dart` و`screens/chart_screen.dart` واختبار `chart_logarithmic_price_scale_test.dart` وتقارير handoff.
- **معايير القبول:** كل إحداثي y في LOG/inverted يساوي تحوّله الأصلي إلى تسامح 1e-10px، Linear/Percent/Indexed/negative fallback بلا تغيير. تشغيل flutter analyze وباقي اختبارات CI قبل الدمج، لا وعود FPS أو تغيير بيانات cTrader/Binance، لا APK.


### 2026-11-22 — Source-index culling قبل الرسم وhit-testing (PENDING)
- **الفرع/الأساس:** `perf/chart-source-window-early-cull-20261122` من `d6ec4302533870795ca01e678bae8b5510d06e73`. **PR وCI: قيد التحقق**.
- **الخلل:** `ChartDrawingHitTest.hit` ورسام الشارت يحسبان `chartX` لآلاف الرسومات التاريخية المحدودة البعيدة رغم أن نافذة الفهارس الحقيقية المعروضة يمكنها استبعادها فوراً. `scale.y` كان مستبعداً سابقاً في PR #610، لكن عبء X ظل.
- **التعديل:** مساعد `definitelyOffscreenBySourceWindow` محافظ على `ChartLineGeometry` يرفض الرسم المحدود المعزول بالكامل خارج نافذة `visibleIndices` المبطنة، دون مساس بأشكال Rays وCrossline والقنوات والمرساة المحددة؛ استدعاؤه في `ChartScreen._hitPattern` وفي `_CandleChartPainter` قبل حساب إحداثيات الرسم.
- **الاختبارات:** 120k مصدر/6000 خط تاريخي، التحقق من 2 لا 12002 استدعاء `sourceX` في حالة اللمس؛ مصفوفة لـ 259/329px والزووم والتمرير و11 نوع رسم تُثبت أن استبعاد الفهرس يعني استبعاد البكسل الحقيقي؛ اختبار selected handles وReplay والحافة. هذا **دليل عدد عمليات** لا FPS Android.
- **لا يُنفذ:** تغيير OHLC أو cTrader/Binance أو Replay cutoffs أو بناء APK أو main. لا دمج إذا فشل CI.


### 2026-11-22 UTC — إغلاق دفعات تحسين الأداء #610 و#612 و#613 بنجاح
- **المستودع/فرع التطوير:** `775878805Osamaha/TradeLab` / `test/flutter-all-fixes-20261116`؛ من `0b82addd5063e7b6f6baaf3b1d0894d2090d04b8` عبر #610 إلى `974196e3c62ef67919c71031c235b57c3c245cad`. لا تعديل `main` أو APK/Release.
- **PR #610:** https://github.com/775878805Osamaha/TradeLab/pull/610 **MERGED** إلى `37bc5d56f2a807d97be046ab49359789b4f81e90`، https://github.com/775878805Osamaha/TradeLab/actions/runs/45018066145 **success**. لمسات على 120k source و6000 offscreen patterns: مسار `ChartDrawingHitTest` يرفض الرسومات المحدودة قبل `scale.y` مع بقاء الرسومات الممتدة/Replay سليمة.
- **PR #612:** https://github.com/775878805Osamaha/TradeLab/pull/612 **MERGED** إلى `736626ad92806e6ce8ad3ac151ff6f9b096edfa6`، https://github.com/775878805Osamaha/TradeLab/actions/runs/45022185183 **success** على `74514dca4463731c224b53d8471399f263cfdaef`. `chart_price_scale_cache.dart` يعتمد حدود `visibleIndices` الفعلية لا قيمة scroll كسريّة متغيرة عند كل frame. اختبار 120k/240 pan يحافظ على 0 قراءات OHLC إضافية لنفس نافذة المصدر؛ المصدر/Replay والأوضاع ما زالت تبطل الكاش.
- **PR #613:** https://github.com/775878805Osamaha/TradeLab/pull/613 **MERGED** إلى `974196e3c62ef67919c71031c235b57c3c245cad`، https://github.com/775878805Osamaha/TradeLab/actions/runs/45022570244 **success** على `ebd85f310b2b270bc52f45facd51c4a8c66cb957`. `ChartHistoryPrefetchPolicy` يسبق حافة التاريخ بشاشتين ضمن 25–256 شمعة مع بقاء Replay guard/old-load guard وعدم اختلاق مصدر.
- **إدارة التكرار:** PR #611 أغلق دون دمج بعد التحقق أنه يكرر نفس head والديف المدمج سابقاً عبر #610. لا إعادة حسابه كتقدم منفصل.
- **نتائج الفحوص:** Dart/Flutter analyze وRange/history/chart/Replay وcatalog/timezone ناجحة؛ الأرقام أعلاه عدد عمليات/شروط بدء جلب، **وليست قياسات frame time أو سرعات شبكة فعليّة**.
- **المتبقي:** Android Profile P50/P95/P99 على جهاز حقيقي، قياس cTrader/Binance/SQLite زمنياً في سيناريوهات التطبيق، ومقارنة مرئية مع TradingView. آخر APK منشور بتاريخ 2026-11-20 لا يشمل هذه التغييرات في فرع التطوير.
- **الخطوة التالية:** تمكين جلسة Android اختبار مصرح بها مع سجل `TRADELAB_CHART_FRAME_METRICS` و`ChartLoadProfiler` لتحديد bottleneck؛ إصلاحه بناءً على القياسات، وليس تخمين قيمة FPS.


### 2026-11-22 — تقديم التحميل الاستباقي للشموع الأقدم أثناء السحب
- **فرع وSHA:** `perf/tradelab-history-prefetch-earlier-20261122` من `75e6bf240799359d7dbf5e3cb89733819728eed3`، **PR/CI: PENDING**.
- **الدليل:** `_prefetchOlderAtEdge` في `screens/chart_screen.dart` يستخدم مهلة 25 بار ثابتة حتى عند 3px/شمعة، ما يجعل طلبات التاريخ تبدأ متأخرة قبل وصول إصبع المستخدم إلى أول شمعة مثبتة.
- **ملفات التنفيذ:** `chart_history_prefetch_policy.dart` + `test/chart_history_prefetch_policy_test.dart` و`screens/chart_screen.dart` و`verify-flutter-range.yml`؛ نافذة استباق 2× عرض الشارت تتراوح 25–256 شمعة وبلا طلب قبل حركة pan موجبة.
- **حماية البيانات:** Replay لا يزال يرفض prefetch؛ حواجز _olderLoading و_source errors و_account source محفوظة؛ لا توليد بيانات ولا تعديل رسومات/حسابات/أسعار، ولا APK.
- **اختبارات/حدود:** Widget/Unit CI قيد التحقق؛ لم تُقَس سرعة شبكة cTrader أو FPS حقيقي على Android؛ لا ادعاء تحسين محسوب بالمللي ثانية.


### 2026-11-22 — تقليل إعادة مسح OHLC خلال السحب الجزئي لشارت 120k
- **الفرع:** `perf/tradelab-price-scale-visible-window-cache-20261122` من `75e6bf240799359d7dbf5e3cb89733819728eed3`. **PR/CI PENDING**.
- **الخلل:** `_viewport == viewport` في `ChartPriceScaleCache.resolve` كان يبطل الكاش حتى إذا تغير موضع الرسم بالبيكسل فقط دون خروج/دخول أي شمعة حقيقية؛ حركة الإصبع المتتابعة تعيد حساب حدود السعر في نفس نافذة الشموع.
- **الملفات:** `chart_price_scale_cache.dart`؛ `chart_price_scale_cache_test.dart`؛ `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`.
- **الاختبارات المقترحة:** 240 خطوة pan كسرية على مصدر 120,000 شمعة، وعدّ source reads؛ إبطال الكاش مع نافذة جديدة/بيانات جديدة/LOG/Percent/Indexed/Inverted. تظل أسعار cTrader/Binance وReplay الأصلية دون تغيير.
- **القيود:** نتائج Android Profile ولقطات مطابقة TradingView غير متاحة؛ اختبار Flutter CI جاري/معلق حتى ظهوره، لا APK ولا تغيير `main`.


### 2026-11-22 — PR #610 دمج بعد نجاح Flutter CI: تسريع اختيار رسومات تاريخية خارج الشاشة
- **قبل:** `test/flutter-all-fixes-20261116` @ `0b82addd5063e7b6f6baaf3b1d0894d2090d04b8`؛ **بعد دمج الكود:** `37bc5d56f2a807d97be046ab49359789b4f81e90` على فرع التطوير فقط، لا `main` ولا APK.
- **الملفات:** `flutter_app/lib/chart/chart_drawing_hit_test.dart` جديد، `flutter_app/lib/screens/chart_screen.dart` استخدام helper، `flutter_app/test/chart_drawing_hit_test_test.dart` جديد، `.github/workflows/verify-flutter-range.yml`، وتقارير docs.
- **ما تم إثباته:** https://github.com/775878805Osamaha/TradeLab/pull/610 **MERGED**؛ https://github.com/775878805Osamaha/TradeLab/actions/runs/45018066145 **completed/success** على `fc945655c037d22c0c15abf4effbe820fddabc20`. Flutter analyze وchart/Range/Replay/history والأدوات/TZ جميعها نجحت.
- **الأرقام الدقيقة:** اختبار مُصطنع ب120k فهرس شمعة و6000 رسم بعيد تحقق من استدعاءين لإسقاط Y للرسم المختار بدلاً من 12002 لمسار غير المقصوص؛ ليس مقياس FPS ولا p95 أو ضمان 6,000 رسم في تطبيق المستخدم.
- **المحافظة:** rays/extended/crossline/fibonacci/parallel بلا استبعاد خاطئ، Replay source-prefix، حدود plot وselected handle، آخر رسم أولوية؛ لا تعديل أسعار بيانات الوسيط أو P&L.
- **غير مُتحقق:** Android الحقيقي screenshot/pixel diff/gesture trace/Profile FPS أو cTrader/Binance live؛ لا إعلان اكتمال.
- **التالي:** جمع قياس Android من جهاز حقيقي عند 320/390dp، ثم إصلاح الفرق الأكبر المثبت وتسجيله بنفس التوثيق.


### 2026-11-22 — تحسين كلفة hit-testing للرسومات خارج النافذة التاريخية
- **فرع وSHA قبل:** `perf/tradelab-drawing-touch-cull-source-20261122` من `test/flutter-all-fixes-20261116` @ `0b82addd5063e7b6f6baaf3b1d0894d2090d04b8`. **بعد/PR/CI: PENDING** حتى توثيق الدمج.
- **السبب من الكود:** `_hitPattern` كان يحسب أسعار Y لكل رسم غير مرئي، خلافاً لقواعد القص المستخدمة بالفعل في Paint. الضرر يتصاعد مع آلاف خطوط الاتجاه التاريخية والـ LOG.
- **الملفات:** helper `chart_drawing_hit_test.dart` + اختبار `chart_drawing_hit_test_test.dart`؛ استبدال مسار اللمس بمحوّل مصدر تابع للشارت الحالي داخل `screens/chart_screen.dart`، إضافة اختبار Flutter CI، وإضافة handoff. تستمر هندسة hit وReplay وcTrader المصدرية دون تغيير.
- **التحقق المطلوب:** تحليل Dart/Flutter ثم الاختبارات الشاملة قبل دمج أي PR؛ اختبار وحدة 6000 رسمة مع عدّ عمليات `sourceY`، وRay/Crossline/Fibonacci/Parallel، وReplay future، وشاشتَي 320/390dp (plot 259/329). **لا قياس FPS فعلي**.
- **التالي:** متابعة GitHub Actions، إصلاح أي إخفاق مثبت من السجل، ثم حفظ رابط/sha النهائيين أو الإبقاء على PR غير مدمج عند الفشل.


### 2026-11-22 UTC — إغلاق دفعتَي CI/PR بنجاح: #608 و#609
- **قبل:** فرع التطوير `863bc9b94da73f03ccc7e294a99634bcae078fd0`؛ **بعد:** `07e2edeef9a0dcf74631f1f5094b5b856d5d3df2` على `test/flutter-all-fixes-20261116`، دون تغيير `main`.
- **التعديل والملفات:** حماية مصدر رسم Replay/Canvas/مغناطيس OHLC من الفهارس السالبة وNaN/Infinity في `chart_annotations.dart`, `chart_line_geometry.dart`; قياس مسافة Weak/Strong magnet بالبكسل الحقيقي بدل فرق السعر على LOG/Inverted في `screens/chart_screen.dart`; اختبارات محددة في `chart_annotations_test.dart` و`chart_line_geometry_test.dart`; ملفات handoff والتقارير.
- **PR #608:** https://github.com/775878805Osamaha/TradeLab/pull/608 **MERGED** عند `afe0f48446606a31d084881f9f9d9d10482557e9`؛ **CI https://github.com/775878805Osamaha/TradeLab/actions/runs/44964541908 completed/success**.
- **PR #609:** https://github.com/775878805Osamaha/TradeLab/pull/609 **MERGED** عند `07e2edeef9a0dcf74631f1f5094b5b856d5d3df2`؛ **CI https://github.com/775878805Osamaha/TradeLab/actions/runs/44965028176 completed/success** على `851b436f2403a91c0fc500732b98fbbeaea1be92`، شامل Flutter analyze + chart/Range/Replay/history + أدوات الرسم وتوقيت اليمن.
- **الإخفاق التاريخي والسبب:** https://github.com/775878805Osamaha/TradeLab/actions/runs/44964863568 failed في analyzer فقط، ثلاث `unnecessary_non_null_assertion`؛ أصلحه `82beefdf`؛ أعيد التحقق بنجاح. التشغيلات الملغاة أثناء تحديثات PR ليست نجاحاً مستقلاً.
- **غير متحقق/مخاطر:** Android actual gesture/FPS p50/p95/p99؛ مقارنة pixel-perfect مع TradingView؛ live cTrader؛ إطلاق APK. لا ادعاء اكتمال ولا تغيير بيانات السوق أو الحسابات.
- **التالي:** اختبار Android مرجعي ومراجعة الأداء الحقيقي، ثم توثيق فروقات الصورة واللمس وسببها قبل إصلاحها، دون توليد أسعار أو بناء APK تلقائيًا.


> سجل تراكمي لا تُحذف منه الإدخالات القديمة. بعد كل تعديل/رفع/دمج/تشغيل فحص، اكتب حدثًا بالحقول الإلزامية، وحدّث [HANDOFF.md](HANDOFF.md). تبقى النتائج المعلقة موسومة PENDING حتى تثبت نتيجة GitHub.

**قالب الحدث:** تاريخ UTC | الحدث/النتيجة | الفرع وSHA قبل/بعد | PR/CI/روابط | الملفات المتغيرة | ما تحقق بالفعل | ما لم يتحقق/المخاطر | الخطوة التالية.

### 2026-11-22 — مقارنة مغناطيس رسومات OHLC ببكسلات شاشة Android الحقيقية
- **الفرع/الأساس:** `fix/tradelab-log-magnet-pixel-tolerance-20261122` مبني على الإصلاح السابق `8158c0445c01bb954ead4911e811d21d6e7fd792`. **PR/CI: PENDING**.
- **المشكلة:** مسافة Weak Magnet السابقة كانت فرق السعر × `12/height`، وهي ليست مسافة 12px على LOG. Strong كان يختار أقل فرق سعري ولو لم يكن بصرياً الأقرب.
- **الإصلاح:** الإسقاط ب`ChartPriceScale.y` للفروق الفعلية على شاشة الرسم، دعم Inverted، واستمرار المصدر نفسه `_displayCandles[index]` (Replay prefix فقط) وتجاهل أسعار غير قابلة للإسقاط. تبقى استدعاءات API القديمة متوافقة.
- **إخفاق CI مصحّح قبل الدمج:** [Actions #44964863568](https://github.com/775878805Osamaha/TradeLab/actions/runs/44964863568) انتهى failure في `flutter analyze` عند `chart_annotations.dart:33,41,54` بسبب 3 تحذيرات `unnecessary_non_null_assertion`. لم تُشغَّل اختبارات Flutter بعده. حُذفت علامات `!` الزائدة مع إبقاء ضمانات Dart flow promotion نفسها؛ **إعادة فحص CI: PENDING**، ولا يُدّعى النجاح قبل النتيجة.\n- **الاختبارات المُعدّة:** `chart_annotations_test.dart` على ارتفاعي 320/390، linear/LOG/inverted، weak/strong/off، حدود 12px، ناN/Infinity؛ اختبار شامل مع باقي Flutter/Range/Replay عبر GitHub CI. **لا ادعاء نجاح قبل نتيجة CI**.
- **الحدود:** لا Android profile/pixel parity ولا APK أو تعديل `main` أو مشاريع أخرى.


### 2026-11-22 — حراسة بيانات الرسم غير الصالحة في Replay وCanvas
- **الأساس/الفرع:** `test/flutter-all-fixes-20261116` عند `863bc9b94da73f03ccc7e294a99634bcae078fd0` → `fix/tradelab-drawing-finite-replay-guards-20261122`. **PR/CI: PENDING**.
- **الخلل:** قبول فهرس سالب في `visibleAt`، واختيار NaN من عناصر OHLC للمغناطيس، وعدم فحص قيم Offset/Rect غير المنتهية قبل رسم خطوط/تحديد لمسها.
- **الكود:** `chart_annotations.dart` يرفض فهارس المصدر غير الصالحة وأسعار المرساة NaN/Infinity ويحافظ على أسعار السوق المنتهية؛ مغناطيس OHLC يتجاهل القيم غير المنتهية ويتعامل مع tolerance غير صالحة. `chart_line_geometry.dart` يرفض stroke/viewport غير المنتهي ويمنع hit-tests لقطع وهمية.
- **التحقق المضاف:** حالات وحدة في `chart_annotations_test.dart` و`chart_line_geometry_test.dart` لReplay/المغناطيس/الملصقات/القص/اللمس. **لم ينجز بعد:** GitHub CI والاختبار الفعلي على Android والمطابقة البصرية/السرعة على هاتف. لا APK ولا تغيير `main`.
- **الخطوة التالية:** فحص نتائج PR، لا دمج عند فشل `flutter analyze` أو الاختبارات؛ تدوين النتيجة وروابطها بعد التحقق.


### 2026-11-22 — تفعيل رسم Trend Angle مع زاوية حقيقية ودعم Replay/Invert
- **المرجع:** https://www.tradingview.com/support/solutions/43000791602-trend-angle-drawing-tool/؛ **الفرع:** `feat/tradelab-trend-angle-source-20261122` بعد PR #606 (MERGED)، الأساس `test/flutter-all-fixes-20261116`.
- **الفجوة:** `trendAngle` في كتالوج Flutter مع `implemented=false`؛ أداة الرسوم نفسها غير معرفة؛ لا يمكن وضع نقطتين أو رؤية زاوية محسوبة.
- **التعديل:** [2a2f087](https://github.com/775878805Osamaha/TradeLab/commit/2a2f0871e68e57b1194f80c4c3d1f42294a47d79) enum source anchor tool؛ [02d534f](https://github.com/775878805Osamaha/TradeLab/commit/02d534ff8e566c3323cff03954cdcee846ef244d) catalog true؛ [7f1769c](https://github.com/775878805Osamaha/TradeLab/commit/7f1769c3d24f53c3f7557731e532d0d86082e828) finite clipping/culling؛ [1f641be](https://github.com/775878805Osamaha/TradeLab/commit/1f641be26ce36d275fce73e4b20bbe86923a1fa7) source-only `ChartInfoLineStats` تدعم Trend Angle وReplay guard، [491db69](https://github.com/775878805Osamaha/TradeLab/commit/491db69fe45af708944eebb49194cd39d8d939d5)/[a708db5](https://github.com/775878805Osamaha/TradeLab/commit/a708db569dd15c2871ccdbde10f8d8aceb29c1f4) تفعيل نقرتين ورسم ملصق الزاوية الأول والـbars/%/فرق السعر ثانياً، دون توليد أي candle أو quote.
- **الاختبارات:** [622d429](https://github.com/775878805Osamaha/TradeLab/commit/622d42991b39d5a0fa3c8e0578d8ba92fc0a7ad9) two-tap widget 320/390، [182b24f](https://github.com/775878805Osamaha/TradeLab/commit/182b24f50a60a24d3196d0ff9fe30e206da907b1) ±45°/Invert/Replay editing، [443c02c](https://github.com/775878805Osamaha/TradeLab/commit/443c02c7fd31a35edd3db2945b9b60383fd5db24) geometry؛ [e0d8ed2](https://github.com/775878805Osamaha/TradeLab/commit/e0d8ed24ece426c559045ad98d1900250318ce77) catalog؛ CI [37f6d72](https://github.com/775878805Osamaha/TradeLab/commit/37f6d7214b0acfcfdc748d535b326baf32fa02dd).
- **النتيجة:** [PR #607](https://github.com/775878805Osamaha/TradeLab/pull/607) **MERGED/squash** في `test/flutter-all-fixes-20261116` عند [SHA d64e4e6](https://github.com/775878805Osamaha/TradeLab/commit/d64e4e66040f7beb79bab94198a4cc46a4ba008d). [Actions #44963619641](https://github.com/775878805Osamaha/TradeLab/actions/runs/44963619641) **completed/success** على HEAD `293edc7ffb8023f8c70fea3143126b1306a51981`: Flutter analyze، widget 320/390dp وsigned canvas angle/Replay/anchor edit، geometry/culling، chart/Range/history/Replay، catalog Info Line/Crossline/LongShort وYemen TZ—all passed.
- **غير متحقق:** Android pixel/gesture parity، Profile FPS وcTrader live **NOT RUN**، لا APK/Release ولا `main` أو أي مشروع غير TradeLab.
- **التالي:** استكمال المطابقة بصور Android فعلية أو تنفيذ أداة الرسم التالية بدليل مصدر واختبارات مستقلة.

### 2026-11-22 — Info Line مصدر أسعار وUTC حقيقي بدلاً من زر كتالوج معطل
- **الفرع:** `feat/tradelab-info-line-source-stats-20261122` من `test/flutter-all-fixes-20261116` بعد PR #605 (MERGED).
- **الفجوة المرجعية:** `infoLine('خط معلومات')` ظاهر في `drawing_tools_sheet.dart` مع `implemented=false` وبدون نمط رسم؛ TradingView: https://www.tradingview.com/blog/en/new-release-of-stable-charting-library-and-trading-terminal-v1-14-12097/ يشرح وظيفة الخط والإحصاءات.
- **التنفيذ:** [011fd4c](https://github.com/775878805Osamaha/TradeLab/commit/011fd4c02618a529738d092c42cd7751cd37f9ac) `ChartDrawingTool.infoLine` مصدر مرساتين؛ [f8a0a67](https://github.com/775878805Osamaha/TradeLab/commit/f8a0a677c0872412b2b95dbcb61960b897af798a) تفعيل أداة الكتالوج؛ [6d61d23](https://github.com/775878805Osamaha/TradeLab/commit/6d61d2337eba096ef6b9dac3a3bbdb0ee4ee58da) رسم finite clipped؛ [fc088d3](https://github.com/775878805Osamaha/TradeLab/commit/fc088d3849c4e8fb005323ca24978e9a67c79e28) إحصاءات فرق السعر/% (فقط بمقام صالح)، بارز، زمن `abs(endUTC-startUTC)` والزاوية الهندسية، بنطاق Replay prefix؛ [42116af](https://github.com/775878805Osamaha/TradeLab/commit/42116af1a9e66aae07dde33d8d48d7ca8084c794) واجهة رسم عربية label ثنائي السطر من المصادر الحقيقية دون refetch/future.
- **الاختبارات:** [75883cb](https://github.com/775878805Osamaha/TradeLab/commit/75883cb4acde9e79e68e0091f9ea43285f1d1a3f) إحصاءات + UTC gaps + 120k anchor + Replay guard؛ [5f7425c](https://github.com/775878805Osamaha/TradeLab/commit/5f7425cbf571ab2baf824a8aad183d090dc55829) Flutter widget 320/390dp، [d6e420f](https://github.com/775878805Osamaha/TradeLab/commit/d6e420fed557145fd7f25f9d61a54540617b80e0) clipping/culling، [50b6d90](https://github.com/775878805Osamaha/TradeLab/commit/50b6d9010f8bd9fade652bbb29d63e3197558e00) catalog smoke؛ CI [1826561](https://github.com/775878805Osamaha/TradeLab/commit/1826561b734b56e0b912229a70cacf7762453819).
- **نتيجة التحقق الفعلية:** [PR #606](https://github.com/775878805Osamaha/TradeLab/pull/606) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند [SHA 28f3c53](https://github.com/775878805Osamaha/TradeLab/commit/28f3c53e53f8187e9acfc56406967edac2b84e64). [Actions #44963130021](https://github.com/775878805Osamaha/TradeLab/actions/runs/44963130021) **completed/success** على HEAD `b586f03d9cbd1c0af19b4da56e2f879eaa9ec5c8`: Flutter analyze؛ math/time/replay/120k/geometry؛ 320/390dp widget؛ Long/Short/Crossline/InfoLine catalogs؛ chart/Range/history/Replay/Yemen timezone. لا Android pixel screenshots/Profile FPS أو cTrader live. لا APK/Release ولا تعديل `main`/مشاريع أخرى.
- **التالي:** Trend Angle مثبت من المرجع مع رسم مصدر حقيقي واختبارات، ثم اختبار شاشة Android حقيقية.

### 2026-11-22 — Percent وIndexed to 100 على محور السعر بدلاً من الاقتصار على Regular/LOG
- **الفرع/الأساس:** `feat/tradelab-percent-indexed-price-axis-20261122` من `test/flutter-all-fixes-20261116` بعد PR #604.
- **المقارنة الرسمية:** https://www.tradingview.com/support/solutions/43000748166-how-to-configure-your-supercharts/ يذكر أربع وضعيات للمقياس، غاب وضعا Percent وIndexed100 عن TradeLab.
- **التنفيذ:** [9335451](https://github.com/775878805Osamaha/TradeLab/commit/9335451534ececc42ccd4fa3e730ed2b7af4a9fc) `ChartPriceReferenceMode` يحدد أساسًا موثوقًا من إغلاق أول شمعة مرئية ضمن CandlePrefix؛ Percent=(price/ref−1)×100، Indexed=price/ref×100، inverse إلى السعر الأصلي. لا تحوير OHLC أو أرقام التداول/الرسومات؛ [4963949](https://github.com/775878805Osamaha/TradeLab/commit/496394995265dc423fc2e6a211bfaf6edc22e738) مفتاح auto scale cache؛ [05bfd45](https://github.com/775878805Osamaha/TradeLab/commit/05bfd4548eee64364ebc2de8d151543f63ef6453) اختيار الوضعين من Flutter؛ [f5a0eb3](https://github.com/775878805Osamaha/TradeLab/commit/f5a0eb3b4ba2ba5c01b0925a9fc0ce5aa17c812e) فواصل محور السعر وتسميات crosshair/last/SL/TP/BID/ASK المحوّلة للعرض باستخدام هندسة السعر الحقيقي. مرجع البداية المؤقت **أول شمعة مرئية close**، يحتاج مقارنة فعليّة لمعرفة إذا كان مطابقًا لاختيار TradingView، لا يُدعى ذلك الآن.
- **اختبارات:** [5a78b3e](https://github.com/775878805Osamaha/TradeLab/commit/5a78b3e0673eb55623e6bf1eb58644847d4640a2) source price invariants/pan/Replay/cache/negative base؛ [8f669db](https://github.com/775878805Osamaha/TradeLab/commit/8f669db1e45d306bf3ca74346453d9caf85526d9) native settings selection؛ [d04e98f](https://github.com/775878805Osamaha/TradeLab/commit/d04e98f44e395d0af33576d7ad37f55d3db5ec94) full widget 320/390dp no refetch؛ [5a8a17d](https://github.com/775878805Osamaha/TradeLab/commit/5a8a17dd210b891240162183696b6e47c8d9e99b) CI.
- **مراجعة إضافية قبل CI:** [f46046a](https://github.com/775878805Osamaha/TradeLab/commit/f46046acf3254e9d16997f60edf4945ac0fc0a90) يستعمل `ChartPriceTextFormatter` القديم لكل الأوضاع للحفاظ على فواصل الآلاف، [4ae7b2d](https://github.com/775878805Osamaha/TradeLab/commit/4ae7b2da668acb94eb03c36ff1e44e6ed2f111e9) يحافظ على 12 منزلة لأسعار الفوركس الدقيقة، واختبار regression [7c558a2](https://github.com/775878805Osamaha/TradeLab/commit/7c558a2a346fcba80fadd75c5f4612ac96d8c946) يتحقق من `35,000.00` و`0.000000250000` و`2,000.00%`.
- **إخفاق فني مصحّح:** [Actions #44962030867](https://github.com/775878805Osamaha/TradeLab/actions/runs/44962030867) فشل في Flutter analyze، والسجل يحدد `chart_relative_price_scale_test.dart:158`: apostrophe في `'relative ruler's ticks ...'` قطعت سلسلة Dart، وأنتجت أخطاء parse متتابعة. [d227292](https://github.com/775878805Osamaha/TradeLab/commit/d227292787aefc67271831dd2317f29f3f49fc2c) عدّل اسم الاختبار إلى نص صالح. تحليل جديد وCI **PENDING**؛ لا ادعاء نجاح دون نتيجة.
- **نتيجة التنفيذ المؤكدة:** [PR #605](https://github.com/775878805Osamaha/TradeLab/pull/605) **MERGED/squash** في `test/flutter-all-fixes-20261116` عند [SHA 09a407f](https://github.com/775878805Osamaha/TradeLab/commit/09a407fabb072df95431ebfc25ad03c30f3a5384). [Actions #44962189024](https://github.com/775878805Osamaha/TradeLab/actions/runs/44962189024) **completed/success** على HEAD `c9bde00f0cfaff4d614e62ac9c027f0ad84a4fba`: Flutter analyze، math/cache/mode reference + Replay future tests، source-backed Flutter UI 320/390dp، chart/Range/history/Replay، Long/Short وCrossline catalog، Yemen timezone كلها ناجحة. الإخفاق الأول #44962030867 (apostrophe عنوان اختبار) موثق أعلاه وإصلاحه دُمج ضمن الرأس الناجح.
- **غير متحقق:** screenshot/pixel Android، Profile/FPS وcTrader live **NOT RUN**. المرجع المئوي أول visible source close قاعدة تنفيذ تحتاج مطابقة مع المرجع على Android، لا ادعاء 100%. لا APK/Release ولا تغيير `main` أو مشروع آخر.
- **التالي:** اختبارات أداء وصورة ومرجع مقارنة حقيقي ثم معالجة فروقات مثبتة من أدوات/شارت TradingView.

### 2026-11-22 — كثافة علامات محور السعر تتكيف مع ارتفاع شاشة Android
- **الفرع:** `fix/tradelab-mobile-price-axis-label-density-20261122` من `test/flutter-all-fixes-20261116` بعد PR #603.
- **المشكلة المثبتة:** 12 فاصل سعر ثابت في الشارت حتى لو صار plot بارتفاع 84dp أثناء Replay؛ تتراكب أرقام tick والتواريخ بصريًا. حجب التسميات المتقاربة كان ينفذ للـLOG فقط.
- **الإصلاح:** [b823484](https://github.com/775878805Osamaha/TradeLab/commit/b823484bba8373c1c87a16759596882af4329f4f) `intervalsForHeight` و`spacedByPixels` تأخذ إحداثيات المقياس الحالية وتتجنب التسميات خارج الحدود والمتقاربة وNaN؛ [d01ae5a](https://github.com/775878805Osamaha/TradeLab/commit/d01ae5a6496f07ebf6784d72f5927c1e7b36e406) يوحد فلاتر التسميات والخطوط في كل Linear/LOG وInverted بدون تغيير الأسعار.
- **التحقق المُعد:** [c840b0b](https://github.com/775878805Osamaha/TradeLab/commit/c840b0bd1ac37d36f31b4dab1b8ac2d1c8cff674) + [b2f8c7f](https://github.com/775878805Osamaha/TradeLab/commit/b2f8c7f30bfea694512ba66f488b16f23237104d) اختبارات 84/155/440dp، أقصى الفواصل، قيمة السوق/Replay وعكس المحور؛ [620303e](https://github.com/775878805Osamaha/TradeLab/commit/620303edcf5f5fc52024122a7db1bd26ca97d8ac) إدراج CI.
- **النتيجة المؤكدة:** [PR #604](https://github.com/775878805Osamaha/TradeLab/pull/604) **MERGED/squash** في `test/flutter-all-fixes-20261116` عند [SHA f722aa9](https://github.com/775878805Osamaha/TradeLab/commit/f722aa98a515d787f18bed17b280f7df69b0c4b8)، [Actions #44961365235](https://github.com/775878805Osamaha/TradeLab/actions/runs/44961365235) **completed/success** على HEAD `8f9fb8a7e1de2a1ce7829c09ced3c1868ac2cfe9`: Flutter analyze، chart/Range/Replay/history، mobile tick label geometry في 84/155/440dp وLOG/Invert، كتالوج الرسم وتوقيت اليمن كلها نجحت.
- **غير متحقق:** Pixel/Golden وAndroid Profile/FPS وcTrader live **NOT RUN**، لا APK/Release أو `main` أو مشروع آخر.
- **التالي:** مطابقة خيارات Percent/Indexed 100 وباقي فجوات السعر ضمن قواعد المصدر الأصلي.

### 2026-11-22 — عكس محور السعر من قائمة Android مع إحداثيات حقيقية وصفر تسرب Replay
- **الفرع:** `feat/tradelab-invert-price-axis-20261122` مبني على `test/flutter-all-fixes-20261116` بعد PR #602.
- **المرجع:** https://www.tradingview.com/support/solutions/43000475599-how-to-invert-reverse-the-chart-price-scale/
- **الفجوة المثبتة:** لم يكن عكس مقياس السعر متاحًا؛ كانت `ChartPriceScale` تفترض سعرًا أعلى عند y أصغر، وهذا يؤثر في الشموع والرسومات واللمس.
- **التنفيذ:** [5c2912a](https://github.com/775878805Osamaha/TradeLab/commit/5c2912aca0c46f5bb8969473914ad7619d4dfc75) inverse y/price، margins معكوسة وdrag anchored في LOG وlinear؛ [f7d18b5](https://github.com/775878805Osamaha/TradeLab/commit/f7d18b51c7900c28cda7257c7c0a3deb03dcbbad) cache key؛ [476298b](https://github.com/775878805Osamaha/TradeLab/commit/476298b32b8c14dfd82c4eac8ded872790467a20) إعداد محفوظ backward compatible؛ [039f9d9](https://github.com/775878805Osamaha/TradeLab/commit/039f9d9ae2192f30a01367a203e39a9ee2e28f9e) اختيار من قائمة الضغط المطول ومحافظة على source/viewport/Replay، [383bae9](https://github.com/775878805Osamaha/TradeLab/commit/383bae9e6604227516e4645d8df1dffd5a754f7e) إعدادات Flutter.
- **الاختبارات:** [3d0527f](https://github.com/775878805Osamaha/TradeLab/commit/3d0527fd9670c7553e196bb4160ff1daccc293e3) pure linear/LOG/invert/manual/Replay؛ [6cff05a](https://github.com/775878805Osamaha/TradeLab/commit/6cff05ae4331a5ce645afd724c071cefa288b50f) Android-width 320/390 context menu؛ [10c3d4c](https://github.com/775878805Osamaha/TradeLab/commit/10c3d4c82d2344d89cf36ae81b586d0d7bbb7193) settings persistence؛ [42a72ad](https://github.com/775878805Osamaha/TradeLab/commit/42a72ad7481c0f70ee2700d19f3997b078fbaf15) CI.
- **النتيجة الفعلية:** [PR #603](https://github.com/775878805Osamaha/TradeLab/pull/603) **MERGED/squash** في فرع التطوير `test/flutter-all-fixes-20261116` عند [SHA 908baa4](https://github.com/775878805Osamaha/TradeLab/commit/908baa43fdb82ac11579684923869ec9a1e442c7). [Actions #44960941431](https://github.com/775878805Osamaha/TradeLab/actions/runs/44960941431) **completed/success** على HEAD `d66ea3e97c8c1d87b6b756e5139070825e1ed5b2`: Flutter analyze، widget invert menu 320/390، pure LOG/linear inversion/anchor/Replay/cache tests، Flutter scales settings، chart/Range/history/Replay/timezone/catalog كلها نجحت.
- **القيود:** Android Profile/FPS وpixel screenshots TradingView وcTrader live **NOT RUN**. لا APK/Release أو main أو مشروع آخر.
- **التالي:** فحص Android بصري حقيقي ثم معالجة أي فروقات ملحوظة دون افتراض نجاح لم يتحقق.

### 2026-11-22 — مقياس LOG فعلي لنطاق السعر بدل اختيار غير عامل
- **Branch:** `feat/tradelab-real-logarithmic-price-scale-20261122` من `test/flutter-all-fixes-20261116` بعد PR #601.
- **الفجوة:** `chart_scale_settings_page.dart` كانت تحصر الوضع في `تلقائي` دون onSelected، و`ChartPriceScale` خطي دائمًا؛ مرجع TradingView Log: https://www.tradingview.com/support/solutions/43000748166-how-to-configure-your-supercharts/.
- **التنفيذ:** [3b3f1db](https://github.com/775878805Osamaha/TradeLab/commit/3b3f1db4ed9d2d77d9a33075f38f347309b0faf2) تحويلات السعر اللوغاريتمي في Auto/manual drag والتراجع الخطي للأرقام غير الموجبة؛ [34ef638](https://github.com/775878805Osamaha/TradeLab/commit/34ef638a524cd99f116407f0c17ca387fffc9b45) تدريج 1-2-5؛ [d277b9d](https://github.com/775878805Osamaha/TradeLab/commit/d277b9d66db5619668eeb34b8ba6988629f1603d) فصل cache؛ [8691473](https://github.com/775878805Osamaha/TradeLab/commit/8691473bbc5e615e8ef9756a2f2d931118b8335d) ضبط الوضع في الإعدادات؛ [b927963](https://github.com/775878805Osamaha/TradeLab/commit/b927963c5a1dc0cf72ccb56e04c6caf536ed4ae0) L/LOG مع إعدادات يدوية reset ومصدر حي دون إعادة تحميل.
- **اختبارات:** [8cb3c45](https://github.com/775878805Osamaha/TradeLab/commit/8cb3c45916b3d2c5e6bfd01bd721169d776ba3e4) invariants/margins/Replay/NaN/cache، [e26f972](https://github.com/775878805Osamaha/TradeLab/commit/e26f97274b22df3f2a214a7e245c8e16924c2c67) Widget 320/390dp toggle L-LOG-L، [53c018f](https://github.com/775878805Osamaha/TradeLab/commit/53c018f11c3cba0f8a27306593236d3a0da2dffa) حفظ إعدادات GUI، [ff3aa90](https://github.com/775878805Osamaha/TradeLab/commit/ff3aa90f5bf919567d1385042375143916028d52) إضافة CI.
- **نتيجة PR/CI:** [PR #602](https://github.com/775878805Osamaha/TradeLab/pull/602) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند [SHA 911f65d](https://github.com/775878805Osamaha/TradeLab/commit/911f65dcea16b4e12088fc697bd632a1920dea2b). [Actions #44960370219](https://github.com/775878805Osamaha/TradeLab/actions/runs/44960370219) **completed/success** على HEAD `f0ed43bf627bc92a31b345bf400808ca4dbe823b`. Flutter analyze، LOG pure geometry/Replay/cache، Widget L/LOG في عرض 320/390dp، إعدادات scale، chart/Range/history/Replay/timezone، كتالوج Long/Short وCrossline كل الاختبارات ناجحة.
- **ما لم يُنفذ:** Android Profile/FPS وTradingView pixel diff وcTrader live **NOT RUN**. لا APK/Release أو تعديل main أو مشروع آخر.
- **التالي:** اختبار الفروق البصرية واللمسية الفعلية للـLOG على Android مع المصدر المالي الموثوق.

### 2026-11-22 — تفعيل Crossline المتقاطع بخطّي الزمن والسعر من أصل الشمعة
- **فرع:** `feat/tradelab-crossline-drawing-20261122` من `test/flutter-all-fixes-20261116` بعد PR #600؛ `main` دون تعديل.
- **دليل وظيفي:** https://www.tradingview.com/support/solutions/43000477747-crossline-drawing-tool/ — تقاطع أفقي ورأسي من مرساة واحدة مع وسوم سعر/وقت.
- **الخلل:** `DrawingCatalogKind.crossLine` مرئي لكنه غير مفعل/لا محرك رسم. **التغيير:** [363e48c](https://github.com/775878805Osamaha/TradeLab/commit/363e48c047a8166676c992fd501a2ba8967bf897) `ChartDrawingTool.crossLine`/oneAnchor؛ [a471435](https://github.com/775878805Osamaha/TradeLab/commit/a4714352364327b3d1389a0d285f2fb18248657a) تمكين الكتالوج؛ [6af64e3](https://github.com/775878805Osamaha/TradeLab/commit/6af64e3e739f4d4660aa43eea491ea9fd6e12342) تقاطع وخطوط مقيدة بالمحاور مع culling محافظ؛ [83808f1](https://github.com/775878805Osamaha/TradeLab/commit/83808f1ef6ef4832a04ec89e477cfd1fc2b3255d) وسم سعر وزمن بتوقيت الشمعة الحقيقي. لا أسعار/شموع مختلقة ولا أمر بيع/شراء.
- **الفحوص المضافة:** [4532193](https://github.com/775878805Osamaha/TradeLab/commit/45321936d84b2297c7a7f4d6f9c199f60e97bf77) geometry؛ [1955bfc](https://github.com/775878805Osamaha/TradeLab/commit/1955bfc94cf5cc05d9832f7f5742ebdeb10a2530) Replay/one-anchor history؛ [861ec7a](https://github.com/775878805Osamaha/TradeLab/commit/861ec7a513a7fd37db0e47abb5c5b57620bd03a9) catalog؛ [8210218](https://github.com/775878805Osamaha/TradeLab/commit/82102181055601d39109982b8d86b0f0584565b2) widget 320/390dp؛ [bb91df7](https://github.com/775878805Osamaha/TradeLab/commit/bb91df7f1cdef8d3af100eda77879df4359d6a9f) أضافها CI.
- **التحقق النهائي:** [PR #601](https://github.com/775878805Osamaha/TradeLab/pull/601) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند [SHA 39a5243](https://github.com/775878805Osamaha/TradeLab/commit/39a52438d981b7c5575b421632138a7c2114d5ef). [Actions #44959351046](https://github.com/775878805Osamaha/TradeLab/actions/runs/44959351046) **completed/success** على HEAD `8341869112ceeb340a80cb79a4b83254f54b815f`: Flutter analyze، chart/Range/Replay/history، Crossline geometry/Replay/widget 320/390dp، كتالوج Crossline، وتوقيت اليمن نجحت.
- **المتبقي:** Android Profile/FPS وTradingView pixel-diff وcTrader live **NOT RUN**؛ خصائص line style/visibility المتقدمة غير مثبتة. لا APK/Release ولا تعديل main أو مشروع آخر.
- **التالي:** اختبارات هاتف ومقارنة بصرية فعلية ثم إصلاح فروقات ثابتة. سجّل كل مرحلة لاحقة في HANDOFF.

### 2026-11-22 — منع وسوم Stop/Target الشبحية لمراكز Long/Short خارج نافذة السعر
- **فرع:** `fix/tradelab-offscreen-position-axis-tags-20261122` من `test/flutter-all-fixes-20261116` بعد PR #599.
- **المشكلة المثبتة:** صندوق المركز كان يُحجب إذا خرج أفقيًا عن الشاشة، بينما وسوم SL/TP على محور السعر كانت تُرسم لكل مركز معلوم بالنطاق الزمني حتى عند الابتعاد عنه عشرات آلاف الشموع.
- **الإصلاح:** [a101c0f](https://github.com/775878805Osamaha/TradeLab/commit/a101c0f2d066fe57372284d2b7c3e7ffc2785e29) helper visibility موحد O(1) لفهرس الرسم مع `ChartViewport`؛ [f72a137](https://github.com/775878805Osamaha/TradeLab/commit/f72a137863ee14f2916aed15d269c05f6020d51d) ربط كل من box والوسوم بنفس الشرط، دون لمس OHLC أو كشف مستقبل Replay.
- **اختبار:** [2510f1b](https://github.com/775878805Osamaha/TradeLab/commit/2510f1b39f6f5ab70d939080c6da0fc03e8ef35d) يغطي 120k source bars، الحواف، العودة إلى الماضي، المستقبل وNaN على عرضين؛ [45bac91](https://github.com/775878805Osamaha/TradeLab/commit/45bac919c5a774509595c98b92329b0500efcfee) أدرجه في CI.
- **النتيجة المؤكدة:** [PR #600](https://github.com/775878805Osamaha/TradeLab/pull/600) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند [SHA 6ea0d87](https://github.com/775878805Osamaha/TradeLab/commit/6ea0d87134b01acc6329cccf804c6231b3858477). [Actions #44958775049](https://github.com/775878805Osamaha/TradeLab/actions/runs/44958775049) **completed/success** على HEAD `7b8e32d29ffa9fff7d0888a3cd08df643b9c6859`: Flutter analyze، 120k viewport visibility tests، chart/Range/Replay/history، long/short catalog وYemen timezone كلها نجحت.
- **ما لم يُنفذ:** Android Profile/FPS، مقارنة TradingView pixel وcTrader live **NOT RUN**. لا APK/Release، ولا تغيير `main` أو مشاريع أخرى.
- **التالي:** اختبار مرئي ولمسي على هاتف Android حقيقي ببيانات حقيقية ثم معالجة فروقات مثبتة بالأدلة.

### 2026-11-22 — منع إعادة بناء واجهة الشارت لكل عينة إصبع أثناء سحب مركز Long/Short
- **Branch:** `perf/tradelab-position-drag-paint-only-20261122` من `test/flutter-all-fixes-20261116` بعد PR #598؛ لا APK ولا تغيير `main`.
- **المشكلة المثبتة:** مسار `_draggingShortHandle` في `ChartScreen.onScaleUpdate` كان يحدث `setState` لكل حركة مما يعيد بناء الرأس/الأدوات والرسومات، في حين تستخدم خطوط الاتجاه painter retained. لم يُقَس زمن الإطارات فعليًا على Android.
- **الكود:** [5a39fc4](https://github.com/775878805Osamaha/TradeLab/commit/5a39fc405f9927635adcadc204fcd1661d3ce762) يدعم callback live لرسومات الشراء/البيع وselection داخل painter، ويحوّل تحرير المقبض إلى `_chartRepaint` مع `setState` واحدة عند الإفلات؛ يمنع no-op refresh. هندسة السعر/الزمن والحسابات وReplay وcTrader/Binance غير متغيرة.
- **الاختبار:** [b0253a9](https://github.com/775878805Osamaha/TradeLab/commit/b0253a9723a09216983b243d23bc504c434de8dd) Widget test لأربعة سيناريوهات Long/Short في 320/390dp، يتحقق من تطور stop وعدم إعادة بناء الشريط العلوي أثناء خمس عينات. [ae9c6f8](https://github.com/775878805Osamaha/TradeLab/commit/ae9c6f84706fea67588fec43f1d2ada9f50c499f) يضيف الاختبار إلى CI.
- **نتيجة PR والاختبار النهائي:** [PR #599](https://github.com/775878805Osamaha/TradeLab/pull/599) **MERGED/squash** في `test/flutter-all-fixes-20261116` عند [SHA 1629424](https://github.com/775878805Osamaha/TradeLab/commit/1629424deb1413adc9691c5ca74d4fe043baa28a). [Actions #44958411202](https://github.com/775878805Osamaha/TradeLab/actions/runs/44958411202) **completed/success** على HEAD `4f3af579ea484d196a07f8d28b1b6377139c72cd`: Flutter analyze، اختبارات المصدر والشارت/Range/Replay/history، فحص Long/Short وYemen timezone ناجحة، شاملة 4 سيناريوهات ثبات Header خلال 5 تحركات وقف/هدف Long/Short على 320/390dp.
- **القيود:** Android Profile/FPS وTradingView screenshot pixel-diff وcTrader live **NOT RUN**؛ لا تقدير أداء رقمي مفبرك ولا APK/Release أو تغيير main.
- **التالي:** قياس أداء هاتف فعلي، معالجة أكبر فجوة ثابتة بالاختبارات، تسجيل نتيجة كل PR هنا وفي HANDOFF.

### 2026-11-21 — تفعيل أداة Long Position الفعلية في TradeLab Flutter
- **الفرع:** `feat/tradelab-long-position-drawing-20261121` من فرع التطوير `test/flutter-all-fixes-20261116` بعد PR #597؛ `main` لا يتغير.
- **الدليل:** `DrawingCatalogKind.longPosition` مسجل في القائمة والمفضلة، لكن `implemented=false`، بينما `ChartScreen` لا يدعم إلا `_selectDrawingMode(short: true)`.
- **التنفيذ:** [1a59748](https://github.com/775878805Osamaha/TradeLab/commit/1a59748c676795d34fd5800e21b88e938c8fe023) نموذج long/short risk/reward؛ [ef85764](https://github.com/775878805Osamaha/TradeLab/commit/ef857640fca06749727d8c05e0d65338bba27996) استقبال 3 نقاط سعر حقيقية وهندسة hit-test؛ [82bc45e](https://github.com/775878805Osamaha/TradeLab/commit/82bc45e47b1c17281c706052fac9548a78253d61) مستطيلات Long باتجاه صحيح؛ [d960ff4](https://github.com/775878805Osamaha/TradeLab/commit/d960ff488fe60c41854b8b455d887ab92d89c13c) تفعيل أداة الشراء في الكتالوج.
- **الاختبارات:** [be90da1](https://github.com/775878805Osamaha/TradeLab/commit/be90da13b7d51b05396d61dd57a42b5568c49472) وحدات Long/Short؛ [f536631](https://github.com/775878805Osamaha/TradeLab/commit/f536631151131c898ce0f10b6de8ad824d9275c2) catalog; [3caf9b9](https://github.com/775878805Osamaha/TradeLab/commit/3caf9b93e9581ff86b6eda9f0820941001c12945) Widget Android 320/390dp؛ [bd48aa4](https://github.com/775878805Osamaha/TradeLab/commit/bd48aa43bec7bcdd1feaa904a45c45f836d6e55a) أدخلها بوابة CI. بيانات الاختبار معزولة ولا تحل محل مزودي السوق.
- **نتيجة المحاولة الأولى:** [PR #598](https://github.com/775878805Osamaha/TradeLab/pull/598) مفتوح؛ [Actions #44939700685](https://github.com/775878805Osamaha/TradeLab/actions/runs/44939700685) **completed/failure**: Flutter analyze PASS، 709 اختبار PASS بما فيها اختبارات Long الجديدة وWidget 320/390dp؛ 4 FAIL هي Golden Tests في `drawing_tools_sheet_test.dart` لعدم وجود `goldens/*.png` الأصلية. لا تعتبر الفشل دليلًا على خلل في Long ولا تولّد صورًا بديلة وهمية.
- **التحقق النهائي بعد الإصلاح:** [GitHub Actions #44940022375](https://github.com/775878805Osamaha/TradeLab/actions/runs/44940022375) **completed/success** على HEAD `cccef12c1085487272062481ada802d75a777cc1`: Flutter analyze، chart/history/Range/Replay، اختبار كتالوج Long/Short المحدد عبر `--plain-name`، واختبارات توقيت اليمن كلها ناجحة. اختبارات Golden الأصلية باقية في المصدر لكنها غير قابلة للتشغيل في CI دون ملفات PNG المرجعية.
- **الدمج الحقيقي:** [PR #598](https://github.com/775878805Osamaha/TradeLab/pull/598) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند commit [c44b4dc](https://github.com/775878805Osamaha/TradeLab/commit/c44b4dc319ef1afed05d9c147316be1b31a438a5). تم التحقق من نجاح بوابة PR، ولا APK/Release أو تغيير `main`.
- **القيود والخطوة التالية:** Android Profile/FPS، مقارنة صور مرجع TradingView وLive cTrader **NOT RUN**؛ اختبار Long على جهاز Android فعلي مطلوب قبل إعلان «طبق الأصل». حافظ على إبلاغ حالة Golden المرجعية المفقودة دون تعويض اصطناعي.

### 2026-11-21 — إلغاء تحرير خط الرسم المؤقت عند تغيير مصدر الشموع
- **الفرع:** `fix/tradelab-stale-doubletap-guide-session-20261121` مشتق من فرع تطوير TradeLab بعد PR #596.
- **المصدر المعاين:** `_doubleTapGuideArmed` يستمر من نقرة مزدوجة قديمة عندما يتبدل الرمز/الشموع أو يخرج المستخدم من الشارت، وقد يلتقط سحبة خاطئة على محور الوقت/السعر؛ لم يكن وضع التحرير يحمل هوية المصدر أو نطاق الرسم.
- **التنفيذ:** [58a7bb3](https://github.com/775878805Osamaha/TradeLab/commit/58a7bb34b0599b3e3a124897d6b6cfaf2d6ab4c4) — `chart_screen.dart` تضيف حارس مصدر الشموع ومفتاح الجلسة وحدود الرسم وإلغاء الحالة عند انتقالات الشارت وحركة الأدوات. [23b3ae2](https://github.com/775878805Osamaha/TradeLab/commit/23b3ae2680dc33f5a76ca6e7743e379c57fb6c46) — اختبار widget يعيد سيناريو BTCUSDT→ETHUSDT وإخفاء التبويب مع إعداد خط سابق للنقل.
- **النتيجة النهائية:** [PR #597](https://github.com/775878805Osamaha/TradeLab/pull/597) **MERGED/squash** في `test/flutter-all-fixes-20261116` عند SHA [465067c](https://github.com/775878805Osamaha/TradeLab/commit/465067c30dc4bcdc9ff186b4f2137ce6315b4434). [Actions #44939023798](https://github.com/775878805Osamaha/TradeLab/actions/runs/44939023798) **completed/success** على HEAD `a2b61017335aa611e89628598062006da90c7a2f`: تحليل Flutter واختبارات الشارت/Range/Replay/history وتوقيت اليمن اجتازت. تأكيد الدمج لا يساوي اختبار Android فعلي.
- **ما لم يُنفذ:** Flutter المحلي، Android Profile/FPS، Live cTrader، مقارنة صور TradingView **NOT RUN**. لا APK/Release ولا تغيير `main` أو مشاريع أخرى.
- **التالي:** أكمل أصغر فجوة وظيفية مؤكدة في أدوات TradingView أو اطلب بيانات قياس Android حقيقية؛ وثّق كل PR في هذا الملف.

### 2026-11-21 — إصلاح سلوك النقر المزدوج على خطوط الرسم في Android
- **الفرع:** `fix/tradelab-mobile-doubletap-drawing-move-20261121` من فرع تطوير TradeLab بعد PR #595؛ `main` محفوظ.
- **المصدر:** https://www.tradingview.com/charting-library-docs/latest/mobile_specifics/ — النقر المزدوج على خط رسم يفعّل تحريك الخط؛ TradeLab كان يعيد موضع الشارت بدل ذلك.
- **تعديل الشيفرة:** [b048951](https://github.com/775878805Osamaha/TradeLab/commit/b048951af4893cc356ec6cbdf2847736c417a148) — hit-test لخط حقيقي على إحداثيات النقرة، تحرير لسحبة واحدة، منع خطوط مقفلة/مخفية/مستقبل Replay، وإبقاء إعادة الشارت بالنقر على الفراغ ومحور السعر AUTO.
- **إضافة اختبار:** [fa57531](https://github.com/775878805Osamaha/TradeLab/commit/fa5753196c957743ca8d50d3e1cef0dd6c8d7356) — widget Android layouts 320/390dp، رسم أصلي بمصدر fixture اختبار فقط ثم سحبه بالنقر المزدوج، منع تكرار الرسم.
- **التنفيذ النهائي:** أضيف `chart_double_tap_guide_test.dart` إلى workflow CI عبر [1c46219](https://github.com/775878805Osamaha/TradeLab/commit/1c46219daf37043e67815cd9d633fc288c1356cc). [PR #596](https://github.com/775878805Osamaha/TradeLab/pull/596) **MERGED/squash** في فرع التطوير عند [875073c](https://github.com/775878805Osamaha/TradeLab/commit/875073c64136ca2249aac2700feb9e8ae5e5be5a). [Actions #44938475089](https://github.com/775878805Osamaha/TradeLab/actions/runs/44938475089) **completed/success** على HEAD `1c46219daf37043e67815cd9d633fc288c1356cc`: Flutter analyze، اختبارات الشارت/Range/Replay/history مع test الجديد 320/390dp، واختبارات Yemen timezone ناجحة. التشغيل الأول 44938418454 ألغي تلقائيًا بعد تحديث workflow، وليس FAIL.
- **ما لم ينفذ:** Android Profile/FPS، مقارنة بكسل TradingView، cTrader live **NOT RUN**؛ لا APK/Release أو تعديل main/مشاريع أخرى.
- **التالي:** متابعة فروقات TradingView المثبتة من الكود أو القياس على Android حقيقي، ثم تحديث HANDOFF بعد كل رفع/دمج.

### 2026-11-21 — دفعة أداء Replay: إعادة استخدام CandlePrefix الموثق
- **الحدث:** إنشاء `perf/tradelab-replay-prefix-stability-20261121` من `test/flutter-all-fixes-20261116`، بدون تعديل `main`.
- **المشكلة المثبتة من الشيفرة:** `_displayCandles` كان يُنشئ قائمة Replay مغلفة جديدة عند إعادة بناء الواجهة مع نفس مصدر OHLC ونفس حد الكشف، فيُبطل `ChartPriceScaleCache` حتى لو لم تتحرك حدود الشموع. هذا مسار حساب إضافي؛ تأثيره الزمني على هاتف حقيقي **غير مقاس**.
- **Commit 1:** [00c143c](https://github.com/775878805Osamaha/TradeLab/commit/00c143c4c9ab93ee41ba6de9dffdbcbd853c7f27) — `flutter_app/lib/chart/candle_prefix.dart`: cache خانة واحدة، source identity/count/bounded through، لا كشف للمستقبل.
- **Commit 2:** [6c5dc97](https://github.com/775878805Osamaha/TradeLab/commit/6c5dc970518dfb507423d064e461c4d8c8fa3f32) — `flutter_app/lib/screens/chart_screen.dart`: الاستخدام في وضع Replay مع Candles/Range/Heikin-Ashi وتحرير cache في dispose.
- **Commit 3:** [7d92c2e](https://github.com/775878805Osamaha/TradeLab/commit/7d92c2e68665bb873bffeb7d03c799c8bbc68794) — `flutter_app/test/candle_prefix_test.dart`: ثبات الهوية، تغير cutoff، استبدال المصدر، منع المستقبل، وهندسة مقياس السعر.
- **نتيجة التحقق:** [PR #595](https://github.com/775878805Osamaha/TradeLab/pull/595) **MERGED/squash** في `test/flutter-all-fixes-20261116`، SHA الدمج [b57bb7e](https://github.com/775878805Osamaha/TradeLab/commit/b57bb7e889565b82d0e1cee4144cc277671a0d47). [Actions #44937767094](https://github.com/775878805Osamaha/TradeLab/actions/runs/44937767094) **completed/success** على HEAD `23d7238129fb24b0df4e89a5461dd44f28eb641d`: Flutter analyze، chart/Range/Replay/history، Yemen timezone كلها ناجحة. تأكدنا من ظهور `CandlePrefixCache` في مصدر فرع التطوير بعد الدمج.
- **القيود:** Flutter المحلي وAndroid Profile/FPS وcTrader حي واختبار TradingView البصري **NOT RUN**. لا نسبة أداء مقاسة؛ لا APK/Release ولا تغيير `main` أو مشروع آخر.
- **التالي:** قياس السحب/التكبير وReplay على Android Profile فعلي ضمن بيانات المصدر الموثقة ومع حمل تاريخي كبير؛ معالجة فرق p50/p95/p99 المثبت فقط. دفعة توثيق ما بعد الدمج لا تغير شيفرة Flutter.

### 2026-11-20 — تمهيد سجل الاستكمال
- الحدث: إنشاء بروتوكول التسليم الدائم لهذه النسخة من TradeLab (ملف الوكلاء + حالة الاستكمال + سجل الأحداث)؛ **توثيق فقط، دون تغيير شيفرة التطبيق أو تشغيل APK**.
- مرجع الكود قبل إنشاء التوثيق: [7fa9fd4](https://github.com/775878805Osamaha/TradeLab/commit/7fa9fd4ceabb6e878b9d6a80c818349b63ee2a76)، فرع `test/flutter-all-fixes-20261116`.
- التغيير السابق الواجب حمله إلى أي محادثة: [PR #563](https://github.com/775878805Osamaha/TradeLab/pull/563) دمج وتحليل واختبارات [44791818293](https://github.com/775878805Osamaha/TradeLab/actions/runs/44791818293) ناجحة (563 Flutter و7 Yemen).
- التحقق من هذا الحدث: حفظ ملفات Markdown في GitHub والتحقق من قراءتها بعد Commit؛ **لم تُشغّل اختبارات Flutter لهذا الحدث التوثيقي**.
- التالي: القياس على Android، وتحسينات الشارت/Replay حسب الدليل؛ سجّل كل عملية جديدة هنا بالوقت والرابط والنتيجة.

### 2026-11-20T18:57:29.353Z — حماية Replay وRange من فساد هندسة الشارت (PR #564)
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، فرع تنفيذ `fix/chart-replay-range-viewport-guards-20261120` من رأس التطوير `85eaed0c9a34695d1b7ca3d472eed77f85c92a5e`؛ `main` لم يتغير.
- **الإجراء والنتيجة:** إنشاء الفرع، رفع حماية حسابات `revealHistoricalBar` و`remapHistoricalAnchor` من قيم `NaN` / `Infinity` وعرض الشمعة الصفري/شديد الصغر، ثم إضافة اختباري انحدار وفتح [PR #564](https://github.com/775878805Osamaha/TradeLab/pull/564) لفرع التطوير فقط.
- **Commit الشيفرة:** [594a7c2](https://github.com/775878805Osamaha/TradeLab/commit/594a7c2470a123944de0c6bb7b5a010d9165d00d) و[ad9a5a0](https://github.com/775878805Osamaha/TradeLab/commit/ad9a5a0933ed663cd6ad8aba684402cffdd01930).
- **الملفات:** `flutter_app/lib/chart/chart_viewport.dart`، `flutter_app/test/chart_viewport_test.dart`، وملفات التسليم.
- **التحقق:** اختبار الجهاز الفعلي **NOT RUN**، Flutter محليًا **NOT RUN** (SDK غير متوفر). [GitHub Actions #44797495267](https://github.com/775878805Osamaha/TradeLab/actions/runs/44797495267) **PENDING** عند الكتابة؛ لا ترفع الحالة إلى PASS قبل نتيجة مؤكدة.
- **حدود التنفيذ:** لا توجد أسعار وهمية أو طلبات وسيط أو تسريب بيانات Replay المستقبلية؛ لم يُبن APK أو Release.
- **العائق والخطوة التالية الواحدة:** افحص نتيجة Actions #44797495267؛ عند PASS راجع الدمج في فرع التطوير فقط، وعند FAIL أصلح الخطأ في نفس PR، ثم وثق النتيجة الفعلية وSHA الدمج.

### 2026-11-20T19:02:01.840Z — اجتياز CI ودمج PR #564 في فرع التطوير
- **النتيجة:** [PR #564](https://github.com/775878805Osamaha/TradeLab/pull/564) **MERGED** بتاريخ `2026-11-20T19:01:01Z` في `test/flutter-all-fixes-20261116`، SHA الدمج الفعلي [8eb8451](https://github.com/775878805Osamaha/TradeLab/commit/8eb845120de323788e2ec819719209249fa27093). بقي `main` عند `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` دون تغيير.
- **الاختبار المؤكد قبل الدمج:** [Actions #44797725643](https://github.com/775878805Osamaha/TradeLab/actions/runs/44797725643) = **PASS / completed / success** لرأس PR `4e1bde1abe9e5e69b52866c8084bc2d29d8438cf`، ويشمل فحص Flutter وتحليل Dart واختبارات الشارت/Range/Replay وتوقيت اليمن. لم يُجر اختبار Android Profile على هاتف.
- **المحاولات السابقة:** Actions `#44797495267` و`#44797647321` أُلغيَتا تلقائيًا بعد تحديث PR؛ ليستا نتائج FAIL للاختبارات. لتقليل استهلاك الحصة، لم تُشغّل إعادة فحص يدوي بعد نجاح المسار النهائي.
- **الملفات المحفوظة:** `flutter_app/lib/chart/chart_viewport.dart` و`flutter_app/test/chart_viewport_test.dart` و`docs/CHANGE_REPORTS.md` و`docs/HANDOFF.md`. التغيير لا يمس مصادر الأسعار أو Replay المستقبلية أو التطبيق الرئيسي.
- **التحقق بعد الدمج:** تم جلب رأس فرع التطوير SHA `8eb8451` وفحص نص الحماية في ملف المصدر على GitHub؛ **لم يُشغّل CI منفصل بعد الدمج**. لا APK ولا Release.
- **الخطوة التالية الواحدة:** قياس تفاعل السحب والتكبير والقصور على Android Profile فعلي باستخدام `TRADELAB_PROFILE_CHART=true` ثم معالجة أول اختناق تظهره القياسات؛ لا تدّعِ FPS من اختبارات وحدة فقط.

### 2026-11-20T19:10:36.643Z — معالجة انقطاع عينة Android أثناء التكبير بإصبعين (PR قبل الفتح)
- **المستودع والفرع:** `775878805Osamaha/TradeLab` / `fix/chart-pinch-midgesture-rebase-20261120`، أُنشئ من فرع التطوير `test/flutter-all-fixes-20261116` بعد PR #564؛ لا تعديل على `main`.
- **الفعل والنتيجة:** وُجدت مشكلة في `ChartTouchGesture.update`: رفض عينة غير صالحة أثناء pinch فعال لا يمسح نقطة التكبير القديمة؛ يمكن للعينة التالية بإحداثيات جديدة أن تنقل الشموع فجأة. الآن يُلغى مرجع pinch الداخلي عند العينة غير الصالحة، وتثبت أول عينة صحيحة تالية مرجعًا من الـ viewport الحالي؛ لا تغيير لقيم الأسعار أو شموع Range/Replay أو للحركات السليمة.
- **التعديلات:** `flutter_app/lib/chart/chart_viewport.dart` ([964719c](https://github.com/775878805Osamaha/TradeLab/commit/964719c62b37a5cffe948cd35df81933151069fc))، `flutter_app/test/chart_viewport_test.dart` ([53e7a75](https://github.com/775878805Osamaha/TradeLab/commit/53e7a75ce845ccd5f8bfe4caaf0d24b8bda3f07a))، وملفا التوثيق؛ اختبار جديد لانقطاع العينة في منتصف pinch مرتين، واستئناف التحريك عند رفع الإصبع.
- **التحقق عند الكتابة:** تحليل Flutter المحلي **NOT RUN** (SDK غير متاح)، Android Profile **NOT RUN**، GitHub PR/CI **PENDING** حتى فتح PR؛ لا تدعِ PASS قبل نتيجة Actions الفعلية.
- **القيود:** لا APK، لا Release، لا اتصال وسيط جديد ولا أسعار وهمية ولا تعديل `main`.
- **الخطوة التالية الوحيدة:** افتح PR إلى فرع التطوير، راقب بوابة CI دون رفع commits أثناءها، أصلح أي فشل قبل الدمج، ثم سجل SHA الدمج ونتيجة الفحص النهائية.

### 2026-11-20T19:13:05.042Z — استكمال حماية الانتقال من إصبعين إلى إصبع بعد عينة غير صالحة
- **الفرع/الحالة:** `fix/chart-pinch-midgesture-rebase-20261120`، [PR #565](https://github.com/775878805Osamaha/TradeLab/pull/565) مفتوح. أثناء مراجعة الإصلاح قبل الدمج تبين أن تصفير `_pinching` عند رفض عينة في منتصف pinch قد يسمح بقراءة فرق مركز إصبع واحد كحركة pan. **تمت معالجة ذلك في نفس PR.**
- **الملفات:** `flutter_app/lib/chart/chart_viewport.dart` و`flutter_app/test/chart_viewport_test.dart` وملفا التوثيق. الآن يُلغى مرجع pinch فقط وتبقى علامة وجود إصبعين إلى أن يحدث انتقال فعلي إلى إصبع واحد، مع تجاهل أول عينة انتقال؛ أضيف اختبار يرفع إصبعًا مباشرة بعد NaN ويثبت عدم قفز الرسم واستئناف السحب الصحيح.
- **التحقق:** Flutter/Android محلي **NOT RUN**؛ CI للنسخة النهائية **PENDING** بعد رفع هذا الالتزام الواحد؛ قد يلغي GitHub الفحص السابق للـ PR عند تحديث الرأس. لا أسعار وهمية ولا APK ولا تغيير `main`.
- **الخطوة التالية:** انتظر نتيجة CI لرأس PR النهائي؛ أصلح أي فشل، ثم دمج في فرع التطوير فقط ووثق SHA ونتيجة Actions.

### 2026-11-20T19:16:45.013Z — فحص ناجح ودمج نهائي لتصحيح انقطاع التكبير PR #565
- **النتيجة الحقيقية:** [PR #565](https://github.com/775878805Osamaha/TradeLab/pull/565) **MERGED** في `test/flutter-all-fixes-20261116`، SHA: [62949ec](https://github.com/775878805Osamaha/TradeLab/commit/62949ec1f29af9aa94869f8a8574a54706cbae5c). تحققنا من رأس الفرع بعد الدمج، بينما `main` بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` دون تعديل.
- **الاختبارات:** [GitHub Actions #44800109737](https://github.com/775878805Osamaha/TradeLab/actions/runs/44800109737) = **PASS (completed/success)** لرأس PR النهائي `8b92dbe33fc99cf1ee2233be4a5c49989656dc29`؛ خطوات `flutter analyze` واختبارات الشارت/Range/Replay والـtimezone جميعها ناجحة. لا يدّعي ذلك نجاح فحص أجهزة Android حقيقية.
- **الأثر:** استرداد مركز تكبير بإصبعين بعد عينات `NaN`/`Infinity` دون قفزة مفاجئة؛ تجاهل انتقال مركز اللمس الوهمي عند رفع إصبع مباشرة بعد انقطاع العينة؛ لا تغيير في البيانات المصدرية أو Replay أو سوق التداول.
- **الملفات:** `flutter_app/lib/chart/chart_viewport.dart`, `flutter_app/test/chart_viewport_test.dart`, `docs/CHANGE_REPORTS.md`, `docs/HANDOFF.md`.
- **ما لم يُنفَّذ:** Android Profile على جهاز حقيقي **NOT RUN**؛ لا APK ولا Release، ولا اختبار مستقل بعد squash merge (بوابة PR النهائية ناجحة).
- **الخطوة التالية الواحدة:** قياس pan/pinch/momentum على Android Profile حقيقي وحفظ p50/p95/p99، ثم إصلاح أول اختناق مثبت على فرع التطوير فقط.

### 2026-11-20T19:41:26.618Z — تسليم APK اختبار ناجح برابط مباشر (PR #566 مغلق دون دمج)
- **الموافقة:** المستخدم طلب «APK انشاء حتى اختبرة» بعد سياسة عدم بناء APK سابقًا؛ تفويض نسخة اختبار واحدة فقط.
- **المشروع/الفرع:** `775878805Osamaha/TradeLab`، كود المصدر المدمج في `test/flutter-all-fixes-20261116` عند SHA `03794ca53590accb7ae777d5889bd72f5c66a90f`، فرع البناء المنفصل `test/tradelab-phone-apk-20261120` عند SHA `6cecd765d1c29b3e9e460d18fe2ffaf8269ed494` (ملفات التوثيق وworkflow فقط فوق كود التطوير). `main` دون تغيير.
- **النتيجة:** [GitHub Actions #44803312522](https://github.com/775878805Osamaha/TradeLab/actions/runs/44803312522) **completed/success**، بما في ذلك Flutter analyze واختبارات chart/Range/Replay/OAuth و`flutter build apk --release`، التحقق من `unzip -t`، فحص توقيع `apksigner verify`، وفحص package ID `com.example.tradelab_flutter.test2`، ورفع Artifact ونشر Release.
- **التنزيل المؤكد:** [TradeLab-Android-Test.apk](https://github.com/775878805Osamaha/TradeLab/releases/download/tradelab-phone-test-6cecd765d1c2/TradeLab-Android-Test.apk) (**59,096,319 bytes**، حالة asset `uploaded`) و[SHA256](https://github.com/775878805Osamaha/TradeLab/releases/download/tradelab-phone-test-6cecd765d1c2/TradeLab-Android-Test.apk.sha256) و[صفحة إصدار الاختبار](https://github.com/775878805Osamaha/TradeLab/releases/tag/tradelab-phone-test-6cecd765d1c2).
- **PR والأمان:** [#566](https://github.com/775878805Osamaha/TradeLab/pull/566) **CLOSED / NOT MERGED** بعد نجاح البناء للحفاظ على workflow أحادي الاستعمال خارج فرع التطوير. لا تشغيل متكرر أو تعديل السوق أو إصدار إنتاجي.
- **قيود الاختبار:** لم يتم تشغيل APK على هاتف المستخدم أو قياس FPS فعلي/اختبار دخول cTrader الفعلي؛ التوقيع التجريبي المؤقت قد يختلف عن توقيع APK سابق لحزمة test2، لذا قد يحتاج حذف **TradeLab Test 2 القديم فقط** قبل تثبيت الاختبار الجديد، مع إبقاء التطبيق الأصلي.
- **الملفات التي تحمل هذا التوثيق:** `docs/CHANGE_REPORTS.md` و`docs/HANDOFF.md` و`AGENTS.md`، دون تغيير كود Flutter.
- **الخطوة التالية الواحدة:** اختبار أحدث APK على Android ورفع ملاحظات اللمس/السحب/Range/Replay ولقطات الشاشة، ثم إصلاح المشكلات المثبتة قبل طلب بناء جديد.

### 2026-11-20T20:50:00.625Z — التحقق من تعارض OHLC للشموع المتداخلة عند جلب التاريخ الأقدم
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، فرع `fix/tradelab-older-ohlc-overlap-20261120` انطلاقًا من `test/flutter-all-fixes-20261116` SHA `facacf9b3eb4da10a367e926eb3d5569bf19b083`. يظل `main` كما هو؛ لا بناء APK.
- **المشكلة المؤكدة بالكود:** `OlderCandlePrepend.prepare` كان يتجاهل جميع نتائج الوسيط ذات الوقت `>= earliest` حتى عندما يختلف OHLC لشمعة موجودة؛ هذا يخفي اختلاف مصدر تاريخي مهم عن Replay. لم ندّعِ وقوع تعارض فعلي في بيانات الحساب.
- **التعديل:** lookup ثنائي O(log N) لكل وقت متداخل ضمن القائمة الموثّقة المتصاعدة؛ إذا وجد نفس وقت الشمعة واختلفت أي من قيم OHLC يتم إيقاف الدمج بخطأ `MarketDataException`، دون تغيير التاريخ أو إعادة رسمه. التطابقات الصالحة تمر بلا نسخ، والفجوات الحقيقية تبقى كما كانت. لا تغيير في مصادر cTrader/Binance أو حساب Range.
- **الملفات:** `flutter_app/lib/data/older_candle_prepend.dart` و`flutter_app/test/older_candle_prepend_test.dart` و`docs/CHANGE_REPORTS.md` و`docs/HANDOFF.md`.
- **اختبارات جديدة:** رفض تعارض الشمعة الحدية، رفض تعارض داخل تاريخ متداخل، الاحتفاظ بفجوة التاريخ المتحقّق، وحالة 120,000 شمعة ذات عدّاد قراءات للتأكد أن التحقق لا يعيد مسح الأرشيف بالكامل.
- **التحقق وقت الحفظ:** GitHub CI **PENDING** بعد فتح PR؛ تنفيذ Flutter محليًا وAndroid Profile **NOT RUN**. لا يُدّعى PASS أو قياس FPS قبل نتيجة GitHub.
- **الخطوة التالية الوحيدة:** افتح PR إلى فرع التطوير، افحص Flutter analyze وكل اختبارات chart/Range/Replay؛ في حالة النجاح ادمج إلى فرع التطوير فقط، وفي حالة الفشل أصلح الاختبارات ثم سجّل النتيجة وSHA الفعلي.

### 2026-11-20T20:53:26.608Z — نجاح اختبارات ودمج PR #567 للتحقق من OHLC المتداخل
- **النتيجة:** [PR #567](https://github.com/775878805Osamaha/TradeLab/pull/567) **MERGED** في `test/flutter-all-fixes-20261116` بتاريخ 2026-11-20، SHA الحقيقي [68169f9](https://github.com/775878805Osamaha/TradeLab/commit/68169f92627c40983c195872bf50c9836f8eff36). تم جلب رأس الفرع وقراءة ملف المصدر بعد الدمج للتأكد أن الإصلاح موجود. بقي `main` عند `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` دون تغيير.
- **CI:** [GitHub Actions #44814969933](https://github.com/775878805Osamaha/TradeLab/actions/runs/44814969933) = **PASS / completed / success** على HEAD الإصلاح `d40b0890008a55690bc46d8f3254f3b31046e992`، مع نجاح تحليل Flutter واختبارات الشارت/Range/Replay/التاريخ وتوقيت اليمن. لا تدّعِ نتائج قياس Android FPS.
- **أثر الكود:** لا يتم إسقاط تكرار شمعة تاريخية لها نفس timestamp ومختلف open/high/low/close بصمت؛ يرفض الدمج برسالة `MarketDataException`. يحتفظ بالأرشيف الأصلي وبفجوات المصدر، ويتحقق من التطابق ببحث O(log N) دون فحص كامل 120k شمعة. 3 اختبارات انحدار جديدة.
- **ملفات المصدر والاختبار:** `flutter_app/lib/data/older_candle_prepend.dart` و`flutter_app/test/older_candle_prepend_test.dart`. ملفات التسليم: `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`.
- **الحالة غير المكتملة:** لم يُشغّل APK جديد بعد هذه التعديلات؛ ملف APK المنشور سابقًا بتاريخ 2026-11-20 يسبق PR #567 ولا يتضمنه. لم تُنفّذ جلسة Android Profile ولا اختبار اتصال cTrader الفعلي. لا تغيير على `main`.
- **الخطوة التالية الوحيدة:** افحص ملاحظات اختبار APK الحالي على الجوال إن توفرت، ثم عالج خللًا مثبتًا آخر من شارت Range/Replay مع CI، دون إنشاء APK جديد إلا بطلب المستخدم.

### 2026-11-20T21:01:58.680Z — حزمة تطوير كبيرة: أداء التاريخ الطويل + سلامة Range/Replay
- **المستودع/الفروع:** `775878805Osamaha/TradeLab`، الفرع `feat/large-history-performance-replay-safety-20261120` مشتق من فرع التطوير `test/flutter-all-fixes-20261116` عند `3b2e1249bf2aa27ff615da42dff583cef54a723a`. لا مساس بـ `main` أو المشاريع الأخرى.
- **مسار 1 (cTrader):** `CTraderCandleStitcher.countNewFromVerifiedHistory` يتحقق من كل candle ضمن التداخل ببحث ثنائي في أرشيف مصدر معتمد مسبقًا، بدل مسح تاريخ كامل لكل تحديث دوري. يرفض OHLC المتناقض وإدخال شمعة داخل فجوة قديمة؛ مدخل `append` العام يظل يتحقق من كامل التاريخ غير الموثوق.
- **مسار 2 (واجهة الشارت):** `VerifiedClosedCandleRefresh.appendVerifiedAsync` يفحص نتيجة تحديث الشموع القصيرة مبكرًا؛ عند عدم وجود شمعة مغلقة جديدة لا يرسل 120k candle إلى worker ولا ينشئ مصفوفات وقت/سعر جديدة، ويترك الشارت الحالي ثابتًا. في حالة الشموع الجديدة يستمر البناء المتزامن على worker.
- **مسار 3 (Range BID):** `RangeTickRollforward.merge` يبدأ من أول tick يُحتفظ به ببحث ثنائي O(log N)، بدل المرور على 120k+ من تيكات ستة أيام التي خرجت من النافذة. لا تغيير في تكرار أحداث نفس الملي ثانية أو حد المليون tick.
- **مسار 4 (تحميل الأقدم):** `CTraderOlderCandlePager.load` يتحقق من OHLC والترتيب ومن عدم تجاوز cursor التاريخ الحصري. يظل count-back صالحًا لو عاد بتاريخ أقدم من lookback في عطلات السوق، بلا شموع وهمية.
- **مسار 5 (Replay):** `RangeBarTimeline.build` يرفض ترتيب BID المعكوس أو الوقت السلبي قبل نشر أي Range timeline؛ يقبل أحداث نفس الملي ثانية بنفس ترتيب المصدر، مع عدم تغيير تعريف الشموع المغلقة أو حد المستقبل.
- **ملفات المصدر المعدلة (5):** `flutter_app/lib/data/ctrader_candle_stitcher.dart` و`verified_market_history_snapshot.dart` و`range_tick_rollforward.dart` و`ctrader_older_candle_pager.dart` و`range_bar_timeline.dart`.
- **ملفات الاختبارات المعدلة (5):** `flutter_app/test/ctrader_candle_stitcher_test.dart` و`verified_market_history_snapshot_test.dart` و`range_tick_rollforward_test.dart` و`ctrader_older_candle_pager_test.dart` و`range_bar_timeline_test.dart`. تغطي أرشيف 120 ألف شمعة و120 ألف تيك، سلوك القراءة اللوغاريتمية، رفض التعارض والتاريخ الفاسد، وعدم إعادة النشر عند صفر شموع جديدة، وحماية Replay والملي ثانية المتساوية.
- **التحقق عند التوثيق:** نتائج GitHub Actions للدفعة **PENDING** قبل فتح PR؛ لا SDK Flutter محلي، Android Profile/FPS **NOT RUN**. لا APK أو Release جديد، والنسخة السابقة لا تتضمن هذه الدفعة.
- **الخطوة التالية الوحيدة:** افتح PR واحدًا نحو `test/flutter-all-fixes-20261116`، راجع CI تحليل Dart واختبارات Range/Replay/التاريخ؛ عند FAIL أصلح قبل الدمج، وعند PASS ادمج التطوير فقط ثم سجّل CI ورقم SHA الحقيقي.

### 2026-11-20T21:05:08.357Z — نجاح CI ودمج دفعة الأداء والأمان الكبيرة PR #568
- **النتيجة الفعلية:** [PR #568](https://github.com/775878805Osamaha/TradeLab/pull/568) **MERGED** في `test/flutter-all-fixes-20261116`، SHA الدمج [db9c2cf](https://github.com/775878805Osamaha/TradeLab/commit/db9c2cfa02bef9fea5f6f1a7f76e23140404e9b8)، بعد تحقق من فرع التطوير وقراءة ملف المصدر المدمج. ظل `main` عند `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` دون تغيير.
- **الاختبارات:** [GitHub Actions #44816709629](https://github.com/775878805Osamaha/TradeLab/actions/runs/44816709629) = **PASS/completed/success** على رأس PR `452d9b72b989356209caf5dfc5eeed013934da5a`؛ `Flutter analyze`، اختبارات التاريخ/Range/Replay المختارة (بما فيها الاختبارات الجديدة للملفات الخمسة)، واختبارات توقيت اليمن نجحت. لم تُجرَ جلسة Android Profile أو قياسات FPS على جهاز.
- **المخرجات:** 5 ملفات مصدر و5 ملفات اختبارات + ملفا التقارير. تسريع فحص تحديثات cTrader عند 120 ألف شمعة، إبقاء نفس snapshot عند عدم وصول بيانات جديدة، تجنب مسح 120 ألف تيك BID عند تدوير نافذة Range، رفض صفحات cTrader الأقدم غير المطابقة للـcursor، وعدم السماح بترتيب زمني عكسي في Range Replay، مع حفظ أحداث المللي ثانية المتساوية دون حذف.
- **ما لم يتغير:** لا بيانات وهمية، لا تنفيذ تداول حقيقي، لا تحميل APK جديد أو Release، لا تغيير `main` ولا مشاريع أخرى. آخر APK المنشور بتاريخ 2026-11-20 **لا يحتوي هذا الإصلاح**؛ للتجربة يلزم بناء جديد بطلب المستخدم.
- **الخطوة التالية الوحيدة:** اختبار حالة ذاكرة/تاريخ Range الطويل ومنع الانفجار غير المحدود لعدد شموع المدى عند قفزات BID موثقة، مع اختبارات ضغط ثم PR مستقل دون APK.

### 2026-11-20T21:07:36.754Z — حماية سقف ذاكرة Range عند التاريخ الضخم وإعادة بناء Replay
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، فرع `feat/range-replay-memory-budget-20261120` من `test/flutter-all-fixes-20261116` بعد دمج PR #568. `main` لم يتغير، لا APK جديد، لا تغييرات للمشاريع الأخرى.
- **التغيير (التنفيذ):** إضافة حد **1,000,000 تيك مصدر BID** وحد **250,000 شمعة Range مغلقة** لكل rebuilt timeline في `flutter_app/lib/data/range_bar_timeline.dart`. هذا سقف للذاكرة وليس ادعاءً بتحميل تاريخ cTrader بالكامل. يتم فحص العدد قبل نقل البيانات إلى isolates أو دمج صفحات أقدم، مع رفض صريح بدلاً من الانهيار أو نشر تاريخ مجتزأ. عند حدوث قفزات سعرية، ينهي البناء بأمان قبل نشر خط زمني جزئي على الشارت/Replay.
- **تكامل API:** `RangeBarTimeline.build`, `buildAsync`, `prependAndBuildAsync` تستخدم نفس حد الذاكرة؛ مع `closedBarLimit` اختياري للاختبارات والطلبات المقيدة ضمن سقف آمن. جميع المسارات تبقي ترتيب BID الحقيقي وأحداث المللي ثانية المتساوية دون اختراع شموع.
- **الاختبارات:** `flutter_app/test/range_bar_timeline_test.dart` — اختبار سقف الشموع عند الحد وبعده، تطبيق السقف على worker وprepend، ورفض ListBase مزيفة بعدد 1,000,001 مصدر دون قراءة عنصر أو تخصيص القائمة الكاملة، والتحقق من عدم تغيير مدخلات التاريخ.
- **الملفات:** `flutter_app/lib/data/range_bar_timeline.dart`, `flutter_app/test/range_bar_timeline_test.dart`, وملفا التسليم.
- **حالة التحقق:** `PENDING` حتى فتح PR ونجاح GitHub Actions. SDK Flutter محلي وAndroid Profile/FPS `NOT RUN`، ولا شيء من هذه الحزمة موجود في APK المنشور مسبقًا.
- **الخطوة التالية الوحيدة:** افتح PR إلى التطوير، حل أي فشل Dart/Flutter في CI، ثم دمج التطوير فقط وتسجيل SHA ونتيجة الفحص النهائية.

### 2026-11-20T21:11:34.056Z — نجاح اختبارات ودمج حماية سقف ذاكرة Range PR #569
- **المستودع/الدمج المؤكد:** `775878805Osamaha/TradeLab`، [PR #569](https://github.com/775878805Osamaha/TradeLab/pull/569) **MERGED** في `test/flutter-all-fixes-20261116`، SHA الحقيقي [b7ee472](https://github.com/775878805Osamaha/TradeLab/commit/b7ee47267bfd039c2705e07587fcca1de33ceab1). تمت مطابقة رأس فرع التطوير مع SHA الدمج. `main` لم يتغير وبقي عند `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`.
- **CI المعتمد:** [GitHub Actions #44817561584](https://github.com/775878805Osamaha/TradeLab/actions/runs/44817561584) = **PASS / completed / success** على رأس PR `2ee03468ef34eef540312acae0d0357fcc8f9341`؛ نجح تحليل Flutter واختبارات مصدر BID/Range/Replay وتوقيت اليمن. لا يُفهم من ذلك نجاح اختبار Android Profile على هاتف.
- **مخرجات ثانية بعد PR #568:** وضع سقف **1,000,000** تيك BID مصدر و**250,000** شمعة Range مغلقة في `RangeBarTimeline` عبر `build` و`buildAsync` و`prependAndBuildAsync`، ورفض صفحات مصدر أكبر من الميزانية قبل فحص/نسخ الملايين أو النقل إلى isolate، مع الامتناع عن نشر تاريخ Range جزئي عند تجاوز حد الشموع. اختبارات للمزامنة والخلفية وprepend والمصدر الضخم الاصطناعي (كحد اختباري لا بيانات سوق مزيفة).
- **الملفات:** `flutter_app/lib/data/range_bar_timeline.dart` و`flutter_app/test/range_bar_timeline_test.dart` و`docs/CHANGE_REPORTS.md` و`docs/HANDOFF.md`.
- **القيود:** لا APK ولا Release جديد؛ آخر APK المتاح سابق لدمج PR #568 وPR #569، وليس متضمنًا لهما. قياس FPS على جهاز Android واتصال cTrader الفعلي **NOT RUN**؛ لا تعديل في مشاريع أخرى.
- **الخطوة التالية الواحدة:** في دفعة العمل القادمة قياس أداء أحدث الشارت على Android Profile فعلي مع cTrader BID وRange أثناء pan/pinch/Replay، ثم معالجة أول اختناق مثبت وتوثيق النتيجة. إذا طلب المستخدم APK جديدًا، يُبنى من أحدث فرع تطوير مع فحص التوقيع.

### 2026-11-20T22:09:52.754Z — تحسين جذري لجدولة صفحات BID المقسمة وتحقيق المصدر
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، فرع الميزات `feat/ctrader-bid-adaptive-paging-20261121` من `570141ef3129ffb092a9b95a060a49ada4cb6ef4`. `main` ومشاريع المستخدم الأخرى دون تغيير. لا APK/Release.
- **المشكلة بالكود السابق:** بعد قسمة أول صفحة BID مشروطة `hasMore`، يواصل كل نصف التحميل بشكل متسلسل؛ قد ينتهي نصف سريع، ويظل عامل التحميل الثاني عاطلاً بينما صفحات عديدة تنتظر في النصف البطيء.
- **الإصلاح:** طابور متكيف محدود بعاملين عبر `Queue` و`Completer` يحتفظ بالعمّال حتى استكمال **كل** النوافذ، ويفصل كل نطاق زمني عند حد مللي ثانية شامل ودقيق. إعادة التجميع فقط بعد تحقق جميع الأوراق مع ترتيب النطاقات لا ترتيب الاستجابات؛ أحداث BID ذات timestamp متساوٍ تبقى بترتيبها.
- **الحماية:** سقف 4096 طلب مصدر، 100000 تيك/صفحة، ومليون تيك إجمالي؛ فشل أي صفحة يلغي نشر الناتج كله، رفض `hasMore` داخل مللي ثانية واحدة، رفض price/وقت خارج الحدود، والتحقق من `accountId` إذا كان موجودًا في استجابة cTrader.
- **الملفات:** `flutter_app/lib/data/market_api.dart`، `flutter_app/test/market_api_test.dart`، `docs/HANDOFF.md`، `docs/CHANGE_REPORTS.md`.
- **الاختبارات الإضافية:** 31 صفحة بتأخير متفاوت وإجابات تصل خارج الترتيب مع حد طلبين متزامنين؛ فشل ورقة مع سلامة بقية الأوراق، ورفض صفحة بعلامة حساب متعارضة. تغطي الاختبارات القائمة تقسيم الصفحات في حافة المللي ثانية، كثافة 6000 تيك، ورفض الأوقات الكسرية.
- **التحقق عند الحفظ:** GitHub Actions **PENDING** بعد فتح PR، Flutter SDK محلي وAndroid Profile **NOT RUN**، لا تدّعِ FPS محسنًا دون قياس.
- **الخطوة التالية الوحيدة:** PR واحد وCI، إصلاح أي إخفاق، دمج في فرع التطوير فقط بعد PASS وتسجيل SHA/CI، دون بناء APK.

### 2026-11-20T22:13:15.990Z — نجاح CI ودمج PR #570 لجدولة تحميل BID المتكيفة
- **GitHub:** [PR #570](https://github.com/775878805Osamaha/TradeLab/pull/570) **MERGED** إلى `test/flutter-all-fixes-20261116`، SHA الحقيقي [7f68458](https://github.com/775878805Osamaha/TradeLab/commit/7f68458a69e51817f2b396bb5bf74bdb41460d9d). تم التحقق من HEAD التطوير بعد الدمج، و`main` بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` بلا تغيير.
- **التحقق:** [Actions #44826685592](https://github.com/775878805Osamaha/TradeLab/actions/runs/44826685592) = **PASS / completed / success** على PR head `3f349dcafc272ceb44f82dab55a9ed17c906ca93`؛ Flutter analyze وكل فحوص BID/Range/Replay/timezone نجحت. Android physical/profile **NOT RUN**.
- **التنفيذ:** استبدال تقسيم cTrader BID الذي يبدأ بمسارين ثم يكمل كل منهما منفردًا بطابور عمل مستمر بعاملين، سقف 4096 طلب / 100 ألف تيك لكل صفحة / مليون إجمالي، والتحقق من accountId إذا أعاده gateway؛ عدم نشر صفحات ناقصة أو تغيير ترتيب أحداث بنفس المللي ثانية. 3 اختبارات حمل/فشل/مصدر.
- **الملفات:** `flutter_app/lib/data/market_api.dart` و`flutter_app/test/market_api_test.dart` و`docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`.
- **الحدود:** لا APK/Release جديد، لا تغييرات في التداول الحقيقي أو أسعار وهمية أو `main` أو مشاريع أخرى. ملف APK المنشور أقدم من #567–#570.
- **الخطوة التالية:** توحيد سقف التاريخ المحمل من SQLite مع الشارت على 200 ألف شمعة وقت، ومنع append تاريخ زائد قبل تخصيص المصفوفات، ثم إجراء CI ودمج التطوير فقط.

### 2026-11-20T22:15:58.010Z — توحيد حد تاريخ الشموع الزمنية بين SQLite وcTrader وReplay
- **المستودع والفرع:** `775878805Osamaha/TradeLab`، `feat/market-candle-200k-history-budget-20261121` عن التطوير عند `3bfd3e806202f682c32b7e8145a87a7e14086315`. لا تغيير `main` أو المشاريع الأخرى؛ لا APK/Release.
- **سبب الإصلاح:** القراءة الأولية ودمج الشموع من SQLite كانا يقصان التاريخ افتراضيًا عند **100,000** شمعة بينما cTrader refresh يسمح حتى **200,000**؛ قد تختفي أقدم شموع معتمدة بعد التنقل وإعادة تحميل الكاش.
- **التنفيذ:** مصدر ميزانية مشترك `MarketHistoryBudget.maxVisibleTimeCandles = 200000`، وإعادة استخدامه في `MarketCandleStore.read`/`mergeVerified` و`CTraderCandleStitcher` و`VerifiedMarketHistorySnapshot` و`OlderCandlePrepend`. يسمح بأكثر من 100k ويمنع تخصيص arrays غير محدودة، مع رسالة خطأ عند محاولة إضافة شمعة تفوق سقف 200k.
- **الفرق المهم:** البيانات الأقدم الموثقة يمكن أن تظل في أرشيف SQLite، والسقف للعرض المؤقت في الذاكرة فقط؛ لا يغيّر OHLC أو توقيت المصدر ولا يُنشئ شموعًا أو يكشف مستقبل Replay.
- **ملفات المصدر (5):** `flutter_app/lib/data/market_history_budget.dart`، `market_candle_store.dart`، `older_candle_prepend.dart`، `ctrader_candle_stitcher.dart`، `verified_market_history_snapshot.dart`.
- **الاختبارات (4):** `market_candle_store_test.dart` و`older_candle_prepend_test.dart` و`verified_market_history_snapshot_test.dart` و`market_history_budget_test.dart`؛ 120001 شمعة، منع تجاوز 200k، رفض الحدود غير الآمنة، والحفاظ على قائمة المصدر عند الصفحات المرفوضة.
- **حالة التحقق أثناء كتابة هذا التقرير:** CI **PENDING** حتى فتح PR، Flutter SDK محلي وAndroid Profile **NOT RUN**. لا ادعاء بتجاوز ذاكرة الهاتف أو تاريخ cTrader غير محدود.
- **الخطوة التالية الواحدة:** ارفع PR إلى فرع التطوير، نفذ GitHub Flutter/SQLite tests، أصلح FAIL، ثم ادمج ودوّن SHA وCI في هذا السجل.

### 2026-11-20T22:19:30.082Z — نجاح CI ودمج PR #571 لمواءمة 200k شمعة مصدرية في الذاكرة
- **المستودع/الدمج:** [PR #571](https://github.com/775878805Osamaha/TradeLab/pull/571) **MERGED** في `test/flutter-all-fixes-20261116`، SHA الفعلي [35444db](https://github.com/775878805Osamaha/TradeLab/commit/35444db050757d40561cd8f54525773709ed11c0). تم التحقق من رأس التطوير مباشرة بعد الدمج؛ `main` بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` دون تغيير.
- **الاختبارات:** [Actions #44827584931](https://github.com/775878805Osamaha/TradeLab/actions/runs/44827584931) = **PASS / completed / success** على رأس PR `5e325c9cbe164e4ae4e6b57a1bacdc594803b4b1`: `flutter analyze`، اختبارات تاريخ المصدر/SQLite/Range/Replay وتوقيت اليمن. لا قياسات FPS على هاتف فعلي.
- **التنفيذ الفعلي:** 5 ملفات source (ملف ميزانية جديد) و4 ملفات اختبار + 2 docs. عرض حتى 200k شمعة زمنية من SQLite بدل 100k؛ مشاركة سقف الذاكرة مع cTrader refresh وsnapshot وolder prepend؛ إيقاف المحاولة قبل تخصيص محاور/قائمة >200k دون تغيير البيانات المصدرية أو Replay.
- **قيود:** التاريخ الأقدم يمكن حفظه في أرشيف SQLite لكن غير محمّل كله في RAM في نفس الوقت؛ ما زال يلزم نظام عرض نوافذ لاحقًا للوصول لأكثر من 200k بلا توقف. لم يُنشأ APK/Release جديد، وآخر APK المتاح يسبق PR #567–#571؛ `main` والمشاريع الأخرى لم تُمس.
- **الخطوة التالية الواحدة:** اختبار تطبيق TradeLab على Android Profile مع بيانات cTrader BID الحقيقية وقياس p50/p95/p99، وإصلاح أية مشكلة تظهر ثم حفظ تقرير جديد.

### 2026-11-20T22:26:46.403Z — نافذة بدء الشارت + تاريخ شموع SQLite محلي على صفحات
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، `feat/local-first-candle-paging-20261121` من `908f42abb28c8d6e3dd9b5a7b6e7835972776c44`، دون تعديل `main` أو مشاريع أخرى، ودون APK/Release.
- **الأداء:** `ChartScreen._loadRealHistory` يبدأ بآخر 4000 شمعة زمنية مصدرية بدل استرجاع 200000 صف عند كل فتح للشارت. هذا تغيير في سياسة استهلاك الذاكرة وحجم SQLite query، وليس قياس زمن Android فعلي.
- **التاريخ الأقدم:** `MarketCandleStore.readOlder` يدعم strict `timestamp_ms < beforeMs`، ترتيب تنازلي في SQLite واسترجاع تصاعدي صالح للرسم، حد افتراضي 2000، وبنفس مفاتيح الرمز/الفريم/الحساب؛ لا إعادة تحميل صفحة المصدر المحفوظة من الإنترنت.
- **تكامل الشاشة:** بحث local-first عند السحب لليسار، ثم حصة broker authenticated فقط عند cache miss/invalid cache. تعطيل النشر عند تغير الحساب/الرمز أثناء الانتظار، استخدام نفس إعدادات Replay/drawing rebase، ومنع الطلبات الجديدة قبل تجاوز حد 200k نافذة RAM.
- **الاختبارات:** ثلاث حالات جديدة في `flutter_app/test/market_candle_store_test.dart`: 4200 مصدر مع فجوة أصلية والعودة إلى 4000+200، صفحات 600/600 منفصلة حسب الحساب، وحدود 200k وargs.
- **ملفات المصدر:** `flutter_app/lib/data/market_candle_store.dart`، `flutter_app/lib/screens/chart_screen.dart`. **التوثيق:** `docs/HANDOFF.md`، `docs/CHANGE_REPORTS.md`.
- **التحقق:** GitHub Actions **PENDING** عند هذه النقطة، Flutter SDK المحلي وAndroid Profile/FPS **NOT RUN**، ولا ادعاء بمطابقة TradingView الفعلية.
- **التالي:** افتح PR، راقب Flutter analyze وSQLite/Range/Replay، أصلح أي FAIL، ثم دمج إلى فرع التطوير فقط وتحديث SHA/CI الفعلي.

### 2026-11-20T22:30:50.872Z — CI فشل اختبار Replay بسبب سحب آلي يفعّل القصور: إصلاح محدد
- **الواقعة المثبتة:** [Actions #44829082109](https://github.com/775878805Osamaha/TradeLab/actions/runs/44829082109) = **FAIL**، تحليل Dart/Flutter **PASS**، و590 اختبارات **PASS** مقابل اختبار واحد **FAIL**: `replay_training_widget_test.dart` عند السطر 96، `pumpAndSettle timed out` بعد `tester.drag`. لا دمج على هذا الفشل.
- **تشخيص مصدر السلوك من الكود:** `chartShouldFling` يشغّل قصور الحركة عند |velocity| ≥ 180px/s ومسافة أفقية ≥14px. استخدام `tester.drag` بالسرعة الافتراضية في اختبار هدفه التأكد من repaint من دون إعادة بناء toolbar يمكن أن يبدأ animation طويلًا، ثم `pumpAndSettle` ينتظر انتهاء القصور لا اكتمال حركة الإصبع. لا يوجد دليل من السجل على فساد بيانات الوسيط أو فشل SQLite؛ لا ننسب الفشل إليها.
- **الإصلاح:** جعل الإيماءات الأربع المستخدمة لاختبار repaint بالذات `tester.timedDrag(..., Duration(milliseconds:500))`، بحيث سرعة 35–45px خلال 500ms أقل من عتبة fling. لا تعطيل لقصور حركة التطبيق ولا تغيير لكود الإنتاج. يحافظ الاختبار على تأكيد تحديث viewport/Replay overlay دون إعادة بناء الواجهات.
- **الفرع والملفات:** `775878805Osamaha/TradeLab`، `feat/local-first-candle-paging-20261121`؛ `flutter_app/test/replay_training_widget_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`. `main` وAPK غير متغيرين.
- **حالة التحقق بعد التصحيح:** CI للالتزام الجديد **PENDING** حتى انتهاء GitHub Actions؛ Android الحقيقي/قياس FPS **NOT RUN**. عند PASS يدمج إلى فرع التطوير، ثم يكتب SHA الدمج والاختبارات الفعلية؛ عند FAIL يتوقف الدمج ويصلح السبب المحدد.
- **الخطوة التالية الوحيدة:** تحقق من CI على رأس PR #572 المحدث ثم دمج التطوير فقط عند PASS.

### 2026-11-20T22:34:38.442Z — تفسير فشل CI الثاني وحماية Replay من جلب التاريخ غير المطلوب أثناء السحب
- **الفشل المؤكد:** [Actions #44829601262](https://github.com/775878805Osamaha/TradeLab/actions/runs/44829601262) = **FAIL**، رغم PASS لتحليل Flutter و590 اختبارًا. اختبار `replay_training_widget_test.dart` ما زال يتعطل عند `pumpAndSettle` (سطر 101 بعد تغيير `timedDrag`)؛ لذا **لم يدمج PR #572**. فشل المحاولة الأولى/الثانية محفوظ في السجل.
- **الخلل في مسار التطبيق وليس السرعة فقط:** فحص `ChartScreen._prefetchOlderAtEdge` كشف أنه يمكن استدعاء `_loadOlderHistory` تلقائيًا بمجرد السحب في Replay حتى إن لم يطلب المستخدم التاريخ الأقدم. وبعد إضافة SQLite local-first، هذا قد يبقي spinner/async متحركًا أثناء اختبار السحب ويمكّن تغيير فهرس شموع التدريب دون إجراء صريح.
- **الإصلاح في التطبيق:** منع التحميل التلقائي من الحافة عند `_replay || _replaySelectingStart`؛ **الأمر اليدوي `ReplayExtrasAction.loadOlder` باقٍ** للتحميل المقصود مع منطق إعادة تثبيت المؤشر الحالي. غير Replay يحتفظ بتحميل المصدر المحلي ثم الوسيط تلقائيًا كما كان.
- **اختبار انحدار مباشر:** `replay_training_widget_test.dart` يحتسب طلبات Binance /api/v3/klines ويتأكد أن سحب شارت Replay لا يصدر طلب مصدر إضافيًا، بالإضافة إلى تأكيد repaint وحدود العرض. استخدام `timedDrag` يستمر لأنه اختبار repaint لا اختبار fling.
- **الفرع والملفات:** `775878805Osamaha/TradeLab`، `feat/local-first-candle-paging-20261121`، `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/test/replay_training_widget_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`. لا APK ولا `main`.
- **التحقق الجديد:** CI **PENDING** على الالتزام الجديد؛ Android Profile **NOT RUN**. لن يُذكر PASS أو دمج إلا بعد التحقق الفعلي.
- **الخطوة التالية الواحدة:** راقب اختبار Replay/SQLite وCI بالكامل في PR #572 ثم دمج فرع التطوير فقط عند PASS.

### 2026-11-20T22:38:19.584Z — نجاح بوابة CI ودمج دفعة SQLite Local-first وReplay PR #572
- **النتيجة المعتمدة:** [PR #572](https://github.com/775878805Osamaha/TradeLab/pull/572) **MERGED** (squash) إلى `test/flutter-all-fixes-20261116`، SHA الفعلي [d746dea](https://github.com/775878805Osamaha/TradeLab/commit/d746dea22a7d11804ad5e19b56f5465a306f1c9d). جرى جلب حالة PR ورأس فرع التطوير والتحقق من مطابقتهما بعد الدمج.
- **فحص PR النهائي:** [GitHub Actions #44830135551](https://github.com/775878805Osamaha/TradeLab/actions/runs/44830135551) **PASS / completed / success**؛ خطوات `Analyze Dart and Flutter`, `Verify historical tick archive and chart interactions` (تتضمن اختبارات SQLite وReplay)، `Verify chart weekdays under Yemen device timezone` جميعها ناجحة. المحاولتان الأوليان **FAIL** مسجلتان في السجل بلا إخفاء.
- **الأثر:** 4000 شمعة محفوظة أوليًا بدل 200k، تحميل صفحات source-verified أقدم (2000) محليًا مع cursor حصري وفصل الحساب ثم الرجوع إلى broker عند الحاجة؛ ميزانية 200k تمنع تخصيص ذاكرة متجاوزة. السحب داخل Replay لا يفعّل تحميلًا تلقائيًا؛ لا يتغير سوق التداول ولا المصدر.
- **ملفات العمل:** `flutter_app/lib/data/market_candle_store.dart`, `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/test/market_candle_store_test.dart`, `flutter_app/test/replay_training_widget_test.dart`، `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`. لا تغيير `main` (بقي SHA `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`).
- **التحقق غير المنفذ:** Android device/Profile/FPS/Broker login **NOT RUN**؛ لا APK أو Release جديد. آخر APK منشور أقدم من هذه الدفعة ولا يحتوي #567–#572.
- **الخطوة التالية الواحدة:** جمع مؤشرات زمن التحميل/FPS في Android Profile وتكرار تجربة cTrader Range/Replay على هاتف حقيقي، ثم إصلاح أي اختناق مدعوم بقياس مع حفظ تقرير GitHub.

### 2026-11-20T22:43:51.849Z — إعداد قياس أداء تحميل الشارت ببيانات آمنة وبمراحل منفصلة
- **المستودع والفرع:** `775878805Osamaha/TradeLab`، `feat/tradelab-chart-load-profiler-20261121` من `400c24a20b67eda1824c0c594f1e96b29cde97a3`. `main` دون تغيير؛ لا APK/Release ولا تعديلات المشاريع الأخرى.
- **الإضافة:** `flutter_app/lib/chart/chart_load_profiler.dart` و`flutter_app/test/chart_load_profiler_test.dart`، ودمج نقاط القياس في `flutter_app/lib/screens/chart_screen.dart`: 12 مرحلة فعلية منفصلة بين cache read، cache snapshot، broker fetch، broker merge، Range startup، older SQLite/Broker، older append، Range older scan/rebuild، closed candle poll/merge. يُستخدم `Stopwatch` فقط عند وجود `TRADELAB_PROFILE_CHART=true` ويُطبع زمن حقيقي لكل عملية بعد إكمالها.
- **تحليلات الأداء:** `ChartLoadStatsCollector` يحتفظ بحد أقصى 40 عينة لكل مرحلة منفصلة، ويصدر p50/p95/p99 بعد كل 4 عمليات للمرحلة نفسها؛ لا تختلط فترات انتظار الإنترنت بأزمنة فك ترميز SQLite أو بناء Range.
- **الخصوصية والدقة:** السجلات تتضمن أسماء مراحل عامة ووضع الرسم وعدد الشموع/التيكات وقياسات ميكروثانية فقط؛ لا بيانات حساب cTrader أو رمز التداول أو السعر أو توقيت مصدر سوق أو أي رمز دخول. الأرقام لا تُدّعى موجودة حتى تشغيل جلسة Profile على Android فعلي.
- **الملفات:** `flutter_app/lib/chart/chart_load_profiler.dart`, `flutter_app/test/chart_load_profiler_test.dart`, `flutter_app/lib/screens/chart_screen.dart`، وملفا تسليم HANDOFF/CHANGE_REPORTS.
- **التحقق عند الحفظ:** `PENDING` لبوابة Flutter analyze واختبارات Range/Replay، Android Profile `NOT RUN`. لا تنشئ APK آليًا.
- **الخطوة التالية الوحيدة:** فتح PR إلى التطوير، إصلاح أي فشل CI حتى PASS، دمج التطوير فقط، وتوثيق SHA/رابط النتيجة.

### 2026-11-20T22:47:33.827Z — دمج PR #573 ونجاح جميع اختبارات قياس مراحل تحميل الشارت
- **المصدر/النتيجة:** [PR #573](https://github.com/775878805Osamaha/TradeLab/pull/573) **MERGED** في `test/flutter-all-fixes-20261116`، SHA الفعلي `5750837b87f2c6a974b2b3ebb480defaccff7dc2`. جرى التحقق من حالة PR ورأس الفرع بعد الدمج.
- **GitHub Actions:** [#44831381260](https://github.com/775878805Osamaha/TradeLab/actions/runs/44831381260) **PASS / completed / success** على رأس العمل `da05dbf6fae1699d39c51c8fb9177fffa2af434a`. نجاح Flutter analyze، التاريخ/Range/Replay والتوقيت.
- **ملفات:** `flutter_app/lib/chart/chart_load_profiler.dart`، `flutter_app/test/chart_load_profiler_test.dart`، `flutter_app/lib/screens/chart_screen.dart`، `docs/HANDOFF.md`، `docs/CHANGE_REPORTS.md`.
- **الأثر:** 12 نقطة Stopwatch حول تحميل وعزل مصدر الشموع وإعادة بنائها؛ تسجيل آمن للأعداد والمدد فقط عند تفعيل `TRADELAB_PROFILE_CHART`. رسائل metrics مع p50/p95/p99 بعد 4 عمليات لكل مرحلة. تم التحقق باختبارات وحدات لكن **لم يتم قياس أي زمن Android حقيقي أو FPS على هاتف**.
- **قيود:** `main` بقي SHA `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`، لا APK أو Release جديد، لا مساس بمشاريع أخرى.
- **الخطوة التالية الوحيدة:** إضافة حارس اتصال صفحات SQLite القديمة لمنع تجاوز تاريخ لم يثبت اكتمال كاشه، اختباره ثم دمجه إلى التطوير فقط.

### 2026-11-20T22:50:48.862Z — حماية اتصال صفحات SQLite وفصل مؤشرات زمن Range عن الشموع العادية
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، `fix/tradelab-sqlite-history-seam-20261121` مشتق من فرع التطوير `a6a96d4e2c750c4ba8210ce9e1101bd9d1bb048d`، دون تغيير `main` أو التطبيقات الأخرى، ودون بناء APK/Release.
- **المشكلة المصدرية:** استرجاع `readOlder` يثبت سلامة OHLC للشموع الموجودة فقط، وليس اكتمال الفترات بين جزيرتين في ذاكرة SQLite. يمكن اختيار جزيرة أقدم مباشرة وتفويت اتصال تاريخي لم يُحمَّل أصلاً من cTrader/Binance. هذه ثغرة في استدلال الكاش موثقة من الكود وليست تأكيدًا بأن بيانات حساب المستخدم تأثرت.
- **الإصلاح 1:** `MarketCandleStore.contiguousOlderPage` يقيّد صفحة الكاش بآخر تسلسل source-verified متصل بخطوة فتح الإطار المطلوبة ومتصل مباشرة بـ`beforeMs`، دون نسخ عند اتصال الصفحة كاملة. أي فجوة محلية مجهولة أو أطوال أشهر متغيرة تنقل طلب أقدم إلى مصدر الوسيط الأصلي، بدلاً من القفز على تاريخ قد يضم شموعًا حقيقية. لا حذف SQLite ولا تعبئة شموع وهمية.
- **الإصلاح 2:** `ChartTimeframeCatalog.fixedOpenStepMs` يقدم خطوات فتح المصدر الإسمية للإطارات الثابتة، ولا يفترض طولًا ثابتًا لـ1M. كل فجوة عطلة سوق لا تُستنتج صحتها من SQLite وحده.
- **الإصلاح 3:** `ChartLoadStatsCollector` يفصل النوافذ الدورية بزوج `(ChartLoadPhase, chartMode)` بدل phase فقط، لكيلا تختلط p95/p99 لRange والشموع الزمنية.
- **الملفات:** `flutter_app/lib/data/chart_timeframe_catalog.dart`, `flutter_app/test/chart_timeframe_catalog_test.dart`, `flutter_app/lib/data/market_candle_store.dart`, `flutter_app/test/market_candle_store_test.dart`, `flutter_app/lib/chart/chart_load_profiler.dart`, `flutter_app/test/chart_load_profiler_test.dart`, `flutter_app/lib/screens/chart_screen.dart`، وملفا التوثيق.
- **الاختبارات:** منع القفز عبر gap بين جزيرتي كاش، اتصال 2000 شمعة دون نسخ، عطلات السوق/التقويم الشهري، رفض الترتيب الخاطئ، وفصل أرقام p95 لكل نوع شموع.
- **التحقق:** `PENDING` حتى PR وGitHub Actions، Android Profile/FPS/الوسيط الفعلي `NOT RUN`. هذه بيانات اختبار محلية فقط وليست أسعارًا منشورة.
- **الخطوة التالية الوحيدة:** PR وFlutter analyze واختبارات history/SQLite/Range/Replay، وإصلاح أي FAIL قبل الدمج إلى التطوير، ثم تحديث SHA/CI النهائي.

### 2026-11-20T22:53:57.778Z — نجاح CI ودمج PR #574 لتوصيل صفحات SQLite دون تجاوز تاريخ غير مؤكد
- **GitHub:** [PR #574](https://github.com/775878805Osamaha/TradeLab/pull/574) **MERGED** إلى `test/flutter-all-fixes-20261116`، SHA فعلي [32ae4f83](https://github.com/775878805Osamaha/TradeLab/commit/32ae4f83fc47f8541a70b756b508fc39d23c9939). تحقق من نتيجة PR ورأس فرع التطوير بعد الدمج.
- **CI:** [Actions #44832321863](https://github.com/775878805Osamaha/TradeLab/actions/runs/44832321863) = **PASS/completed/success** على مصدر PR `de231c5d91054fd71295ee9a59d9a915f2384edb`: Flutter analyze واختبارات التاريخ وSQLite والشارت وRange/Replay والتوقيت اليمني نجحت.
- **التنفيذ:** حماية source-contiguous لسلسلة الشموع المحلية قبل older prepend، fallback إلى مصدر الوسيط عند gap غير مؤكدة، خطوات زمن صحيحة للإطارات الأصلية، لا تخمين طول أشهر المصدر، وحفاظ على هوية القائمة الأصلية لصفحة متصلة 2000 شمعة. فصل `ChartLoadStatsCollector` بالمرحلة ووضع الرسم؛ اختبار عزل p95.
- **المصدر/الاختبار:** `flutter_app/lib/data/chart_timeframe_catalog.dart`, `flutter_app/test/chart_timeframe_catalog_test.dart`, `flutter_app/lib/data/market_candle_store.dart`, `flutter_app/test/market_candle_store_test.dart`, `flutter_app/lib/chart/chart_load_profiler.dart`, `flutter_app/test/chart_load_profiler_test.dart`, `flutter_app/lib/screens/chart_screen.dart`. ملفات التسليم: `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`.
- **القيود:** لم يتغير `main` (بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`) ولا أي مشروع آخر. لا APK أو Release. Android Profile/FPS واختبار حقيقي مع حساب cTrader `NOT RUN`، ولا يدّعي تقرير CI تحسنًا مقاسًا للهاتف.
- **الخطوة التالية الوحيدة:** اختبار Android Profile للشارت وBID Range وتحليل سجل التحميل والـframe p95 الجديد، ثم تنفيذ إصلاح موجّه بمؤشرات فعلية؛ لا APK قبل تصريح المستخدم.

### 2026-11-20T22:58:23.167Z — حماية منتقي Replay من الحساب/المصدر القديم وتسريع بحث 200 ألف توقيت
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، `feat/tradelab-replay-safe-fast-timeline-20261121` عن فرع التطوير `36a1f3de805b3dd658e320c7e65a6886890fc82f`. لا تعديلات `main` أو باقي المشاريع؛ لا APK/Release.
- **المشكلة الأولى بالكود:** `ReplayStartResolver.hasVerifiedTimes` يمسح كل timestamps عند الدخول والتأكيد والاختيار من التقويم؛ `atOrBefore` يستخدم فحص كامل O(200k) قبل البحث الثنائي، حتى لو تحقق الشارت بالفعل من نفس snapshot.
- **الإصلاح:** `ReplayVerifiedTimeIndex` يعيد استعمال التحقق على نفس مصدر timestamps/عدد الشموع الموثقة، ويجعل البحث التالي `O(log N)` والتأكيد `O(1)`. يتجدد التحقق عند تغير هوية snapshot أو عدد الشموع، ولا يغير static resolver للجهات غير الموثوقة. يدعم تواريخ Range متساوية UTC ولا يكشف آخر شمعة مستقبلية عند بدء Replay.
- **المشكلة الثانية بالكود:** اختيار تاريخ Replay يستخدم `timestamps` أُخذ قبل `showDatePicker` و`showTimePicker` وDialog التوقيت الصيفي؛ إذا تغير الحساب/الرمز/المزود/المنطقة الزمنية أثناء بقاء النافذة يمكن استخدام فهرس من الرسم القديم على الرسم الحالي.
- **الإصلاح:** `ReplayDateSelectionGuard` يتحقق من هوية قائمة مصدر التوقيت، `_loadRevision`، العدد، الحساب/الرمز/الفريم/المزود/المنطقة الزمنية ووضع تحديد البداية بعد كل `await`. يتوقف دون تغيير اختيار المستخدم أو Replay عند فقد صلاحية المصدر. كما يضبط candidate index داخل حدود المصدر.
- **الملفات:** `flutter_app/lib/replay/replay_start_resolver.dart`, `flutter_app/test/replay_start_resolver_test.dart`, `flutter_app/lib/screens/chart_screen.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **التغطية:** 200k توقيت مع `ListBase` لحساب قراءات مصدر 180 عملية بحث، تغيّر snapshots/عداد الشموع، Range نفس المللي ثانية، مصدر غير مرتب، الإبطال لكل بُعد من منتقي الوقت. ليست بيانات تداول حقيقية، ولا تغيير مصدر أو سعر.
- **التحقق حتى الآن:** CI `PENDING`، اختبار Android Profile وفريمات الهاتف الحقيقي `NOT RUN`. حالة PR ستُسجل بعد فتحه. لا إنشاء APK.
- **الخطوة التالية الوحيدة:** افتح PR إلى `test/flutter-all-fixes-20261116`، تأكد من نجاح CI والاختبارات، أصلح أي فشل، ثم دمج فرع التطوير فقط وتحديث SHA/CI الفعلي.

### 2026-11-20T23:01:53.828Z — نجاح اختبار ودمج #575 لتحسين اختيار توقيت Replay وإبطال نوافذ المصدر القديم
- **GitHub:** [PR #575](https://github.com/775878805Osamaha/TradeLab/pull/575) **MERGED** في فرع `test/flutter-all-fixes-20261116`، SHA الفعلي `e7ffbd80db2add402cc16b89a7ef60576a7b6887`. تم التحقق من حالة PR ورأس فرع التطوير.
- **CI:** [Actions #44833280061](https://github.com/775878805Osamaha/TradeLab/actions/runs/44833280061) = **completed/success** على مصدر PR `6ea07bfbbe5c8cf530edb3f70ca9ae5a483f38f5`؛ نجح `flutter analyze` وفحص الشارت/Range/Replay وتوقيت اليمن.
- **الملفات:** `flutter_app/lib/replay/replay_start_resolver.dart`، `flutter_app/test/replay_start_resolver_test.dart`، `flutter_app/lib/screens/chart_screen.dart`، `docs/HANDOFF.md`، `docs/CHANGE_REPORTS.md`.
- **الأثر:** اختيار تاريخ Replay يتعامل مع snapshot مُتحقق منه مع بحث ثنائي متكرر O(log N)؛ اختيار التاريخ/الوقت/DST الذي يبقى مفتوحًا أثناء انتقال الحساب/المصدر لا يحرك مؤشر أو شمعات الجلسة الجديدة. تدعم الاختبارات تسلسل 200k ومختلف أسباب إبطال الجلسة؛ لا كشف أسعار مستقبلية ولا تغيير بيانات السوق.
- **الحدود:** `main` دون تغيير SHA `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`، لا APK، لا تحديث مشاريع أخرى، لا تجربة Android Profile أو حساب cTrader الحقيقي. لم تُقَس p95/p99 لأداء الهاتف.
- **الخطوة التالية الوحيدة:** تحسين محاكاة صفقات Replay عند القفز بين عشرات آلاف الشموع مع اختبارات توقف/هدف/إعادة تقديم، دون الاعتماد على بيانات مستقبلية.

### 2026-11-20T23:06:12.934Z — تسريع معالجة وقف/هدف الصفقات التدريبية في Replay للقفزات التاريخية الطويلة
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، `feat/tradelab-replay-large-seek-exit-index-20261121` من فرع التطوير `f696e3feba13e74bc468332b1ce7e93afa996a68`. لا تغير `main`، ولا APK/Release أو مشاريع أخرى.
- **الثغرة الأدائية في الكود:** `ReplayTrainingSession.moveTo` يفحص **كل شمعة جديدة × كل صفقة SL/TP مفتوحة**؛ عند تخطي 100 ألف شمعة ومجموعة صفقات تدريب كثيرة تصبح الحلقة O(B*T) على واجهة Flutter وقد تتسبب بتأخر واجهة Replay. لا نقول إن هذه المشكلة قيس أثرها فعليًا على هاتف المستخدم.
- **التحسين:** `ReplayRevealedExitIndex` يستخدم `Float64List` لحدّين دقيقين minLow/maxHigh في شجرة ثنائية، لا يقرأ/يفهرس **أي شمعة غير مكشوفة**، ويبحث عن أول bar مطابقة لكل صفقة. الحد 250001 شمعة يشمل الحد المسموح من Range وواحدة متكوّنة غير منفذة. بعد إنشاء الشجرة، البحث O(log N) لكل صفقة؛ وتمديد الشموع الجديدة محدود وفقًا لطول المصدر.
- **تكامل التدريب:** مسار سريع فقط للقفزات 2048+ شمعة، 8+ صفقات مراقبة، 100k+ من عمليات المقارنة التقريبية؛ حالة Playback العادية تُبقي الحلقة الصغيرة دون شجرة كبيرة. السياسة السعرية نفسها في المسارين (لا استخدام high/low شمعة الدخول، وقف أولًا عند تحقق الشرطين، stop gap عند افتتاح أكثر سلبية)، ولا تداول حقيقي. إبطال الفهرس عند rewind/prepend/clear وتبدّل مصدر الشموع.
- **الملفات:** `flutter_app/lib/replay/replay_revealed_exit_index.dart` (جديد)، `flutter_app/test/replay_revealed_exit_index_test.dart` (جديد)، `flutter_app/lib/replay/replay_training_session.dart`, `flutter_app/test/replay_training_session_test.dart`، وملفا التوثيق.
- **الاختبارات الجديدة:** منع الوصول إلى أي شمعة مستقبلية بـListBase محروس مع 100k مصدر، بحث وقف/هدف عند أول bar، تمديد الفهرس دون إعادة قراءة المصدر المكشوف، رفض ميزانية ذاكرة أكبر من Range، 24 صفقة ضمن تخطّي 120k شمعة مع stop-first/adverse open وإعادة تشغيل بعد rewind، وحظر تأثر الصفقة بمدى شمعة دخولها نفسها.
- **التحقق الحالي:** CI `PENDING` بعد إنشاء PR، Android Profile وفحص cTrader الفعلي `NOT RUN`. لا ادّعاء بتحسن FPS مقاس.
- **الخطوة التالية الوحيدة:** إنشاء PR، النجاح في CI بما يشمل اختبارات Replay/SQLite/Range/التوقيت، دمج التطوير فقط وتسجيل SHA/الرابط؛ حل الفشل قبل الدمج إن ظهر.

### 2026-11-20T23:09:33.016Z — نجاح CI ودمج PR #576: فهرسة وقف/هدف Replay للقفزات بين 120 ألف شمعة
- **التنفيذ والدمج:** [PR #576](https://github.com/775878805Osamaha/TradeLab/pull/576) **MERGED** (squash) إلى `test/flutter-all-fixes-20261116`، SHA الفعلي [84e9c5c3](https://github.com/775878805Osamaha/TradeLab/commit/84e9c5c3eb038b2cca30427101af8f95149f3851). تحققت من حالة PR ورأس فرع التطوير بعد الدمج.
- **الاختبارات الفعلية:** [GitHub Actions #44834326339](https://github.com/775878805Osamaha/TradeLab/actions/runs/44834326339) **completed / success** على PR HEAD `a21a116b51c68f2f08e6b786645bf6efe5788d82`؛ نجاح Dart/Flutter analyze واختبارات التاريخ والشارت وReplay/Range وتوقيت اليمن.
- **التغيير:** تحويل قفز Replay الكبير مع صفقات متعدّدة مراقبة إلى `ReplayRevealedExitIndex` ببنية Float64 min/max تطلع على الشموع *المكشوفة فقط*، وتعيد أول bar ذات SL/TP بشكل منفصل لكل صفقة. لا تغيير تعبئة أو اتجاه السعر أو P&L؛ stop أولًا، adverse-gap عند سعر فتح أسوأ، عدم تنفيذ على شمعة الدخول. يبقى المسار التسلسلي للحركة العادية بلا إنشاء index.
- **ملفات المصدر:** `flutter_app/lib/replay/replay_revealed_exit_index.dart`, `flutter_app/lib/replay/replay_training_session.dart`. **الاختبارات:** `flutter_app/test/replay_revealed_exit_index_test.dart`, `flutter_app/test/replay_training_session_test.dart`. وملفا `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **الاختبارات الإضافية:** 100 ألف شمعة بواجهة `ListBase` تمنع حتى قراءة شمعة بعد cutoff، 120 ألف شمعة و24 صفقة مع SL+TP وgap/rewind، قفزة 25 ألف شمعة واختبار short entry، منع تجاوز 250001 source bars. لا تحميل أسعار وهمية للتطبيق؛ الاختبارات تستخدم fixtures محلية فقط.
- **القيود:** لا تطبيق على `main` (بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`)، لا APK أو Release جديد، لا مشاريع أخرى، واختبار Android Profile/قياس FPS/حساب cTrader الحقيقي `NOT RUN`.
- **الخطوة التالية الواحدة:** تشغيل جلسة Android Profile لقياس p50/p95/p99 مع شارت Range و120k وReplay على هاتف، ثم معالجة أول اختناق موثق؛ لا إنشاء APK دون إذن.

### 2026-11-20T23:12:32.362Z — قص خطوط الصفقات التدريبية الطويلة داخل شاشة Replay بدل آلاف الشرطات المخفية
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، `fix/tradelab-replay-overlay-visible-dashes-20261121` عن التطوير `e4124586310bd881588f04520c4aafdd4bbcdf3c`. لا تعديل `main` أو المشاريع الأخرى، لا APK/Release.
- **المشكلة من الكود المراجع:** `ReplayTradeOverlayPainter._dashed` يرسم SL وTP بحلقة `for x = left; x < right; x += 12` دون الاقتصار على viewport؛ دخول صفقة قبل 200 ألف شمعة عند 10px للشمعة يمكن أن يعني ~166,000 شرطة لكل خط رغم `canvas.clipRect`. حلقة Dart نفسها باقية حتى لو أخفى Skia ناتج الرسم.
- **التحسين:** دالة pure `ReplayTradeOverlayLayout.visibleDashSegments` تحسب أول dash يمكن أن يدخل شاشة الهاتف مباشرة باستخدام حساب صحيح لطور الشرطات الأصلي وتنتج فقط الجزء داخل `0..plotWidth`. `visibleStroke` يقيّد امتداد الخطوط المتصلة للسعر، و`ReplayTradeOverlayPainter` يتجنب رسم العلامات خارج المنطقة المرئية وبيانات الإحداثيات غير النهائية.
- **سلامة السوق:** الأسعار وأزمنة الوسيط وشموع المصدر وReplay cutoff والتدريب الورقي ثابتة؛ تغيير رسم/رستر فقط. لا استنتاج Candle جديد ولا رسم أسعار مستقبلية.
- **الملفات:** `flutter_app/lib/replay/replay_trade_overlay.dart`, `flutter_app/test/replay_trade_overlay_test.dart`، `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **اختبارات انحدار:** O(plotWidth) مع امتداد -2 مليون بكسل، الحفاظ على phase عند القص، خطوط offscreen/NaN، ورسم widget مع Position عبر 200 ألف شمعة، دون تغيير الصفقات.
- **التحقق:** GitHub CI `PENDING` قبل فتح PR؛ Android FPS / Profile `NOT RUN`. لا ادعاء بقياس FPS حقيقي.
- **الخطوة التالية:** PR وCI، إصلاح FAIL، دمج التطوير فقط بعد PASS وتسجيل SHA/رابط الاختبار.

### 2026-11-20T23:15:59.980Z — دمج PR #577 بعد نجاح اختبارات حدود رسم الصفقات الطويلة
- **العمل والدمج:** [PR #577](https://github.com/775878805Osamaha/TradeLab/pull/577) **MERGED** (squash) في `test/flutter-all-fixes-20261116`، SHA فعلي [98db797](https://github.com/775878805Osamaha/TradeLab/commit/98db797faf2bb98941734ea77b9228571d08e159).
- **CI:** [GitHub Actions #44835136904](https://github.com/775878805Osamaha/TradeLab/actions/runs/44835136904) **completed/success** على `be9fce0caa2f2fcd5bb2726362312b554d73dcb0`، مع تحليل Flutter واختبارات chart/Replay/Range/tz اليمن.
- **المصدر:** `flutter_app/lib/replay/replay_trade_overlay.dart`؛ الرسم المتقطع للـSL/TP الآن O(عرض شاشة Android) لا O(طول الصفقة التاريخية)، مع طور dashed أصلي وإحداثيات price scale صحيحة؛ خط الدخول المتصل وقص العلامات يتبع viewport فقط. **الاختبارات:** `flutter_app/test/replay_trade_overlay_test.dart` على -2m pixels و200k-bar replay، مع عدم تغيير التداول التدريبي.
- **التوثيق:** `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`؛ التغيير الحقيقي اكتمل وحُفظ على GitHub.
- **الحدود:** `main` بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`؛ لا APK/Release ولا مشاريع أخرى. Android FPS/Profile أو حساب cTrader الحقيقي `NOT RUN`.
- **الخطوة التالية الوحيدة:** تطوير تحديث شموع Range من تيكات BID الجديدة الموثقة في cTrader، وليس من اقتباس السعر وحده، مع الحفاظ على التوقيت والتسجيل الآمن.

### 2026-11-20T23:21:05.849Z — تنفيذ تحديث شموع Range الحية من cTrader BID أصلي دون إعادة بناء التاريخ الطويل
- **المستودع والفرع:** `775878805Osamaha/TradeLab`، `feat/tradelab-verified-live-range-20261121` من `70ea5371d2dd8625f36d78d7ae7c6795c056da8a`. `main` دون تغيير، لا APK أو Release ولا مشاريع أخرى.
- **الخلل الوظيفي في الشارت:** كانت أسعار BID/ASK الحية تعيد رسم السعر فقط، دون إضافة تيكات BID المؤرّخة إلى شموع Range؛ التغيير الحالي يضيف مصدر تحديث تيكات فعلي ولا يستخدم quote كنقطة مزيفة.
- **التحقق من تداخل المصدر:** `RangeLiveBidDelta.verifiedSuffixAsync` يفحص صفحة cTrader الموقعة ضمن الفترة [lastTimestamp,now]؛ يطابق **جميع الأحداث القديمة من المللي ثانية الأخيرة بالترتيب والقيمة والعدد** ويعيد اللاحق فقط بما فيه أحداث أخرى بنفس المللي ثانية. صفحة ناقصة أو مصدر تغيّر/تكرر بشكل غير متوافق يفشل ولا يُنشر تاريخ خاطئ. صفحات >5000 تُفحص على worker.
- **بناء Range:** `RangeBarBuilder.resumeFromVerifiedForming` يستعيد حالة الشمعة Range المتكوّنة من مصدر موثوق؛ `RangeBarTimeline.appendVerifiedSuffixAsync` لا يمر على كل التيكات القديمة، يحافظ على الشموع المغلقة ومؤشرات أحداث BID الأصلية، ويبني فقط الزيادة مع نشر لقطة `RangeLiveAppendBuildResult` متطابقة. يعزل البناء الكبير على worker ويحافظ على حدود 1m tick/250k closed bars.
- **تكامل الإنتاج:** `ChartScreen._refreshLiveRange` عند timer 30 ثانية للحساب/الرمز/المقاس الصحيح فقط، دون Replay أو تحديث خلال جلب تاريخ قديم/ملء آلي، ويتحقق من `revision` وهوية قائمة التيكات والـtimeline بعد كل await. يُحدث `_rangeHistoryTicks`, `_actualRange`, `_rangeBarEndTickIndices`, `_rangeBarTimestamps` **ذريًا في setState** ويثبت محور الزمن أثناء إضافة الشموع المغلقة. لا اتصال باسم مستخدم/حساب آخر ولا بيانات مستقبلية.
- **القياس:** `ChartLoadPhase.liveRangeUpdate` يضيف توقيتًا اختياريًا دون سعر أو حساب وفق نظام Android Profile الموجود. لا ادعاء بنتائج موبايل واقعية الآن.
- **المصدر:** `flutter_app/lib/data/range_live_bid_delta.dart`, `range_bar_builder.dart`, `range_bar_timeline.dart`, `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/lib/chart/chart_load_profiler.dart`.
- **الاختبارات:** `flutter_app/test/range_live_bid_delta_test.dart`, `range_bar_builder_test.dart`, `range_bar_timeline_test.dart`: ترتيب وتطابق BID بنفس المللي ثانية، page failure، حجم 6500 تيك وworker، تطابق rebuild الكامل بعد 6200 تيك، حفظ cutoff Replay، عدم تغيير snapshot القديم والـhard budgets.
- **التحقق عند الحفظ:** GitHub Actions `PENDING` حتى PR، Android Profile وcTrader broker live `NOT RUN`. لا أسواق مختلقة أو تداول حقيقي، لا APK.
- **الخطوة التالية الوحيدة:** إنشاء PR والتأكد من PASS في Flutter analyze/Range/Replay ثم الدمج في التطوير مع SHA ورابط CI، وإصلاح أي FAIL قبل الدمج.

### 2026-11-20T23:23:14.349Z — إصلاح فشل CI #44836213938 وتوسيع بوابة اختبارات Range/Replay
- **فشل موثق:** [GitHub Actions #44836213938](https://github.com/775878805Osamaha/TradeLab/actions/runs/44836213938) **FAIL/completed/failure** في `flutter analyze --no-fatal-infos`: `test/range_bar_builder_test.dart:27` و`test/range_bar_timeline_test.dart:179` تستخدمان `TradeCandle` من دون استيراد `data/tradelab_data.dart`. **لم يحدث دمج للفرع الفاشل**.
- **الإصلاح:** إضافة الاستيراد الصريح في الاختبارين دون تعديل كود الحسابات أو source BID؛ ثم توسيع `.github/workflows/verify-flutter-range.yml` ليشمل `range_live_bid_delta_test.dart` و`replay_revealed_exit_index_test.dart` و`chart_load_profiler_test.dart` و`range_bar_validation_test.dart` و`market_history_budget_test.dart` و`candle_prefix_test.dart`. كانت بعض الاختبارات السابقة موجودة بالكود لكنها لم تكن ضمن القائمة الثابتة لعمل CI؛ لا ندّعي أنها اجتازت تشغيلًا لم يشملها.
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، `feat/tradelab-verified-live-range-20261121` على PR #578؛ `main` دون تعديل، لا APK/Release. **التحقق حاليًا: PENDING** حتى فحص commit المصحح.
- **الخطوة التالية الوحيدة:** مراقبة فحص GitHub Actions الجديد للملفات الستة، إصلاح أي فشل، ثم دمج PR #578 إلى التطوير عند PASS.

### 2026-11-20T23:26:35.887Z — نجاح فحص CI الموسع ودمج PR #578 لتحديث Range الحي
- **نتيجة GitHub:** [PR #578](https://github.com/775878805Osamaha/TradeLab/pull/578) **MERGED/squash** إلى `test/flutter-all-fixes-20261116`؛ SHA المدمج الفعلي `754f500bd7dde18d92764dc74b928d5ea765d6e4` (تحققنا من PR ورأس التطوير).
- **الاختبارات:** [Actions #44836462583](https://github.com/775878805Osamaha/TradeLab/actions/runs/44836462583) **completed/success** على `a60d886f7037c2874685a8b1d3ccbf8dd808d561`: flutter analyze، اختبارات Range/Replay/Chart وتوقيت اليمن، **بما فيها 6 ملفات اختبار جديدة إلى workflow**. لم نتجاهل الفشل السابق: [#44836213938](https://github.com/775878805Osamaha/TradeLab/actions/runs/44836213938) **FAIL** (2 imports `TradeCandle`) وصُحح قبل الدمج.
- **الكود:** `flutter_app/lib/data/range_live_bid_delta.dart`, `range_bar_builder.dart`, `range_bar_timeline.dart`, `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/lib/chart/chart_load_profiler.dart`. اختبارات `flutter_app/test/range_live_bid_delta_test.dart`, `range_bar_builder_test.dart`, `range_bar_timeline_test.dart`. تعديل بوابة الاختبارات `.github/workflows/verify-flutter-range.yml` وملفا التسليم.
- **التنفيذ الفعلي:** BID حقيقي مصدره cTrader، فحص مصدر live inclusive لنفس المللي ثانية، ردّ أي نقص أو اختلاف، تحديث الشمعة Range المتكوّنة والشموع المغلقة الجديدة تدريجيًا، snapshot ذرية وشروط حماية revision والحساب والرمز، تعطيل التحديث أثناء Replay. لا صفقات حقيقية أو أسعار مخترعة، ولا تجاوز ميزانية مليون BID/250k Range مغلقة.
- **القيود:** `main` غير مُعدل `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`. لا APK/Release ولا مشاريع أخرى. Android Profile/اختبار حساب وسيط حي/قياس FPS `NOT RUN`؛ لا ادّعاء ببيانات تداول فعلية في بيئة CI.
- **الخطوة التالية الواحدة:** تحقق من تحديث live Range على جهاز Android وحساب cTrader حقيقي وجمع أدلة/قياسات، ثم علاج أي اختلاف موثق دون تغيير `main`.

### 2026-11-21T00:32:19.881Z — تخفيف نقل تاريخ BID المليون تيك في عامل تحقق تحديث Range الحي
- **المستودع/الفرع:** `775878805Osamaha/TradeLab` → `perf/tradelab-live-bid-boundary-only-20261121`، من تطوير `c2534af76b39f76bc8aa2962cd2c8cd9088c96af`. لا تعديل لفرع `main`، لا APK أو Release، ولا أي مشروع آخر.
- **المشكلة المؤكدة من المصدر:** `RangeLiveBidDelta.verifiedSuffixAsync` مع صفحة cTrader من 5000+ أحداث تنقل record مكونًا من `(previouslyVerified, brokerPage, lastTimestamp)` إلى `compute`، وتحتفظ `previouslyVerified` حتى مليون تيك. بينما `_verifiedLiveSuffixWorker` يفحص فقط ذيل الأحداث التي تشترك في آخر مللي ثانية. هذا عمل/نقل ذاكرة زائد عند كل فترة تحديث وليس اختبار FPS مقاسًا على جهاز.
- **الإصلاح:** استخراج `RangeLiveBidBoundary.fromVerified` ببحث ثنائي من دون نسخ الأرشيف، مع قائمة immutable لأحداث المللي ثانية الأخيرة فقط؛ worker يقارن `(boundary.events, brokerPage, boundaryMs)`. لا فقد للأحداث المتطابقة ولا ترتيب مصطنع؛ فشل مغلق عند أي تعارض، ورفض تاريخ أكبر من مليون تيك قبل الوصول إلى مصدره.
- **الاختبارات:** `_MillionBidHistory` يحاكي مليون BID عبر `ListBase`؛ يثبت أقل من 50 قراءة لحصر مللي ثانية المصدر وإجراء polling بصفحة 6500 تيك، ويحافظ على أحداث مشتركة متكررة. `_OversizedBidHistory` يرفض طول مليون+1 دون طلب أي عنصر. اختبار نقص تيك أو تغير ترتيبه يفشل.
- **الملفات:** `flutter_app/lib/data/range_live_bid_delta.dart`, `flutter_app/test/range_live_bid_delta_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **التحقق الحالي:** CI `PENDING` حتى PR. لا اختبارات Android Profile/FPS أو حساب cTrader حقيقي؛ التحسين نظري في تكلفة نسخ الذاكرة وثبت بعداد قراءات وحدة عند اجتياز CI.
- **الخطوة التنفيذية التالية:** PR ونجاح GitHub Actions الفعلي ثم دمج فرع التطوير فقط، تحديث ملفات التسليم مع commit وCI النهائي.

### 2026-11-21T00:34:06.866Z — تصحيح فشل Flutter analyze في PR #579 دون إخفاء فشل CI
- **التشغيل الفاشل:** [GitHub Actions #44844537479](https://github.com/775878805Osamaha/TradeLab/actions/runs/44844537479) **completed/failure**؛ التحليل حدد `unused_local_variable` في `flutter_app/lib/data/range_live_bid_delta.dart:115` بعد نقل مقارنة أحداث BID من التاريخ الكامل إلى قائمة حدود المللي ثانية. اختبارات Range/Replay SKIPPED بهذا الفشل؛ لم يُدمج PR.
- **الإصلاح:** استخدم `boundaryMs` فعليًا في مقارنة كل زوج أحداث مصدرية (`earlier.timestamp == boundaryMs` و`newer.timestamp == boundaryMs` وكذلك السعر المطابق) بدلاً من مجرد مقارنة تاريخين قد يختلفان معًا عن حد المصدر؛ أكثر صرامة ويحمي ترتيب cTrader/Replay.
- **الملفات:** `flutter_app/lib/data/range_live_bid_delta.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **المستودع والفرع:** `775878805Osamaha/TradeLab` / `perf/tradelab-live-bid-boundary-only-20261121`؛ `main` دون تعديل، لا APK/Release.
- **التحقق:** Flutter CI التصحيحي `PENDING` حتى إعادة تشغيل PR #579. لا قياسات Android Profile أو cTrader حي.
- **الخطوة التالية:** إعادة فحص GitHub Actions، إصلاح أي FAIL إضافي؛ لا دمج إلا بعد PASS.

### 2026-11-21T00:37:17.185Z — نجاح ودمج PR #579 وتقليل نقل أرشيف cTrader BID عند التحديث الحي
- **النتيجة:** [PR #579](https://github.com/775878805Osamaha/TradeLab/pull/579) **MERGED** (squash) إلى `test/flutter-all-fixes-20261116`، SHA المدمج الفعلي `819da6f63c5f1b01cbe4217d061a4b4305e7a813`. تم التحقق من فرع التطوير و`main`.
- **CI الناجح:** [Actions #44844722298](https://github.com/775878805Osamaha/TradeLab/actions/runs/44844722298) **completed/success** على PR HEAD `2946061af493c8bea28c63348039d91cf914c337`؛ Flutter analyze، اختبارات Range/Replay/chart والتوقيت في اليمن. الفشل السابق [#44844537479](https://github.com/775878805Osamaha/TradeLab/actions/runs/44844537479) **FAIL** بسبب unused boundaryMs، صُحح بفحص أصالة timestamp.
- **ملفات الكود والاختبار:** `flutter_app/lib/data/range_live_bid_delta.dart` و`flutter_app/test/range_live_bid_delta_test.dart`؛ أُضيف `RangeLiveBidBoundary` ببحث ثنائي للـsame-ms tail وأصبح الإدخال إلى `compute` من التاريخ السابق هو tail فقط، لا المليون تيك كله. يظل تحقق brokerPage كاملاً دون إنقاص أو اختلاق حدث. احتوى الاختبار على مليون Tick افتراضي و6500 حدث جديد، مع ميزانية المصدر وduplicate ordinal.
- **التوثيق:** `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md` تم تحديثهما بهذا السجل بعد دمج PR والـSHA الحقيقي.
- **الحدود:** لا FPS/وقت تشغيل مقاس على Android، ولا جلسة cTrader حقيقية؛ `main` بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`، لا APK/Release ولا مشاريع أخرى.
- **الخطوة التالية الوحيدة:** إزالة التحقق المكرر/العامل الثاني عندما تكون صفحة BID كبيرة، مع اختبارات تحقق توقيت المصدر وترتيب الأحداث وCI قبل دمج التطوير.

### 2026-11-21T00:38:49.342Z — توحيد فحص صفحة cTrader BID الكبيرة واستخراج التحديث الحي في worker واحد
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`, `perf/tradelab-single-pass-live-bid-verification-20261121` مبني على `8c1104faa8264212cb8a4a09a92bc8872d16447c`؛ `main` دون تعديل، لا APK/Release ولا مشاريع أخرى.
- **الاختناق المراجع من كود PR #579:** `RangeLiveBidDelta.verifiedSuffixAsync` كان يرسل `brokerPage` الكبيرة لعملية `RangeBidPageVerifier.verifyAsync` (عامل Flutter compute) ثم يعيد إرسال **نفس الصفحة** إلى `_verifiedLiveSuffixWorker` (عامل ثانٍ). PR #579 قلل نسخة الأرشيف القديم، لكن نسخة الصفحة الجديدة كانت لا تزال تتكرر.
- **التحسين:** `_verifyAndExtractLiveSuffix` يجري `RangeBidPageVerifier.verify` من البداية للنهاية، ثم يرفض الصفحة الفارغة، ثم يفحص كل أحداث boundary الموثقة ويفصل suffix من نفس العامل. حد `RangeBidPageVerifier.minOffloadTicks` هو 5000؛ الملفات الأقل تُفحص محليًا دون worker. لا حذف لتكرار التيكات الأصلي ولا توليد سعر أو تغيير مصدر أو كشف future Replay.
- **الاختبارات الجديدة:** إثبات تطابق النتائج عند 4999/5000/6501 Tick، رفض صفحات 5000+ بترتيب معكوس، تجاوز وقت `toMs`، سعر BID غير صالح، وتعارض السعر في مللي ثانية التداخل. يظل اختبار `_MillionBidHistory` (مليون مصدر + 6500 تيك) للتحقق من أن إرسال التاريخ الكامل قد توقف.
- **الملفات:** `flutter_app/lib/data/range_live_bid_delta.dart`, `flutter_app/test/range_live_bid_delta_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **التحقق الحالي:** GitHub Actions `PENDING` إلى حين فتح PR؛ لا قياسات زمنية Android ولا cTrader حي. التحسين حسابي/نقل بيانات وليس ادعاء بقياس FPS.
- **الخطوة التالية الوحيدة:** PR ثم CI PASS ودمج إلى فرع التطوير، مع حفظ SHA الحقيقي ورابط التشغيل الناجح.

### 2026-11-21T00:42:40.500Z — نجاح ودمج PR #580: توحيد تحقق صفحات cTrader BID الكبيرة
- **الدمج الفعلي:** [PR #580](https://github.com/775878805Osamaha/TradeLab/pull/580) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند SHA `b2c323eeb2a4d110176bdb92a15371d859c0c53c`؛ تم تأكيد حالة PR في GitHub.
- **CI:** [Actions #44845266471](https://github.com/775878805Osamaha/TradeLab/actions/runs/44845266471) **completed/success** للـPR HEAD `4aa1ea3e780eba81314457b440e3cba35d6ca7ba`. نجح `flutter analyze --no-fatal-infos` واختبارات Range/Replay/chart وتوقيت Yemen.
- **العمل:** إزالة ثاني `compute` وزمن نقل صفحة BID كبيرة ثانيةً: `_verifyAndExtractLiveSuffix` يتحقق من كافة التيكات (timestamp/price/order/bounds)، ثم يقارن ذيل أحداث المللي ثانية الأخيرة ويعيد فقط الأحداث الجديدة في نفس العامل. `RangeBidPageVerifier.verify` سياسة المصدر نفسها، دون إضعاف فحص أو اختلاق شموع. ما تزال معالجة الصفحة الصغيرة دون worker.
- **الملفات:** `flutter_app/lib/data/range_live_bid_delta.dart` و`flutter_app/test/range_live_bid_delta_test.dart` و`docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`.
- **الانحدار الجديد:** اختبارات حدود 4999/5000/6501 تيك تؤكد تطابق المسار، وأكثر من 5000 Tick مع ترتيب خاطئ/زمن أعلى من الحد/سعر سلبي/حدث BID منقّح تُرفض كلها؛ اختبارات المليون تيك السابقة محفوظة ونُفذت ضمن البوابة.
- **القيود:** `main` لم يتغير، `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`، لا APK أو Release ولا مشاريع أخرى. Android Profile/FPS/CTrader broker الحقيقي `NOT RUN`.
- **الخطوة التالية الوحيدة:** جمع ملف Android Profile مع حساب cTrader فعلي للشارت وRange/Replay، توثيق p50/p95/p99، ثم تحسين الاختناق الأعلى بالأدلة.

### 2026-11-21 (UTC) — تصحيح تحقق المصدر/المسافة لـRange الحي (فتح PR قيد الإجراء)
- **المستودع والفرع:** `775878805Osamaha/TradeLab`، `fix/tradelab-range-snapshot-boundary-20261121` مشتق من `358f38532a7347fef92172935c2d465a85b7195b`؛ فرع `main` دون تعديل.
- **الحدث:** إنشاء فرع منفصل وتعديل ثلاثة ملفات؛ commits: [de5fbb5](https://github.com/775878805Osamaha/TradeLab/commit/de5fbb5e8997964cf223c5de4f7934d343fc57da)، [b1157e4](https://github.com/775878805Osamaha/TradeLab/commit/b1157e4878d884bbe557c6497fcb65e10d925807)، [6122183](https://github.com/775878805Osamaha/TradeLab/commit/6122183d0ae425582c21e36af6b527389b233657).
- **التصرف الفعلي:** رفض وصل لقطة آخر BID غير المطابقة للسجل أو أول مصدر/إغلاق رغم تطابق عدد الأحداث وآخر UTC؛ منع نشر نتيجة تحديث Range إذا تغيّر `point` أثناء Await. لا تعديل مصدر cTrader/Binance أو Replay cutoff أو الحساب الورقي.
- **الاختبارات المكتوبة:** ثلاث حالات mismatch للحدود وحالة append صحيحة؛ ملف `flutter_app/test/range_bar_timeline_test.dart` ضمن بوابة `verify-flutter-range` الموجودة.
- **التحقق:** **NOT RUN** محليًا (لا Flutter SDK)؛ **PENDING** CI حتى فتح PR. لم يُفحص Android Profile أو جلسة cTrader الحية. لا APK/Release ولا تغيير `main`.
- **الملفات:** `flutter_app/lib/data/range_bar_timeline.dart`، `flutter_app/lib/screens/chart_screen.dart`، `flutter_app/test/range_bar_timeline_test.dart`، وملفا التسليم.
- **الخطوة التالية:** فتح PR إلى التطوير، فحص CI الفعلي وإصلاح أي فشل، ثم الدمج والتقرير النهائي.

### 2026-11-21 (UTC) — نجاح CI ودمج PR #581 مع استلام التغييرات في التطوير
- **الإجراء والنتيجة:** [PR #581](https://github.com/775878805Osamaha/TradeLab/pull/581) **MERGED/squash** إلى `test/flutter-all-fixes-20261116`؛ commit الدمج الفعلي [`9a8997f92905e77ca28ea9acb371406e2f037de4`](https://github.com/775878805Osamaha/TradeLab/commit/9a8997f92905e77ca28ea9acb371406e2f037de4). رأس فرع التطوير تحقق مطابقًا له بعد الدمج.
- **دليل اختبارات GitHub:** [Actions #44908442478](https://github.com/775878805Osamaha/TradeLab/actions/runs/44908442478) **completed/success** لرأس PR `d8a0438c5b1df9168ce2cc8616e5c8259ceba82d`، بما يشمل `flutter analyze --no-fatal-infos` واختبارات التاريخ/Range/Replay والشارت وYemen timezone. لا APK.
- **ما تغير:** `flutter_app/lib/data/range_bar_timeline.dart` (تطابق حدود المصدر في O(1))؛ `flutter_app/lib/screens/chart_screen.dart` (إبطال تحديث إذا تغيّر point أثناء await)؛ `flutter_app/test/range_bar_timeline_test.dart` (ثلاث حالات فساد لقطة وحالة صحيحة)؛ `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md` (تقرير قابل للاستكمال).
- **ما لم يُختبر:** Android Profile/FPS الحقيقي، تسجيل دخول cTrader أو وصول BID حي. لم يتغير `main`، لم ينشأ APK/Release ولا تغيرت مشاريع أخرى.
- **الخطوة التالية الواحدة:** تسجيل p50/p95/p99 وتفاصيل سبب تأخر التحديث/اللمس في Android Profile حقيقي ثم استهداف أول اختناق موثق؛ لا دمج في `main` أو بناء APK تلقائيًا.

### 2026-11-21 (UTC) — حماية تخصيص شموع Range من تجاوز الحد، مرحلة PR قيد الفحص
- **المشروع/الفرع:** `775878805Osamaha/TradeLab` / `fix/tradelab-range-early-bar-budget-20261121` من `test/flutter-all-fixes-20261116` عند `8596fdac966d38a73d3bb3e57704ce0c366af384`.
- **الأفعال الفعلية:** إنشاء فرع تعديل وحفظ 4 ملفات كود/اختبار في commits [88fb63a](https://github.com/775878805Osamaha/TradeLab/commit/88fb63a3bd2c9011f942f8d59d4ad0cba2369698)، [3426b46](https://github.com/775878805Osamaha/TradeLab/commit/3426b46b43bf29b3e2a01899a6fd647b75631890)، [84e54a1](https://github.com/775878805Osamaha/TradeLab/commit/84e54a101bf34a003f255a5f5283a736e316c918)، [a6e4486](https://github.com/775878805Osamaha/TradeLab/commit/a6e4486f46eb119165be2f0c6bb50d3314d43af0).
- **تغيير الشيفرة:** تمرير سعة إغلاق متبقية لكل حدث BID إلى المولد، ومنع إنشاء شموع مغلقة أكثر من السقف قبل تخصيصها. ينطبق على التاريخ وبناء الإضافة الحية، ويبقي تحديث forming bar ممكنًا عند صفر سعة إغلاق. يحتفظ بخطأ عام ذي رسالة عربية في واجهة Range؛ لا كشف future Replay أو إلحاق بيانات من مصدر غير متحقق.
- **ملفات العمل:** `flutter_app/lib/data/range_bar_builder.dart`، `flutter_app/lib/data/range_bar_timeline.dart`، `flutter_app/test/range_bar_builder_test.dart`، `flutter_app/test/range_bar_timeline_test.dart`، `docs/HANDOFF.md`، `docs/CHANGE_REPORTS.md`.
- **الاختبار:** 6 حالات انحدار جديدة أضيفت، **NOT RUN** محليًا (Flutter SDK غير متوفر)، **CI PENDING** حتى PR؛ Android Profile/FPS وcTrader LIVE **NOT RUN**. دون APK/Release/main/مشاريع أخرى.
- **الخطوة التالية:** مراجعة GitHub Actions والتعامل مع PASS/FAIL، ثم الدمج فقط إلى التطوير مع تقرير SHA النهائي.

### 2026-11-21 (UTC) — نجاح فحص CI ودمج PR #582 لحماية ميزانية Range مبكرًا
- **المستودع:** `775878805Osamaha/TradeLab`؛ [PR #582](https://github.com/775878805Osamaha/TradeLab/pull/582) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` مع SHA الدمج الفعلي [`a18c6383e2cc88b882ca483b5bfcf6c32e92ff20`](https://github.com/775878805Osamaha/TradeLab/commit/a18c6383e2cc88b882ca483b5bfcf6c32e92ff20).
- **دليل الفحص:** [GitHub Actions #44909751279](https://github.com/775878805Osamaha/TradeLab/actions/runs/44909751279) **completed/success** على `323e4d32e660453d9161d624beae85d708a93ba7`: تحليل Flutter، اختبارات التاريخ/الشارت وRange/Replay، وفحص التوقيت في اليمن. الحالات الست الجديدة موجودة ضمن ملفات الاختبار التي أجريت.
- **سلوك الإصلاح:** `maxNewClosedBars` يحمي الحد قبل كل إنشاء شمعة Range مغلقة في تحديث تاريخي/حي؛ معالجة الفشل لا تنشر كتلًا جزئية؛ تحديث forming bar عند سعة إغلاق 0 ما زال ممكنًا. لا مصادر أسعار وهمية أو أوامر تداول حقيقية أو كشف Replay للمستقبل.
- **الملفات التي دخلت الدمج:** `flutter_app/lib/data/range_bar_builder.dart`, `flutter_app/lib/data/range_bar_timeline.dart`, `flutter_app/test/range_bar_builder_test.dart`, `flutter_app/test/range_bar_timeline_test.dart`، و`docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **المتبقي/الحدود:** Android Profile وFPS حقيقي/جلسة cTrader حية **NOT RUN**؛ لم تُنشأ APK أو Release، ولم يتغير `main` ولا أي مشروع آخر.
- **الخطوة التنفيذية التالية الوحيدة:** قياس Android Profile الحقيقي ببيانات cTrader موثقة قبل وصف السلاسة، ثم تصحيح اختناق مدعوم بأرقام.

### 2026-11-21 (UTC) — إضافة قياس أسباب التأخير في Range Live (التحقق قيد التنفيذ)
- **العمل/الفرع:** `775878805Osamaha/TradeLab`، `feat/tradelab-live-range-phase-profile-20261121` يبدأ من رأس التطوير `356bc85fd1c1c529e457d26cf266149f9bcd45ba`.
- **الملفات المحفوظة:** `flutter_app/lib/chart/chart_load_profiler.dart` commit [d2f8381](https://github.com/775878805Osamaha/TradeLab/commit/d2f83814adf503298ac901ab3441e1bbd452b577)؛ `flutter_app/lib/screens/chart_screen.dart` commit [a78a4ca](https://github.com/775878805Osamaha/TradeLab/commit/a78a4ca7506e45a3aae927e9566cbd7627d45363)؛ `flutter_app/test/chart_load_profiler_test.dart` commit [4de5ab8](https://github.com/775878805Osamaha/TradeLab/commit/4de5ab87227e7d951f0917549af1b6d08a4db82e)؛ وملفا التوثيق.
- **تغير الإنتاج:** قياس منفصل للـauthenticated cTrader fetch وBID validation وRange append وno-change، مع الاحتفاظ بوقت end-to-end عند إلحاق حدث موثق. لم يتغير تكوين شموع Range أو cutoff Replay أو المنفذ/الحساب ولا أي API request جديد.
- **الاختبارات:** اختبار انحدار جديد لعزل زمن/percentiles لكل مرحلة، التمييز بين poll بلا تحديث وappend فعلي، وغياب بيانات حساسة. **NOT RUN** محليًا لأن Flutter SDK غير متاح؛ **CI PENDING**؛ Android Profile الحقيقي/cTrader connected **NOT RUN**.
- **القيود:** لا APK/Release، لا تغيير `main` أو المشاريع الأخرى.
- **الخطوة التالية:** إنشاء PR وفحص GitHub Actions، تصحيح أي مشكلة مثبتة، ثم دمج في التطوير وتقرير رسمي بالروابط والـSHA.

### 2026-11-21 (UTC) — نجاح CI ودمج PR #583 لتفصيل بيانات أداء Range
- **المستودع/الفرع:** `775878805Osamaha/TradeLab` إلى `test/flutter-all-fixes-20261116`؛ [PR #583](https://github.com/775878805Osamaha/TradeLab/pull/583) **MERGED/squash**. SHA الدمج الحقيقي [`b5b8271a0b07ea9bc046c000e96dfbc428a29fe0`](https://github.com/775878805Osamaha/TradeLab/commit/b5b8271a0b07ea9bc046c000e96dfbc428a29fe0).
- **اختبار موثق:** [Actions #44910151843](https://github.com/775878805Osamaha/TradeLab/actions/runs/44910151843) **completed/success** عند PR HEAD `e410978bcf08feac21038b59622062b925ed541a`؛ `flutter analyze --no-fatal-infos`، اختبارات chart/Range/Replay/history وYemen timezone.
- **العمل في الشيفرة:** `ChartLoadPhase` مراحل جديدة `liveRangeBrokerFetch`, `liveRangeVerify`, `liveRangeAppend`, `liveRangeNoChange`، مع الحفاظ على `liveRangeUpdate` الإجمالي. `ChartScreen._refreshLiveRange` يقيس مراحل النجاح والتحقق الفعلي فقط، ويعزل polls بلا أحداث جديدة عن زمن append. لا تسجيل لأي رمز/سعر/حساب، لا أثر للقياس في الوضع الافتراضي دون flag.
- **الاختبارات/الملفات:** `flutter_app/lib/chart/chart_load_profiler.dart`، `flutter_app/lib/screens/chart_screen.dart`، `flutter_app/test/chart_load_profiler_test.dart`، `docs/HANDOFF.md`، `docs/CHANGE_REPORTS.md`. اختبار p95 مستقل لكل مرحلة ومنع حقول حساب/سعر.
- **الحدود:** لا APK/Release، لا تغيير `main` ولا مشاريع أخرى. Android Profile وتسجيل cTrader الحقيقي/FPS **NOT RUN**؛ تحقق CI ليس قياس FPS.
- **الخطوة التالية الواحدة:** Android Profile على جهاز حقيقي بحساب cTrader واستخراج أرقام p50/p95/p99 وتحديد سبب البطء الفعلي، دون التخمين.

### 2026-11-21 (UTC) — إصلاح أول انتقال إصبع بعد pinch فاسد قبل الاختبارات
- **الإجراء:** إنشاء `fix/tradelab-first-invalid-pinch-lift-20261121` من `8d9cb0141f2431bd310555eb2b870fdf68c86dd6` في `775878805Osamaha/TradeLab`، وتعديل ملفات المصدر والاختبار. Commits [f6b0ac9](https://github.com/775878805Osamaha/TradeLab/commit/f6b0ac9219916fd6ba4fe3bb69dfad4b08ea4d34) و[712a06d](https://github.com/775878805Osamaha/TradeLab/commit/712a06d8f015ee1e083e7a4de043a6a634246ba8).
- **التغيير:** حفظ حالة وجود إصبعين عندما تكون أول عينة مركز اللمس غير صالحة؛ يمنع اعتبار العينة الأولى بعد رفع الإصبع الثاني سحبًا فعليًا. إعادة anchoring سليمة للعينات التالية. لا تعديل لبيانات broker أو رسومات Replay أو أوامر ورقية.
- **الملفات:** `flutter_app/lib/chart/chart_viewport.dart`, `flutter_app/test/chart_viewport_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **التحقق:** اختباران إضافيان يغطيان NaN/Infinity/scale=0 ثم lift وحركة طبيعية وتكبير جديد؛ **CI PENDING** حتى فتح PR، Android Profile/FPS وFlutter محلي **NOT RUN**. لا main/APK/Release/مشاريع أخرى.
- **التالي:** إنشاء PR، متابعة فحص GitHub Actions إلى PASS، أو إصلاح الفشل إن وجد، ثم دمج فرع التطوير وتوثيق الـSHA والـCI.

### 2026-11-21 (UTC) — نجاح GitHub Actions ودمج PR #584 لحماية الانتقال من إصبعين إلى واحد
- **المستودع/الفرع:** `775878805Osamaha/TradeLab` إلى `test/flutter-all-fixes-20261116`. [PR #584](https://github.com/775878805Osamaha/TradeLab/pull/584) **MERGED/squash**؛ commit الدمج الفعلي [`d88107c62dd461c72dc8051dcfbde130be3c4094`](https://github.com/775878805Osamaha/TradeLab/commit/d88107c62dd461c72dc8051dcfbde130be3c4094).
- **التحقق الموثق:** [GitHub Actions #44914776406](https://github.com/775878805Osamaha/TradeLab/actions/runs/44914776406) **completed/success** على الرأس `9b23a72359e9ed060e4f3572ef85a4874d55ca9a`. ناجحة: `flutter analyze --no-fatal-infos`، اختبار chart_viewport مع الاختبارين الجديدين، واختبارات Range/Replay/history والشارت وYemen timezone.
- **السلوك النهائي:** عينة two-pointer الأولى إذا كانت NaN/Infinity/scale 0 تُسجّل جلسة pinching قائمة دون اعتماد إحداثيات غير صحيحة، وتُهمل حركة single-pointer الأولى بعد الرفع بدل القفز بـdelta وهمي. ما زال السحب الطبيعي/تكبير الإصبعين الجديد مستمرًا بعد ذلك.
- **الملفات:** `flutter_app/lib/chart/chart_viewport.dart`, `flutter_app/test/chart_viewport_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **حدود التحقق:** ليس Android Profile ولا FPS حقيقيًا، ولم يختبر مستخدم التطبيق على الهاتف بعد؛ لا APK/Release، ولا تعديل `main` أو مشاريع أخرى.
- **الخطوة التالية الوحيدة:** قياس Android Profile على الشارت الفعلي لتقييم سلاسة اللمس والتكبير بأرقام p50/p95/p99 ثم معالجة الاختناق المثبت.

### 2026-11-21 (UTC) — جعل snapshot Range التاريخي غير قابل للتعديل (CI معلّق)
- **الفرع/المصدر:** `775878805Osamaha/TradeLab`، `fix/tradelab-immutable-range-timeline-20261121` من رأس التطوير `c34eea43d5f51309ae6275a8f6e6f341e5f41db2`.
- **التعديلات الفعلية:** `range_bar_timeline.dart` عند [c4abbc3](https://github.com/775878805Osamaha/TradeLab/commit/c4abbc36c8b60c4f8e9608ff63086b1fdbe7a181)؛ `range_bar_timeline_test.dart` عند [e2b8bca](https://github.com/775878805Osamaha/TradeLab/commit/e2b8bcac6a03baafed8acc25a0879785149d8608) و[تصحيح توقع حالة prepend](https://github.com/775878805Osamaha/TradeLab/commit/eceb6d0a7dbc60ecf7d95000976d6e4f1b4f91af). تقرير حفظ في `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`.
- **الهدف الدقيق:** صيانة ثلاثة buffers historical Range كمشاهدات فقط دون نسخ كامل الأرشيف، منع mutation للشموع/أحداث Replay من أي consumer؛ لا تغير في أسعار BID، توقيت الحد، إغلاق الشموع أو تداول ورقي.
- **الاختبارات المكتوبة:** بناء مباشر/older-prepend و6001 تيك عبر `buildAsync`، ومحاولات mutation لكل قائمة مع الحفاظ على source ordinal. **CI PENDING** حتى PR، Flutter محليًا **NOT RUN**، Android Profile/FPS **NOT RUN**.
- **القيود:** لا main/APK/Release/مشاريع أخرى.
- **الخطوة التالية:** PR إلى التطوير، CI PASS أو إصلاح الخطأ، ثم الدمج والتوثيق مع SHA الحقيقي.

### 2026-11-21 (UTC) — نجاح CI ودمج PR #585 لحماية قوائم تاريخ Range بلا نسخ إضافي
- **المشروع/الفرع:** `775878805Osamaha/TradeLab`، [PR #585](https://github.com/775878805Osamaha/TradeLab/pull/585) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند SHA [`bd41bc1f66e0fc49a908254baf5b163005671802`](https://github.com/775878805Osamaha/TradeLab/commit/bd41bc1f66e0fc49a908254baf5b163005671802).
- **اختبارات فعلية على GitHub:** [Actions #44915200946](https://github.com/775878805Osamaha/TradeLab/actions/runs/44915200946) **completed/success** عند `75773a86a82ccf3b3b8eec045070b007993968af`؛ تحليل Flutter واختبارات التاريخ/Range/Replay/chart وتوقيت اليمن بما فيها اختبارات 6001 BID في worker ورفض محاولات mutation.
- **السلوك الجديد:** `RangeBarTimeline.build` يعرض `UnmodifiableListView` فوق قوائم الشموع ومؤشرات إغلاق أحداث BID والتوقيت المأخوذة مباشرة من العامل؛ لا يستطيع consumer استخدام `add/[]=/clear/removeLast` لتغيير snapshot الموثقة، ولا تُضاف نسخ كاملة بحجم 250k صف للمجرد حماية القوائم. لا تغيير في الأسعار الأصلية أو رسم Replay.
- **الملفات:** `flutter_app/lib/data/range_bar_timeline.dart`, `flutter_app/test/range_bar_timeline_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **الحدود:** لم تقاس سلاسة Android الحقيقية/FPS ولم يتصل حساب cTrader حي، ولا APK/Release ولا تغيير `main` أو مشاريع أخرى.
- **الخطوة التالية الوحيدة:** تسجيل Android Profile فعلي وتحليل pan/pinch وRange ببيانات موثقة، دون افتراض تحسن FPS من CI وحده.

### 2026-11-21 (UTC) — بداية إصلاح اختيار العامل للقفزة الأولى في Range الحي
- **المشروع والفرع:** `775878805Osamaha/TradeLab` / `fix/tradelab-live-range-first-gap-offload-20261121` من التطوير عند `dc0c324ce1cb8bde51e8fbea62b243a305831836`.
- **التغيير الفعلي:** `RangeBarTimeline.shouldAppendInBackground` يمرّر آخر تيك BID محفوظ قبل الصفحة الحديثة إلى تقدير حمل الشموع، لتجنب نقل قفزة 4100+ شمعة إلى isolate الواجهة إذا احتوت الصفحة على حدث واحد. لا نقل كامل للأرشيف لأجل التقدير، ولا إعادة كتابة لأسعار حقيقية/Replay.
- **الملفات وcommits:** `flutter_app/lib/data/range_bar_timeline.dart` [5db6e40](https://github.com/775878805Osamaha/TradeLab/commit/5db6e4035a82b079b524a3a04ba7982d1ef1abd9)؛ `flutter_app/test/range_bar_timeline_test.dart` [31c7e12](https://github.com/775878805Osamaha/TradeLab/commit/31c7e12afab937dd7f4709eb0eede83c54e90639)؛ تحديث `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`.
- **اختبارات مكتوبة:** قفزة تيك واحد 4100 شمعة صحيحة المصدر مع بقاء cutoff Replay، وفصل الحالات البسيطة عن الأرشيف/الشموع الكبيرة. **CI PENDING** حتى PR. Flutter SDK محليًا وAndroid Profile/FPS وحساب cTrader حي **NOT RUN**.
- **القيود:** لا APK أو Release أو تغيير `main` أو مشاريع أخرى.
- **الخطوة التالية:** PR إلى التطوير، فحص CI/اختبارات الشارت، معالجة أي إخفاق، ثم دمج وتوثيق SHA/رابط الاختبار الفعلي.

### 2026-11-21 (UTC) — نجاح الاختبار ودمج PR #586 لاختيار خلفية Range الحي
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، [PR #586](https://github.com/775878805Osamaha/TradeLab/pull/586) **MERGED/squash** في `test/flutter-all-fixes-20261116` عند commit [`32c9efc46c5e9f2ec63da687043d0b4e828e5141`](https://github.com/775878805Osamaha/TradeLab/commit/32c9efc46c5e9f2ec63da687043d0b4e828e5141).
- **نتيجة التحقق الرسمية:** [GitHub Actions #44916281496](https://github.com/775878805Osamaha/TradeLab/actions/runs/44916281496) **completed/success** لـPR HEAD `77ac5bb265861b48b5e4edea5878098acf6bb3ea`. نجح `flutter analyze`، اختبارات التاريخ/الشارت/Range/Replay وتوقيت اليمن، ومنها اختبارات قفزة 4100 شمعة من حدث BID واحد واختيار worker.
- **التغيير الفعلي:** `RangeBarTimeline.shouldAppendInBackground` يضيف آخر حدث BID موثق كمرجع تقدير حمل أول تيك جديد، دون إعادة مسح أرشيف BID كله. الصفحات الصغيرة المعتادة تبقى مسارًا مباشرًا، والقفزات الكبيرة تفوّض `compute` قبل توليد الشموع. لا تغيير المصدر أو قواعد إغلاق شموع Range أو ordinal لحدث Replay ولا كشف المستقبل.
- **الملفات:** `flutter_app/lib/data/range_bar_timeline.dart`، `flutter_app/test/range_bar_timeline_test.dart`، `docs/HANDOFF.md`، `docs/CHANGE_REPORTS.md`.
- **المتبقي:** Android Profile/FPS، جلسة cTrader حية غير مختبرين **NOT RUN**؛ لا APK/Release/main أو مشاريع أخرى.
- **التالي:** إثبات كلفة كل مرحلة على Android حقيقي ببيانات cTrader موثقة ثم تحسين الاختناق الأكبر مع اختبارات.

### 2026-11-21 (UTC) — ضبط أهلية inertial chart fling على الإزاحة المرئية (قبل الفحص)
- **المستودع/الفرع:** `775878805Osamaha/TradeLab` / `fix/tradelab-boundary-fling-gesture-20261121` من `4d811ec8213ea82d162fe64d1de876b6b356c580`.
- **التغييرات:** `flutter_app/lib/chart/chart_viewport.dart` commit [8420079](https://github.com/775878805Osamaha/TradeLab/commit/8420079fee2e0d84bc645bb52f3c19aa2c91e801)؛ `flutter_app/test/chart_viewport_test.dart` commit [342521c](https://github.com/775878805Osamaha/TradeLab/commit/342521c1c542569fc21f01acd048788e1b709b55)؛ تحديث ملفّي الاستكمال.
- **السلوك:** زخم الشارت يُحتسب من الحركة المعتمدة لviewport بعد clamp، لا من سحب الإصبع خارج نطاق التاريخ؛ لا رسوم متحركة وهمية عند الحدود ولا تغيير أساسي في الشارت/Replay/الأسعار.
- **الاختبارات المكتوبة:** اختبار مسار oldest/right whitespace مع delta ±600 وغياب fling، واختبار 200px تحرك 5px فقط، والسحب الطبيعي 40px ورفض الهندسة غير الصالحة.
- **التحقق:** **CI PENDING** إلى حين PR، Flutter محليًا/Android Profile/FPS/جهاز حقيقي **NOT RUN**. لا APK/Release أو main/مشاريع أخرى.
- **التالي:** PR، قراءة حالة GitHub Actions النهائية، تصحيح أي فشل، دمج التطوير وتوثيق SHA ورابط Actions.

### 2026-11-21 (UTC) — فشل CI #44916690008 وتحديد خطأ دقة حد الشارت وتصحيحه
- **المشروع/الفرع:** `775878805Osamaha/TradeLab`، PR [#587](https://github.com/775878805Osamaha/TradeLab/pull/587) في `fix/tradelab-boundary-fling-gesture-20261121`.
- **اختبار الفشل المؤكد:** [Actions #44916690008](https://github.com/775878805Osamaha/TradeLab/actions/runs/44916690008) **completed/failure**؛ سجل الوظيفة `Verify historical tick archive and chart interactions` = **649 PASS / 1 FAIL**. الاختبار `blocked historical boundary swipes cannot trigger phantom fling` في `chart_viewport_test.dart:851` كان يتوقع `horizontalTravel=0` وحصل على `3.552713678800501e-14` بكسل من الفرق العددي بين `-20.4` وحد `plotWidth/barWidth*0.68`. التحليل Flutter ناجح ولم يصل التشغيل إلى فحص Yemen timezone بعد فشل suite.
- **التصحيح المرتبط بالدليل:** `flutter_app/lib/chart/chart_viewport.dart` commit [5aa2e56](https://github.com/775878805Osamaha/TradeLab/commit/5aa2e5630b48389f7c50f9a84b3bacfff7f42603) يتجاهل `movedPixels <= 1e-9` بكسل؛ لا يعتبر خطأ roundoff حركة مسموحة وزخمًا. يبقي 1px و5px و40px في الاختبارات سليمة.
- **الحالة:** **CI PENDING** لنسخة الإصلاح الجديدة؛ لم يُدمج PR في التطوير، Android Profile/FPS **NOT RUN**، لا APK/Release/main/مشاريع أخرى.
- **الخطوة التالية:** التحقق من نسخة CI الأحدث في PR #587 وإصلاح أي فشل جديد قبل دمج التطوير وكتابة SHA/نتيجة الاختبارات.

### 2026-11-21 (UTC) — إعادة اختبار PR #587 PASS ودمج إصلاح الزخم بعد الفشل العددي
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، [PR #587](https://github.com/775878805Osamaha/TradeLab/pull/587) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند commit [`2843d9ec6b56c5928249f3d50d9ade7854c22c5a`](https://github.com/775878805Osamaha/TradeLab/commit/2843d9ec6b56c5928249f3d50d9ade7854c22c5a).
- **خط الاختبارات الأول:** [Actions #44916690008](https://github.com/775878805Osamaha/TradeLab/actions/runs/44916690008) **FAIL**: 649 حالة ناجحة وواحدة فاشلة بسبب `horizontalTravel=3.552713678800501e-14` بدل صفر عند حساب حد البياض الأيمن. ملاحظة: لم يُقبل الدمج حينها.
- **التصحيح:** [commit 5aa2e56](https://github.com/775878805Osamaha/TradeLab/commit/5aa2e5630b48389f7c50f9a84b3bacfff7f42603) يستبعد خطأ roundoff تحت `1e-9` بكسل، ويبقي الحركة الطبيعية المؤثرة على candle viewport.
- **نتيجة الاختبار النهائي:** [GitHub Actions #44917017347](https://github.com/775878805Osamaha/TradeLab/actions/runs/44917017347) **completed/success** على PR HEAD `2046dfbb4965fff560b9c5d5797e747f8066252d`: Flutter analyze وchart/Range/Replay/history وYemen timezone.
- **الملفات:** `flutter_app/lib/chart/chart_viewport.dart`, `flutter_app/test/chart_viewport_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`. لا تغيير للمصدر الحقيقي أو أسعار BID أو كشف Replay المستقبلية.
- **الحدود:** لا APK/Release، لا تغيير main أو المشاريع الأخرى، ولا اختبار FPS/Android Profile أو تفاعل لمس جهاز حقيقي **NOT RUN**.
- **الخطوة التالية الواحدة:** قياس Android Profile الفعلي لسلاسة الإيماءات وRange/cTrader ثم استهداف أول تأخير بالأدلة.

### 2026-11-21 (UTC) — إصلاح تسجيل زمن إطارات الشارت المتأخر (فحص CI قيد البدء)
- **المستودع/الفرع:** `775878805Osamaha/TradeLab` / `fix/tradelab-frame-timing-batch-attribution-20261121` تأسس من dev عند `f66cc5812354adbaf8d1d902304bf11dd7e50fc3`.
- **سبب الإصلاح:** callback توقيت إطارات Flutter يصل متأخرًا على دفعات حسب وثائق SchedulerBinding، بينما جلسات اللمس السابقة تغلق قبل التسليم؛ الإطارات الراجعة قد تُفقد أو تُنسب خطأً إلى gesture أخرى. المصدر: https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html
- **التعديل:** `ChartFrameTimingAttribution` في `flutter_app/lib/chart/chart_frame_profiler.dart` commit [6c1030c](https://github.com/775878805Osamaha/TradeLab/commit/6c1030c818dca091fa8df16b5384c4326886279c). إنفاذ نافذتي الزمن على ساعة الإطار، قوائم bounded، تجاهل idle بعد touch-up، الاحتفاظ بالأرقام المسلمة الصحيحة p50/p95/p99. لا سر أو OHLC أو تفعيل خارج Profile.
- **اختبارات جديدة:** `flutter_app/test/chart_frame_profiler_test.dart` commit [57404a7](https://github.com/775878805Osamaha/TradeLab/commit/57404a75dd947fc70348522a721c280979179e2c) ثلاث حالات دفعات متأخرة، تداخل gestures دون خلط، وذاكرة محدودة/عينات غير مخترعة.
- **التحقق:** GitHub Actions **PENDING**، جهاز Android حقيقي/FPS/cTrader حي **NOT RUN**. ملفات التوثيق: `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`. لا main ولا APK/Release.
- **التالي:** فتح PR، التحقق من Flutter analyze وCI، إصلاح أي FAIL، دمج في التطوير فقط وحفظ CI URL وSHA النهائي.

### 2026-11-21 (UTC) — نجاح CI ودمج PR #588 لربط تأخر FrameTiming بزمن الإيماءة
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، [PR #588](https://github.com/775878805Osamaha/TradeLab/pull/588) **MERGED/squash** في `test/flutter-all-fixes-20261116` عند [SHA `10ab6bd66348b9319302818f0cc0504e6ae5cbbc`](https://github.com/775878805Osamaha/TradeLab/commit/10ab6bd66348b9319302818f0cc0504e6ae5cbbc).
- **نتيجة GitHub الفعلية:** [Actions #44918861973](https://github.com/775878805Osamaha/TradeLab/actions/runs/44918861973) **completed/success** على HEAD `e52ff229b08d6c0b5934c85cf04fbfdf844d8eb1`. نجح تحليل Flutter واختبارات chart/Range/Replay/history وYemen timezone، بما فيها 3 اختبارات انحدار للتوقيت المؤجل.
- **التغيير:** `flutter_app/lib/chart/chart_frame_profiler.dart` يُبقي نوافذ الإيماءات إلى وصول الدفعات الزمنية الحقيقية، ويُسند كل `FrameTiming.buildStart` إلى pan أو pinch وفق حدودها الزمنية بدل وقت تسليم callback. يمنع تلويث p95 بإطار idle بعد رفع الإصبع أو بإيماءة لاحقة. حد 16 نافذة، لا أسماء رموز أو أسعار أو حسابات، profiling اختياري فقط؛ `flutter_app/test/chart_frame_profiler_test.dart` يتحقق من الحالات.
- **التوثيق:** تحديث `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md` بعد الدمج مع SHA ورابط CI الصحيح.
- **حدود الاختبار:** Android Profile/FPS/CTrader session فعلي **NOT RUN**، فلا ادعاء بتحسن سلاسة مقاس؛ لا APK أو Release أو main/مشاريع أخرى.
- **التالي:** جهاز Android/حساب cTrader موثّق وقياس p50/p95/p99 لـ pan/pinch/momentum، ثم إصلاح الاختناق الذي يظهر بالبيانات.

### 2026-11-21 (UTC) — فرع إصلاح هوية حجم شموع Range ورفض stale append
- **المستودع/الفرع:** `775878805Osamaha/TradeLab` / `fix/tradelab-range-distance-snapshot-integrity-20261121` من dev SHA `7c1eb83f55fb52dcb673107f87ebee2bfb40e602`.
- **المشكلة من الشفرة:** `RangeBarTimeline.appendVerifiedSuffixAsync` فحص سلامة BID الأول والأخير لكنه لم يفحص Range `priceDistance`. تغيير Range size مع وصول update متأخر يسمح بخلط شموع مؤكدة بمقاسين مختلفين وcutoff Replay غير متسق.
- **الإصلاح والملفات:** `flutter_app/lib/data/range_bar_timeline.dart` commit [a03b0ae](https://github.com/775878805Osamaha/TradeLab/commit/a03b0ae2e69633321b88960ca52fba5966c5eee1) يخزن حجم Range المصدر داخل snapshot ويقارن قبل الإلحاق حتى لو suffix فارغة؛ `flutter_app/test/range_bar_timeline_test.dart` commit [0b05499](https://github.com/775878805Osamaha/TradeLab/commit/0b05499a33d9a5fee36cbb8828dd56b21a9e272a) فيه اختبار اختلاف مقاس مع closes موثقة واختبار forming-only (0 closes) واختبار استمرار التحديث الموافق ومطابقة إعادة بناء المصدر.
- **الحالة:** **CI PENDING**، Android Profile/FPS والجهاز الحقيقي وحساب cTrader حي **NOT RUN**؛ لا APK/Release/main أو مشاريع أخرى.
- **التوثيق:** `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md` محدّثان في فرع التغيير.
- **التالي:** PR إلى dev، Flutter analyze + كامل الاختبارات، معالجة أي FAIL قبل الدمج ثم حفظ رابط CI وSHA الدمج النهائي.

### 2026-11-21 (UTC) — نجحت الاختبارات ودمج PR #589 لحماية هوية Range priceDistance
- **المستودع/الفرع:** `775878805Osamaha/TradeLab`، [PR #589](https://github.com/775878805Osamaha/TradeLab/pull/589) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند commit [`d89567db15fab88d0b0de05866bbd2a5adf02088`](https://github.com/775878805Osamaha/TradeLab/commit/d89567db15fab88d0b0de05866bbd2a5adf02088).
- **CI الفعلي:** [GitHub Actions #44921079135](https://github.com/775878805Osamaha/TradeLab/actions/runs/44921079135) **completed/success** على PR HEAD `b63f1d7dcc185c482500dc13c34e5c6668789f23`. اجتاز flutter analyze واختبارات التاريخ/Range/Replay/chart وتوقيت اليمن؛ لم يُدمج قبل انتهاء الاختبار.
- **السلوك الفعلي:** حقل `RangeBarTimeline.priceDistance` immutable مرتبط بكل مسار البناء التاريخي والإلحاق؛ يرفض `appendVerifiedSuffixAsync` snapshot لمقاس مختلف قبل أي دمج أو no-op حتى لو طابقت أسعار وتواقيت حدود BID، فلا يُنشئ Replay cutoff مختلطًا. الاختبارات تثبت الحفاظ على OHLC وأحداث المصدر عند المقاس الموافق.
- **الملفات:** `flutter_app/lib/data/range_bar_timeline.dart`, `flutter_app/test/range_bar_timeline_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **الحدود:** لا اختبار جهاز Android Profile/FPS ولا جلسة cTrader حي **NOT RUN**؛ لا APK/Release/main أو أي مشروع آخر.
- **الخطوة التالية:** قياس Android Profile على بيانات موثّقة كبيرة وتحليل p95/p99 للسحب/التكبير وعمليات Range ثم علاج أول اختناق مثبت.

### 2026-11-21 (UTC) — حماية Replay من نتائج نوافذ قديمة عند تبديل السوق أو الجلسة (CI قيد التنفيذ)
- **المشروع/الفرع:** `775878805Osamaha/TradeLab` / `fix/tradelab-replay-async-session-guard-20261121` من dev SHA `c48821be5c716e5147a84ff4ea3f6605b7504b0c`.
- **التغييرات المؤكدة بالشيفرة:** `ReplayAsyncSessionGuard` لهوية timestamps/source/account/timeframe/mode/session/revision في `replay_start_resolver.dart`; `chart_screen.dart` يتجاهل نتائج تأكيد إعادة بدء Replay وأوامر التداول الورقية إذا تغير المصدر أو الجلسة أثناء إظهار dialog، ولا يطبق random/earliest من نتائج تأكيد ملغى. إضافة `selectionEpoch` تمنع date-picker قديم من اختيار بداية جلسة لاحقة على نفس التاريخ المحمل.
- **commits:** [497ec68](https://github.com/775878805Osamaha/TradeLab/commit/497ec68ec31d0dd0e1b2c8b0d534eb4dbca95c28), [9fd8ba5](https://github.com/775878805Osamaha/TradeLab/commit/9fd8ba5810de9b5331f2ff2fa4d307988aab94cc), [51b52a8](https://github.com/775878805Osamaha/TradeLab/commit/51b52a8cdcd119f28513f7211a5f3048fe85556c), [9927920](https://github.com/775878805Osamaha/TradeLab/commit/9927920fc2c9ff54115b28a792957f7501bac65f), [cd70135](https://github.com/775878805Osamaha/TradeLab/commit/cd7013583fb0faadb3cc2a738ba887ecf58a34f5), [19d861a](https://github.com/775878805Osamaha/TradeLab/commit/19d861ac64f122b6e466de770f23d8b489517118).
- **الملفات:** `flutter_app/lib/replay/replay_start_resolver.dart`, `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/test/replay_start_resolver_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **الحالة:** **CI PENDING**، Android Profile/FPS وcTrader الحي وملف APK جديد **NOT RUN**. لا تغيير main/المشاريع الأخرى.
- **الخطوة التالية:** PR إلى dev، فحص CI النهائي، إصلاح أي فشل، دمج إلى dev فقط مع SHA الحقيقي وتحديث التوثيق والتحقق من حفظه.

### 2026-11-21 (UTC) — نجاح CI ودمج PR #590 لإلغاء إجراءات Replay القديمة بعد تغير الحساب أو الجلسة
- **المشروع/الفرع:** `775878805Osamaha/TradeLab` [PR #590](https://github.com/775878805Osamaha/TradeLab/pull/590) **MERGED/squash** في `test/flutter-all-fixes-20261116` عند [commit `032b99fc4d89bd633e97199d697ef4942a6c8780`](https://github.com/775878805Osamaha/TradeLab/commit/032b99fc4d89bd633e97199d697ef4942a6c8780).
- **الاختبار الفعلي:** [GitHub Actions #44922062150](https://github.com/775878805Osamaha/TradeLab/actions/runs/44922062150) **completed/success** على PR HEAD `e898644c6cb1fb6ae04a05e8e600a2cfaf28ab1e`. اجتاز Flutter Analyze واختبارات Replay/Range/history/chart وYemen timezone، ومن ضمنها session/source guard وReplay date selection epoch.
- **السلوك المنفذ:** يرفض نتائج confirmation/history/order المتأخرة إذا تغير source timestamp identity أو market/provider/account/timeframe/chartMode/replay session/revision، وتحمي selection epoch من نافذة تاريخ قديمة حتى مع نفس بيانات السوق. لا يعود popup random/earliest يختار بداية لجلسة أخرى إذا ألغيت إعادة البداية. التداول تدريبي فقط ولا اتصال لتنفيذ أوامر حقيقية.
- **الملفات:** `flutter_app/lib/replay/replay_start_resolver.dart`, `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/test/replay_start_resolver_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **الحدود:** Android Profile/FPS والجلسة الحية مع cTrader **NOT RUN**. لا APK/Release أو تعديل main/مشاريع أخرى.
- **التالي:** اختبار transitions 2→3→2 fingers على رسم الشارت مع rebase pinch، ثم CI/merge؛ ما زالت المطابقة البصرية البكسلية بحاجة إلى Screenshots حقيقية.

### 2026-11-21 (UTC) — معالجة قفزة pinch عند تغير مجموعة أصابع Android
- **الفرع:** `775878805Osamaha/TradeLab` / `fix/tradelab-multi-pointer-pinch-rebase-20261121` من dev SHA `fd90997ee46dd8479e3de79bb76cbfb280bf292a`.
- **التغيير:** `ChartTouchGesture` يميز انتقالات 2→3 و3→2، ويلغي pinch origin القديم ويُعيد تثبيته على الشارت الحالي عند أول عينة صحيحة؛ لا يفسر تغير المركز فجأة كتكبير أو سحب، ويحافظ على تصفية NaN/Infinity.
- **الكود:** [7b638b4](https://github.com/775878805Osamaha/TradeLab/commit/7b638b43b48ed4c9be40d32106d0bc51d50c8206) في `flutter_app/lib/chart/chart_viewport.dart`. **الاختبارات:** [87f999b](https://github.com/775878805Osamaha/TradeLab/commit/87f999b3d7dfc7af21c2bb954f81c1d36d0a059f) في `flutter_app/test/chart_viewport_test.dart`: انتقالات 2→3→2→1، تكبير 20→24→30px، منع phantom pan والتعامل مع invalid 3-pointer sample.
- **التوثيق:** `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md` في فرع الإصلاح.
- **التحقق:** GitHub CI **PENDING**؛ Android real touch/FPS وcTrader **NOT RUN**. لا APK/Release/main ولا مشروع آخر.
- **التالي:** PR إلى dev، انتظر CI PASS، ثم merge وتوثيق رابط الاختبار وSHA النهائي.

### 2026-11-21 (UTC) — نجاح CI ودمج PR #591 لإزالة قفزات pinch عند 2→3→2 أصابع
- **المستودع/الفرع:** `775878805Osamaha/TradeLab` [PR #591](https://github.com/775878805Osamaha/TradeLab/pull/591) **MERGED/squash** في `test/flutter-all-fixes-20261116` عند SHA [`cef8dc5e66dc36952f6ccf8ad359ceb79d01dde2`](https://github.com/775878805Osamaha/TradeLab/commit/cef8dc5e66dc36952f6ccf8ad359ceb79d01dde2).
- **CI الفعلي:** [GitHub Actions #44922495795](https://github.com/775878805Osamaha/TradeLab/actions/runs/44922495795) **completed/success** لرأس PR `f51041386980041784213f9ba6e75110ab1c9bd0`: Flutter analyze واختبارات chart/Range/Replay/history وYemen timezone.
- **التغيير:** تحديث `ChartTouchGesture.update` لإلغاء pinch origin عند تغير عدد الأصابع المتعددة (2→3→2) وإعادة تثبيت origin على viewport الحالية عند أول عينة صالحة دون إسقاط إطار إضافي. تحافظ الشيفرة على تجاهل العينات NaN/Infinity ومنع الحركة الوهمية بعد الرفع النهائي. لا تغيير لشارت البيانات أو OHLC/Replay.
- **الملفات:** `flutter_app/lib/chart/chart_viewport.dart`، `flutter_app/test/chart_viewport_test.dart`، `docs/HANDOFF.md`، `docs/CHANGE_REPORTS.md`.
- **القيود:** فحص Android real touch/Profile/FPS وcTrader حي **NOT RUN**؛ لا APK أو Release أو main/مشاريع أخرى. النجاح الآلي لا يثبت pixel-perfect أو FPS الفعلي.
- **التالي:** مقارنة لقطات الشاشة وسلوك gesture/replay على Android Profile مع TradingView ومعالجة أول فرق موثق، دون تخمين.

### 2026-11-21T16:11:40.441Z — إصلاح OHLC tracking على Android طبق سلوك TradingView الموثق (CI PENDING)
- **الفرع:** 775878805Osamaha/TradeLab / fix/tradelab-mobile-crosshair-persistent-tracking-20261121 من dev SHA 592e6f7c307d96efb574de79d72863dedc5e13b9.
- **الفجوة/المرجع:** TradingView Mobile https://www.tradingview.com/charting-library-docs/latest/mobile_specifics/ يثبت crosshair بالضغط المطول ويُنهيه بنقرة؛ TradeLab سابقًا أخفى crosshair فور onLongPressEnd، فجعل OHLC inspector غير مقروء بعد رفع الإصبع.
- **التغيير:** [04bfeb0](https://github.com/775878805Osamaha/TradeLab/commit/04bfeb018fa19afd5e52c4e6059f919ddff3732c) في flutter_app/lib/screens/chart_screen.dart يجعل عرض OHLC مستمرًا بعد الرفع، ويغلق التتبع بنقرة واحدة دون تسريبها لتعديل الرسومات أو تحديد Replay، ويمنع فتحه من محوري الوقت/السعر، أو في Replay selecting/بدون candles.
- **اختبارات:** [6051d3d](https://github.com/775878805Osamaha/TradeLab/commit/6051d3dd33e5709ab55198ff30f899bec04fd41a) في flutter_app/test/chart_ohlc_inspector_test.dart اختبارات widget عند 320dp و390dp بمصدر بيانات test fixture فقط: long press ثم lift ثم OHLC persists ثم single tap dismiss، وlongpress axis not active.
- **التقارير:** docs/HANDOFF.md, docs/CHANGE_REPORTS.md؛ تغييرات أخرى خارج TradeLab **NONE**.
- **التحقق:** GitHub CI **PENDING**، Android real device Profile/FPS وcTrader live **NOT RUN**، ولا APK أو Release أو main.
- **التالي:** افتح PR، راجع CI وأصلح FAIL ثم ادمج إلى dev فقط بعد PASS واحفظ الحالة الحقيقية.

### 2026-11-21T16:16:32.499Z — PR #592: تحليل فشل CI وإصلاح تعارض Tap/Scale مع Crosshair الطويل
- **CI الأول FAIL:** [Actions #44923242646](https://github.com/775878805Osamaha/TradeLab/actions/runs/44923242646) finished failure؛ Flutter analyze PASS، 4 failures فقط في widget cases 320/390dp لـ chart_ohlc_inspector_test.dart وchart_paint_only_pan_test.dart. تفصيل log: crosshair بقي ظاهرًا بعد tap جديد لأن Scale recognizer يملك اللمسة فلا يصل onTapUp؛ الاختبار القديم ينتظر اختفاء OHLC عند finger lift وهذا عكس السلوك الصحيح المستهدف.
- **تصحيح السلوك:** [9e56e40](https://github.com/775878805Osamaha/TradeLab/commit/9e56e40ba3cd398eb63cb7a7b2f74195772fce78) في flutter_app/lib/screens/chart_screen.dart: Listener.onPointerDown يزيل crosshair فور لمس جديد حتى عندما يفشل onTapUp، مع حماية من تحرير رسم/تغيير Replay، ومع reset عند pointer cancel أو بدء long-press آخر.
- **تحديث اختبار سابق:** [6a04286](https://github.com/775878805Osamaha/TradeLab/commit/6a0428669f621568f822d60c3b32240a3b2e66d1) في flutter_app/test/chart_paint_only_pan_test.dart: يتأكد من بقاء OHLC بعد up والإخفاء بعد tap واحد. الاختباران الجديدان في chart_ohlc_inspector_test.dart يبقيان.
- **التوثيق:** docs/HANDOFF.md وdocs/CHANGE_REPORTS.md؛ branch fix/tradelab-mobile-crosshair-persistent-tracking-20261121، PR #592 إلى test/flutter-all-fixes-20261116. **CI revalidation PENDING**؛ Android real/Profile/FPS وcTrader live NOT RUN، لا APK/Release/main.
- **الخطوة التالية:** التحقق من آخر GitHub Actions run بعد التصحيح ودمج PR فقط إذا completed/success.

### 2026-11-21T16:19:56.911Z — تصحيح فشل CI الثاني لامتحان crosshair بسبب Flutter DoubleTap timer
- **الفرع وPR:** 775878805Osamaha/TradeLab, fix/tradelab-mobile-crosshair-persistent-tracking-20261121, [PR #592](https://github.com/775878805Osamaha/TradeLab/pull/592).
- **النتيجة المثبتة:** [Actions #44923687526](https://github.com/775878805Osamaha/TradeLab/actions/runs/44923687526) completed/failure؛ Flutter analyze PASS، كافة اختبارات crosshair الجديدة 320/390 PASS، باقي الشارت/Range/Replay لم تظهر فيها أخطاء سلوك؛ فشل اختبارا chart_paint_only_pan_test بسبب Pending timer (duration 40ms) من DoubleTapGestureRecognizer بعد محاكاة نقرة واحدة.
- **التصحيح:** [43256e8](https://github.com/775878805Osamaha/TradeLab/commit/43256e8b7a6149092650026d2af325c7ad46fede) في flutter_app/test/chart_paint_only_pan_test.dart يستبدل pump() بـ pumpAndSettle() بعد نقرة إنهاء tracking، حتى تنتظر Flutter test timers ولن يخلّف مؤقتًا بعد انتهاء الاختبار. لم يغيّر الكود أي أسعار أو شموع أو Replay.
- **الملفات:** flutter_app/test/chart_paint_only_pan_test.dart وdocs/HANDOFF.md وdocs/CHANGE_REPORTS.md. **CI PENDING** للتصحيح؛ Android Profile/FPS وcTrader live NOT RUN، لا APK/Release/main.
- **التالي:** تحقق من CI الكامل، وصحح أي FAIL آخر ثم merge dev وتوثيق SHA الفعلي.

### 2026-11-21T16:24:16.091Z — نجاح CI الثالث لـ PR #592 ورفض الدمج بسبب PR head غير متزامن
- **اختبار ناجح:** [Actions #44923997988](https://github.com/775878805Osamaha/TradeLab/actions/runs/44923997988) completed/success على afae3e2316ddd74a516783ade2214d067facd8a0، بما فيه Flutter analyze، crosshair widget tests 320/390dp، gesture، Range، Replay، history، Yemen timezone.
- **اختلاف GitHub REST:** PR #592 head SHA afae3e2316ddd74a516783ade2214d067facd8a0، لكن branch fix/tradelab-mobile-crosshair-persistent-tracking-20261121 ref هو 049c2c97637837926b423551fe47dddcb784c8d7 (commit docs-only من parent afae3e). أول merge عبر GitHub returned 409 Head branch is out of date، لذا **PR NOT MERGED** ولا تعديل dev/main.
- **الإجراء:** تحديث PR body لشرح ثلاث جولات CI (2 فشل ثم نجاح) والحالة التقنية، ومحاولة توثيق هذا الحدث في docs/HANDOFF.md وdocs/CHANGE_REPORTS.md؛ لا تعديل source أو الاختبارات بعد نجاح CI. Android Profile/cTrader live NOT RUN، لا APK.
- **الخطوة التالية:** إعادة مزامنة HEAD بطريقة آمنة دون force، تحقّق من CI، ثم merge وتسجّل SHA الدمج الحقيقي.

### 2026-11-21T16:28:18.728Z — دمج PR #592 مع نتائج CI وإنشاء معيار مطابقة TradingView قابل للقياس
- **الفرع والمستودع:** 775878805Osamaha/TradeLab / test/flutter-all-fixes-20261116.
- **الدمج:** [PR #592](https://github.com/775878805Osamaha/TradeLab/pull/592) **MERGED/squash** SHA [c1bc4179e013f111239b4d2d5308dfb5832a51b1](https://github.com/775878805Osamaha/TradeLab/commit/c1bc4179e013f111239b4d2d5308dfb5832a51b1) من head 017a1cf4996f46af36c739c26de6978f49941810.
- **CI النهائي:** [Actions #44924414254](https://github.com/775878805Osamaha/TradeLab/actions/runs/44924414254) completed/success على HEAD نفسه: Flutter analyze، 320/390dp OHLC/dismissal، كامل chart/Range/Replay/history وتوقيت اليمن. Runs الفاشلة #44923242646 و#44923687526 وتصحيحها محفوظة في السجلات التاريخية، لا حذف.
- **التغييرات:** ChartScreen crosshair sticky long press ثم tap dismissal آمن عبر raw Listener؛ chart_ohlc_inspector_test.dart وchart_paint_only_pan_test.dart يؤكدان السلوك من دون مؤقتات Flutter متبقية. لا تغيير مصدر BID/حساب/التداول الحقيقي.
- **توثيق جديد:** [docs/TRADINGVIEW_PARITY_ACCEPTANCE.md](https://github.com/775878805Osamaha/TradeLab/blob/test/flutter-all-fixes-20261116/docs/TRADINGVIEW_PARITY_ACCEPTANCE.md)، commit [04924a7](https://github.com/775878805Osamaha/TradeLab/commit/04924a77168462ff0d3236f143b84e0e240d6143): مرجع رسمي ومعيار قبول للـUI/Replay/tooling/performance، مع حالة NOT COMPLETE حتى اختبار Android بصريًا وسلوكيًا.
- **الحدود:** Android Profile/FPS والمقارنة البصرية real device والجلسة الحية مع cTrader **NOT RUN**؛ لا APK/Release ولا تعديل main/مشاريع أخرى. توثيق 2026-11-21T16:28:18.728Z.
- **التالي:** إصلاح تجربة الضغط المطول على محور السعر/الوقت في chart_screen.dart مع widget tests، PR/CI/merge جديد إذا نجح.

### 2026-11-21T16:32:10.391Z — إضافة قوائم ضغط مطوّل على محوري السعر والوقت في TradeLab
- **المصدر المرجعي الرسمي:** https://www.tradingview.com/charting-library-docs/latest/mobile_specifics/ (Mobile long-press on price/time scales opens context menu).
- **المستودع/الفرع:** `775878805Osamaha/TradeLab` / `feat/tradelab-mobile-axis-longpress-context-menus-20261121`؛ base dev SHA `9b2977f2bbd47b938836e44e149d6648c5c4fef1`.
- **التغييرات:** [f31fe4c](https://github.com/775878805Osamaha/TradeLab/commit/f31fe4c67b888e1e34895d2748ce5c312d7742ec) ChartScreen axis longpress -> native menu anchored to global touch: السعر AUTO + إعدادات المقاييس، الوقت إعدادات المقاييس + المنطقة الزمنية. يعود إلى صفحات Scale/Symbol الحالية ولا يمس BID/cTrader/Range/Replay أو الحسابات؛ الـcrosshair يبقى plot-only.
- **الاختبارات:** [fbbbb7a](https://github.com/775878805Osamaha/TradeLab/commit/fbbbb7aaac120adf82c192d282c8d91b42536785) و[5984319](https://github.com/775878805Osamaha/TradeLab/commit/59843191c92f2040f31c5d98b037dd9d421911bd) في `flutter_app/test/chart_ohlc_inspector_test.dart` عند 320 و390dp: فحص المحتويات والتنقل وصفحات المقاييس والتوقيت وعدم ظهور OHLC على المحاور وعدم فقدان مصدر التاريخ عند cancel. اختبار mock offline فقط.
- **التوثيق:** `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md` في نفس فرع الإصلاح. **CI PENDING**؛ real Android Profile/FPS, cTrader live, pixel parity NOT RUN؛ لا APK/Release/main/مشاريع أخرى.
- **التالي:** فتح PR إلى dev، تحقق من CI، إصلاح أي فشل، merge squash فقط عند PASS ثم update/verify التقارير برابط run وSHA النهائي.

### 2026-11-21T16:35:56.234Z — نجاح CI ودمج PR #593 لمطابقة قوائم محوري السعر والوقت
- **المستودع/فرع التطوير:** `775878805Osamaha/TradeLab` / `test/flutter-all-fixes-20261116`. [PR #593](https://github.com/775878805Osamaha/TradeLab/pull/593) **MERGED/squash** عند [SHA `797360ff5f87e3ae07b2ba4c874e86c2923910b0`](https://github.com/775878805Osamaha/TradeLab/commit/797360ff5f87e3ae07b2ba4c874e86c2923910b0)، من PR HEAD `341cfd6586bc03d226c8366fbe9d07f0e76ef0fd`.
- **فحص CI:** [GitHub Actions #44925136335](https://github.com/775878805Osamaha/TradeLab/actions/runs/44925136335) **completed/success** على رأس PR، يشمل flutter analyze، widget عند 320 و390dp، chart/Range/Replay/history وتوقيت اليمن. تمت مراجعة حالة الرأس قبل الدمج.
- **الفعل المطبق:** Flutter `ChartScreen.onLongPressStart`: ضغط مطوّل على محور السعر يعرض `AUTO` وإعدادات المقاييس في قائمة سياقية صغيرة؛ وعلى محور الوقت يعرض إعدادات المقاييس والمنطقة الزمنية. العرض يستخدم صفحات Flutter الأصلية ويمنع خلط قوائم المحاور مع OHLC tracking أو بداية Replay. اختبارات إلغاء إعدادات المحور تعود إلى نفس الشارت ومصدر الشموع الحقيقي.
- **الملفات:** `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/test/chart_ohlc_inspector_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`, مع معيار القبول `docs/TRADINGVIEW_PARITY_ACCEPTANCE.md` المنشأ في الدفعة السابقة.
- **الحدود:** Android Profile/FPS، الصور الحقيقية الجانبية، اتصال cTrader حي **NOT RUN**؛ لا APK/Release ولا تعديل `main` أو أي مشروع آخر. لا ادعاء بأن TradeLab أصبح مطابقًا بالكامل بمجرد نجاح CI.
- **الخطوة التالية:** اختبار Android فعلي مقابل مرجع TradingView وتقرير اختلافات screenshot/gesture/latency حقيقية ثم إصلاحها حسب الأولوية.

### 2026-11-21T18:23:24.554Z — PR قيد CI: منع انجراف الشارت أثناء Replay وإغلاق Play عند EOF
- **الفرع:** `775878805Osamaha/TradeLab`/`fix/tradelab-replay-history-viewport-anchor-20261121` من dev SHA `5902a2a780efa3495e8765b2f304ed4df24ae77c`.
- **الدليل من الكود:** Replay يغير `_visibleThrough` دون تعديل `_viewport`، مع أن معادلة `chartX` تعتمد على طول القائمة الظاهرة؛ لذلك يسير الرسم التاريخي يسارًا/يمينًا عمودًا أثناء Play أو seeks، ولو كان المستخدم عند شمعة قديمة. زر Play عند EOF كان ينشئ Timer غير مجدٍ.
- **التنفيذ:** [1c16757](https://github.com/775878805Osamaha/TradeLab/commit/1c167577245f9323379dc7c415bcb4c0f272357f) `chart_viewport.dart` يضيف حساب تثبيت Replay؛ [b7481f9](https://github.com/775878805Osamaha/TradeLab/commit/b7481f964f7ab93465c08a4fa1ed53299e58bb8f) `chart_screen.dart` يطبقه أثناء Seek وAuto Play ويمنع EOF timer؛ [cbdf3e3](https://github.com/775878805Osamaha/TradeLab/commit/cbdf3e39606d6e89d6bcacf6c57ced428b32a7f9) `replay_mobile_controls.dart` يعطل التشغيل بلا شمعة مؤكدة جديدة.
- **الاختبارات:** [67dcbc0](https://github.com/775878805Osamaha/TradeLab/commit/67dcbc0ae928cca2a3dd07f74aa4a513f091d694) `replay_viewport_focus_test.dart` حالات 260/320/390dp وآخر حافة/فراغ/rewind/تاريخ قديم؛ [11f7262](https://github.com/775878805Osamaha/TradeLab/commit/11f7262750d1c0e78c890674e63dad1fa284b473) `replay_mobile_controls_test.dart` disable عند EOF مع إبقاء pause ممكنًا.
- **الحالة:** Flutter CI PENDING، Android device/Profile/FPS وcTrader live NOT RUN، لا APK/Release/main. لا تغييرات خارج TradeLab.
- **التالي:** PR إلى `test/flutter-all-fixes-20261116`، فحص CI SUCCESS، دمج squash ثم حفظ SHA وCI الرابطين وتحديث handoff.

### 2026-11-21T18:27:33.537Z — نجاح CI ودمج PR #594 لتثبيت مواضع شموع Replay عند التقدم والرجوع
- **المستودع/الفرع:** `775878805Osamaha/TradeLab` / `test/flutter-all-fixes-20261116`. [PR #594](https://github.com/775878805Osamaha/TradeLab/pull/594) **MERGED/squash** عند commit [`b7826311823884245ddf44bd4b74f1c6fb1f1278`](https://github.com/775878805Osamaha/TradeLab/commit/b7826311823884245ddf44bd4b74f1c6fb1f1278).
- **التحقق المؤكد:** [GitHub Actions #44935284854](https://github.com/775878805Osamaha/TradeLab/actions/runs/44935284854) **completed/success** على PR HEAD `fcfe049df9e1163a85c0610616857f76a1239ce7`: اجتاز Flutter analyze، اختبار market history/chart/Range/Replay وYemen timezone، بما فيها اختبار Replay viewport عند 260/320/390dp وwidget controls عند 320/390dp.
- **السلوك:** `ChartViewport.afterReplayVisibleCountChange` يحتفظ بمكان الشمعة المصدر أثناء كشف/إزالة بادئة Replay، وتستخدمه `ChartScreen._seekReplay` و`_togglePlay`; عند حذف المصدر بسبب rewind كبير يعود المستخدم لآخر بار حقيقي. `_togglePlay` لا ينشئ timer عند نهاية بيانات Replay، ويعطّل `ReplayMobileControls` زر Play عند EOF مع بقاء Pause حين يكون قيد التشغيل.
- **الملفات:** `flutter_app/lib/chart/chart_viewport.dart`, `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/lib/replay/replay_mobile_controls.dart`, `flutter_app/test/replay_viewport_focus_test.dart`, `flutter_app/test/replay_mobile_controls_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`. تحديث معيار المطابقة `docs/TRADINGVIEW_PARITY_ACCEPTANCE.md` بالنتيجة.
- **ما لم يختبر:** Android real touch/Profile/FPS، لقطة pixel parity بمرجع TradingView، وcTrader live **NOT RUN**. لم يُبن APK ولم يُنشر Release، ولم يُعدل main/مشاريع أخرى.
- **الخطوة التنفيذية التالية:** مقارنة فعلية على Android بنسخة اختبار مأذون بها وتقرير اختلافات gesture, Replay, latency، ثم إصلاح أكبر اختلاف مؤكد قبل إعلان مطابقة كاملة.
