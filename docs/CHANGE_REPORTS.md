# TradeLab — سجل تقارير التطوير في GitHub

> سجل تراكمي لا تُحذف منه الإدخالات القديمة. بعد كل تعديل/رفع/دمج/تشغيل فحص، اكتب حدثًا بالحقول الإلزامية، وحدّث [HANDOFF.md](HANDOFF.md). تبقى النتائج المعلقة موسومة PENDING حتى تثبت نتيجة GitHub.

**قالب الحدث:** تاريخ UTC | الحدث/النتيجة | الفرع وSHA قبل/بعد | PR/CI/روابط | الملفات المتغيرة | ما تحقق بالفعل | ما لم يتحقق/المخاطر | الخطوة التالية.

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
