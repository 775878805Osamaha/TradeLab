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
