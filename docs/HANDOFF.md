# TradeLab — ملف استكمال العمل من أي محادثة

> **ابدأ من هنا** عند فتح محادثة أخرى. آخر مراجعة للحالة: **2026-11-20 UTC**. هذا **ملخص مؤرّخ** وليس ادعاءً بأن SHA ما زال آخر ما في GitHub؛ تحقق من الفرع وملفات المشروع مباشرة قبل أي تعديل.

## أين نعمل وما آخر دليل؟
- فرع العمل المعتمد: `test/flutter-all-fixes-20261116`. مصدر الحالة المؤكد قبل إضافة ملفات التسليم: [commit 7fa9fd4](https://github.com/775878805Osamaha/TradeLab/commit/7fa9fd4ceabb6e878b9d6a80c818349b63ee2a76).
- آخر إصلاح **مدمج في التطوير**: [PR #563](https://github.com/775878805Osamaha/TradeLab/pull/563) — إعادة استخدام أعلى/أدنى OHLC المرئيين.
- **آخر إصلاح مدمج:** [PR #564](https://github.com/775878805Osamaha/TradeLab/pull/564) — حماية `revealHistoricalBar` في Replay و`remapHistoricalAnchor` في Range من هندسة viewport غير صالحة، مع اختبارين جديدين. دمج في فرع التطوير بتاريخ `2026-11-20T19:01:01Z` عند [SHA `8eb8451`](https://github.com/775878805Osamaha/TradeLab/commit/8eb845120de323788e2ec819719209249fa27093).
- **آخر فحص ناجح موثق:** [Actions #44797725643](https://github.com/775878805Osamaha/TradeLab/actions/runs/44797725643) = **SUCCESS** لفحص Flutter وتحليل Dart واختبارات الشارت/Range/Replay قبل الدمج؛ إلغاء المحاولتين السابقتين ناتج عن تحديثات PR لا عن فشل اختبارات. لم يُقَس FPS على هاتف.
- آخر فحص **بعد الدمج**: [Actions #44791818293](https://github.com/775878805Osamaha/TradeLab/actions/runs/44791818293)؛ نجح **563 اختبار Flutter + 7 اختبارات توقيت اليمن**. لا يعني ذلك قياس FPS على هاتف.
- أعمال حديثة مرتبطة: [#562](https://github.com/775878805Osamaha/TradeLab/pull/562) تحسين تدرجات المحور وتنسيق السعر؛ [#561](https://github.com/775878805Osamaha/TradeLab/pull/561) ذاكرة حساب نطاق السعر؛ [#559](https://github.com/775878805Osamaha/TradeLab/pull/559) و[#560](https://github.com/775878805Osamaha/TradeLab/pull/560) قياس الإطارات حسب الإيماءة وحركة السحب؛ [#557](https://github.com/775878805Osamaha/TradeLab/pull/557) و[#558](https://github.com/775878805Osamaha/TradeLab/pull/558) كاش BID.
- `main` عند المراجعة: `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`، **لا تنقل تطوير Flutter إليه دون طلب صريح**.
- الوضع: التطبيق **قيد التطوير**؛ لا اعتماد نهائي للتثبيت على Android. لا تُنشئ APK أو Release أثناء التطوير؛ هذا طلب صريح مستمر.

## القيود التي يجب عدم تغييرها
- XAUUSD والـForex عبر cTrader، والكريبتو عبر Binance؛ لا تُنشئ أسعار أو شموع وهمية، ولا تكشف بيانات Replay المستقبلية.
- التداول ورقي/تدريبي فقط؛ لا فتح صفقات بأموال حقيقية.
- لا APK أو Release حتى يكتمل التطبيق ويطلب المستخدم ذلك؛ اترك `main` دون تغيير.
- لا ادعاء بنجاح اختبار جهاز حقيقي اعتمادًا على CI وحده.

## مهمة الاستكمال الفورية
1. على جهاز Android فعلي، شغّل جلسة **Profile** مع `--dart-define=TRADELAB_PROFILE_CHART=true` لقياس p50/p95/p99 لإيماءات pan وpinch وmomentum؛ لم تنفذ هذه الخطوة بعد.
2. إن ظهر اختناق مثبت، أصلحه في PR صغير لفرع التطوير، شغّل اختبارات بدون APK، ودوّن نتيجة CI/الدمج في `docs/CHANGE_REPORTS.md`. لا توجّه أي تغييرات إلى `main`.

## آخر ما ينبغي تنفيذه
1. قياس p50/p95/p99 لعمليات السحب والتكبير وحركة القصور باستخدام `TRADELAB_PROFILE_CHART=true` في Android Profile على جهاز فعلي؛ هذه القياسات **لم تُنفّذ** بعد.
2. اختبار تاريخ Range الطويل من تيكات BID الحقيقية عبر cTrader، وترتيب تيكات المللي ثانية نفسها، وحدود Replay، وسلامة الرسم والذاكرة تحت الضغط.
3. إصلاح أي اختناق مثبت، اختبارات Flutter وCI، ثم تسجيل كل رفع/PR/دمج وفق `AGENTS.md`. لا تتظاهر بتحقيق مطابقة TradingView من دون مقارنة فعلية.

## كيف يستمر وكيل جديد؟
1. اقرأ [AGENTS.md](../AGENTS.md) و[CHANGE_REPORTS.md](CHANGE_REPORTS.md)، ثم اجلب آخر HEAD وPRs وCI من GitHub.
2. لا تسأل المستخدم عن المشروع/الفرع/المتطلبات الموجودة هنا؛ افحص الكود الفعلي وابدأ بأول إجراء موثق غير مكتمل.
3. نفّذ تعديلًا محددًا واختبره. أضف تقرير تغيير إلى السجل، وحدّث هذه الصفحة، واحفظهما في GitHub **مع التعديل نفسه أو مباشرة بعده**. بعد الدمج سجّل SHA الحقيقي ونتيجة CI.

## روابط مشاريع المستخدم الأخرى
- [TradeLab](https://github.com/775878805Osamaha/TradeLab/blob/test/flutter-all-fixes-20261116/docs/HANDOFF.md)
- [OMX ERP](https://github.com/775878805Osamaha/omx-erp/blob/main/docs/HANDOFF.md)
- [OMEX Store](https://github.com/775878805Osamaha/omex-mobile-app/blob/main/docs/HANDOFF.md)

**ملاحظة:** هذا الملف وسجل الأحداث مجرد توثيق لاستكمال العمل، ولا يثبت جاهزية المنتج أو تشغيله على الهاتف.