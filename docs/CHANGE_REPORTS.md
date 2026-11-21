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
