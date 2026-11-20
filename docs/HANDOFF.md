# TradeLab — ملف استكمال العمل من أي محادثة

## توحيد تاريخ الشموع الزمنية إلى 200 ألف — PR قيد الاختبار
- فرع `feat/market-candle-200k-history-budget-20261121` من التطوير `3bfd3e806202f682c32b7e8145a87a7e14086315`. لا APK/Release، ولا تعديل `main`.
- `MarketCandleStore.read`/`mergeVerified`: رفع السقف الافتراضي من 100k إلى **200k** شمعة زمنية موثقة مع عدم قص التاريخ الأقدم عند إعادة فتح رمز cTrader؛ `CTraderCandleStitcher` والـsnapshot يستخدمان السقف المشترك.
- `OlderCandlePrepend` يرفض تجاوز 200k قبل تخصيص القوائم ومحاور الرسم؛ أرشيف SQLite يبقى مستقلًا ويحفظ التاريخ الحقيقي خارج نافذة الذاكرة. هذا ليس تحميل تاريخ غير محدود في RAM.
- 4 اختبارات إضافية لأرشيف 120001، والحد 200k+، ورفض تجاوز العرض. **CI: PENDING**؛ اختبار الهاتف/قياس FPS **NOT RUN**.
- **التالي:** افتح PR، راجع Flutter/SQLite/Range/Replay، ادمج فرع التطوير فقط عند PASS واحفظ CI/SHA الفعلي.

## دفعة تطوير ناجحة ومدمجة — PR #570: تحميل BID متوازن وآمن
- [PR #570](https://github.com/775878805Osamaha/TradeLab/pull/570) **MERGED** إلى فرع التطوير، commit `7f68458a69e51817f2b396bb5bf74bdb41460d9d`. تطوير cTrader BID بتوزيع العاملين مع بقاء حدّ الطلبات، مصدر الحساب، وأحداث نفس المللي ثانية.
- [Actions #44826685592](https://github.com/775878805Osamaha/TradeLab/actions/runs/44826685592) **PASS / completed / success**: تحليل Flutter، اختبارات BID والتاريخ/Range/Replay وتوقيت اليمن. Android Profile وFPS على هاتف **NOT RUN**.
- **APK:** النسخة التجريبية المنشورة مسبقًا لا تحتوي #567–#570. لا APK جديد ولا تغيير `main`.
- **التالي:** استكمال توحيد حدود ذاكرة تاريخ شموع الوقت الطويل محليًا، مع اختبارات منع تجاوز السقف، ثم اختبارات Android فعلية عند توفر جهاز.

## اكتمال حماية الذاكرة وتحميل Range — PR #569
- **MERGED:** [PR #569](https://github.com/775878805Osamaha/TradeLab/pull/569)، SHA [b7ee472](https://github.com/775878805Osamaha/TradeLab/commit/b7ee47267bfd039c2705e07587fcca1de33ceab1) في `test/flutter-all-fixes-20261116`.
- **اختبارات ناجحة:** [Actions #44817561584](https://github.com/775878805Osamaha/TradeLab/actions/runs/44817561584) = **SUCCESS**؛ تحليل Dart/Flutter، اختبارات مصدر BID وRange/Replay وتوقيت اليمن كلها نجحت. Android Profile/FPS **NOT RUN**.
- سقف مصدر BID `1,000,000` تيك وسقف Range `250,000` شمعة مغلقة لكل بناء. يمنع النظام تجاوز السقف قبل نسخ الأرشيف إلى worker، ويرفض تجاوز عدد شموع Range دون نشر Replay مجتزأ. ينطبق ذلك على البناء المباشر والخلفي وإضافة التاريخ الأقدم.
- هذه الحزمة تكمل [PR #568](https://github.com/775878805Osamaha/TradeLab/pull/568) الذي نفّذ خمسة تحسينات مصدر وخمسة ملفات اختبار للتحميل والأداء والتاريخ.
- **الأحدث على GitHub ليس في APK السابق**؛ لا APK جديد دون طلب صريح. `main` وبقية المشاريع دون تغيير.
- **الخطوة التالية:** اختبار السلاسة على Android Profile فعلي، ثم معالجة أول اختناق بأرقام p50/p95/p99 من جهاز.

## دفعة تطوير كبيرة مكتملة — PR #568
- **MERGED:** [PR #568](https://github.com/775878805Osamaha/TradeLab/pull/568) إلى `test/flutter-all-fixes-20261116`، SHA الفعلي [db9c2cf](https://github.com/775878805Osamaha/TradeLab/commit/db9c2cfa02bef9fea5f6f1a7f76e23140404e9b8).
- **نجحت الاختبارات:** [Actions #44816709629](https://github.com/775878805Osamaha/TradeLab/actions/runs/44816709629) = **SUCCESS** لتحليل Flutter ودورات Range/Replay/الشارت وYemen timezone؛ هذه نتائج آلية وليست قياسات FPS حقيقية.
- **خمسة تحسينات مصدر + خمسة ملفات اختبار:** تحديث cTrader المغلق O(log N) بدل تكرار مسح 120k شمعة، إيقاف إنشاء محاور جديدة عند عدم وجود close جديد، Range BID rollforward O(log N) للتيكات المهملة، التحقق من حد cursor للأقدم، والتحقق من ترتيب BID المتصاعد لحماية Replay. احتفظ بـsame-ms BID والحد الآمن للذاكرة وسلامة الشموع المصدرية.
- **APK:** النسخة التجريبية المنشورة قبل هذه الحزمة ما تزال هي الأحدث المتاحة للتثبيت؛ لا تحتوي تحسينات #567 و#568. لا تنشئ APK جديدًا دون طلب.
- **التكملة التالية:** حماية عدد شموع Range الكلي من الزيادة غير المحدودة عند قفزات BID موثقة، واختبار تحميل 120k+ وتجميد الرسم على أجهزة فعلية لاحقًا. لا تعديل `main`.

## أحدث إصلاح مدمج — PR #567 (20 نوفمبر 2026)
- [PR #567](https://github.com/775878805Osamaha/TradeLab/pull/567) **MERGED** إلى `test/flutter-all-fixes-20261116` عند [commit 68169f9](https://github.com/775878805Osamaha/TradeLab/commit/68169f92627c40983c195872bf50c9836f8eff36).
- `OlderCandlePrepend.prepare`: رفض تضارب open/high/low/close إذا أعاد المزود شمعة بنفس وقت مصدر موجود، بدلاً من تجاهلها بصمت. بحث ثنائي في الأرشيف الموثق، دون تبديل الأسعار أو ملء فجوات التاريخ أو كشف شموع Replay المستقبلية. اختبارات الحالة الحدية والتعارض الداخلي وأرشيف 120 ألف شمعة.
- [GitHub Actions #44814969933](https://github.com/775878805Osamaha/TradeLab/actions/runs/44814969933): **PASS** لتحليل Flutter وجميع الاختبارات المطلوبة ومنها Range وReplay والتوقيت المحلي. Android FPS/اختبار جهاز حقيقي **NOT RUN**.
- **تنبيه الإصدار:** أحدث APK المثبت/المنشور أقدم من هذا الإصلاح، ولا يتضمن PR #567. لا APK جديد ولا تعديل `main` وفق طلب الاستمرار في التطوير.
- **التالي:** مراجعة نتائج اختبار APK اليدوي على Android وإصلاح أي مشكلة مثبتة؛ أو متابعة اختبار سلامة تاريخ Range/Replay تحت ضغط 100k+ من بيانات حقيقية، مع توثيق كل تغيير.

## أحدث APK قابل للتثبيت — 20 نوفمبر 2026
- **الحالة: جاهز للتحميل والتجربة اليدوية**. [تحميل TradeLab Android Test APK](https://github.com/775878805Osamaha/TradeLab/releases/download/tradelab-phone-test-6cecd765d1c2/TradeLab-Android-Test.apk)، 59,096,319 بايت، [GitHub Release](https://github.com/775878805Osamaha/TradeLab/releases/tag/tradelab-phone-test-6cecd765d1c2).
- مصدر البناء `6cecd765d1c29b3e9e460d18fe2ffaf8269ed494` على `test/tradelab-phone-apk-20261120`، مشتق من أحدث فرع التطوير عند `03794ca53590accb7ae777d5889bd72f5c66a90f` بعد دمج PR #565؛ لم يُعدَّل `main`.
- [Actions #44803312522](https://github.com/775878805Osamaha/TradeLab/actions/runs/44803312522): **SUCCESS** لاختبارات Flutter وتجميع APK وفحص التوقيع. الحزمة `com.example.tradelab_flutter.test2`، موقعة توقيعًا تجريبيًا مؤقتًا؛ قد يتطلب تثبيتُها إزالة نسخة Test 2 القديمة إذا اختلفت بصمة الشهادة، دون المساس بالتطبيق الأساسي.
- [PR #566](https://github.com/775878805Osamaha/TradeLab/pull/566) أُغلق دون دمج؛ workflow الخاص بالبناء أحادي الاستعمال معزول عن التطوير. انتهى تفويض البناء الواحد؛ لا إنشاء جديد دون طلب صريح.
- **لم يُثبت نجاحه على الهاتف بعد**، ولا قياسات Android Profile أو اختبار اتصال حساب cTrader، وهذه الخطوة التالية الوحيدة.


> **ابدأ من هنا** عند فتح محادثة أخرى. آخر مراجعة للحالة: **2026-11-20 UTC**. هذا **ملخص مؤرّخ** وليس ادعاءً بأن SHA ما زال آخر ما في GitHub؛ تحقق من الفرع وملفات المشروع مباشرة قبل أي تعديل.

## أين نعمل وما آخر دليل؟
- فرع العمل المعتمد: `test/flutter-all-fixes-20261116`. مصدر الحالة المؤكد قبل إضافة ملفات التسليم: [commit 7fa9fd4](https://github.com/775878805Osamaha/TradeLab/commit/7fa9fd4ceabb6e878b9d6a80c818349b63ee2a76).
- آخر إصلاح **مدمج في التطوير**: [PR #563](https://github.com/775878805Osamaha/TradeLab/pull/563) — إعادة استخدام أعلى/أدنى OHLC المرئيين.
- **إصلاح سابق مدمج:** [PR #564](https://github.com/775878805Osamaha/TradeLab/pull/564) — حماية `revealHistoricalBar` في Replay و`remapHistoricalAnchor` في Range من هندسة viewport غير صالحة، مع اختبارين جديدين. دمج في فرع التطوير بتاريخ `2026-11-20T19:01:01Z` عند [SHA `8eb8451`](https://github.com/775878805Osamaha/TradeLab/commit/8eb845120de323788e2ec819719209249fa27093).
- **آخر فحص ناجح موثق:** [Actions #44797725643](https://github.com/775878805Osamaha/TradeLab/actions/runs/44797725643) = **SUCCESS** لفحص Flutter وتحليل Dart واختبارات الشارت/Range/Replay قبل الدمج؛ إلغاء المحاولتين السابقتين ناتج عن تحديثات PR لا عن فشل اختبارات. لم يُقَس FPS على هاتف.
- آخر فحص **بعد الدمج**: [Actions #44791818293](https://github.com/775878805Osamaha/TradeLab/actions/runs/44791818293)؛ نجح **563 اختبار Flutter + 7 اختبارات توقيت اليمن**. لا يعني ذلك قياس FPS على هاتف.
- أعمال حديثة مرتبطة: [#562](https://github.com/775878805Osamaha/TradeLab/pull/562) تحسين تدرجات المحور وتنسيق السعر؛ [#561](https://github.com/775878805Osamaha/TradeLab/pull/561) ذاكرة حساب نطاق السعر؛ [#559](https://github.com/775878805Osamaha/TradeLab/pull/559) و[#560](https://github.com/775878805Osamaha/TradeLab/pull/560) قياس الإطارات حسب الإيماءة وحركة السحب؛ [#557](https://github.com/775878805Osamaha/TradeLab/pull/557) و[#558](https://github.com/775878805Osamaha/TradeLab/pull/558) كاش BID.
- `main` عند المراجعة: `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`، **لا تنقل تطوير Flutter إليه دون طلب صريح**.
- الوضع: التطبيق **قيد التطوير**؛ لا اعتماد نهائي للتثبيت على Android. لا تُنشئ APK أو Release أثناء التطوير؛ هذا طلب صريح مستمر.

- **آخر إصلاح مدمج:** [PR #565](https://github.com/775878805Osamaha/TradeLab/pull/565)، SHA [62949ec](https://github.com/775878805Osamaha/TradeLab/commit/62949ec1f29af9aa94869f8a8574a54706cbae5c) — معالجة الانقطاع غير الصالح أثناء التكبير بإصبعين، وإعادة ضبط أصل pinch من الشارت الحالي، وتجاهل أول انتقال إلى إصبع واحد؛ اختبارات انحدار جديدة.
- **آخر CI ناجح:** [Actions #44800109737](https://github.com/775878805Osamaha/TradeLab/actions/runs/44800109737) على رأس PR النهائي `8b92dbe33fc99cf1ee2233be4a5c49989656dc29` — **PASS** في Flutter analyze واختبارات الشارت/Range/Replay والتوقيت. لا قياس Android FPS حتى الآن.

## القيود التي يجب عدم تغييرها
- XAUUSD والـForex عبر cTrader، والكريبتو عبر Binance؛ لا تُنشئ أسعار أو شموع وهمية، ولا تكشف بيانات Replay المستقبلية.
- التداول ورقي/تدريبي فقط؛ لا فتح صفقات بأموال حقيقية.
- لا APK جديد تلقائيًا؛ تم بناء نسخة اختبار واحدة بطلب صريح بتاريخ 2026-11-20، وأي بناء لاحق يحتاج طلبًا جديدًا. اترك `main` دون تغيير.
- لا ادعاء بنجاح اختبار جهاز حقيقي اعتمادًا على CI وحده.

## آخر دفعة تطوير مكتملة — استعادة اللمس أثناء التكبير
- [PR #565](https://github.com/775878805Osamaha/TradeLab/pull/565) **MERGED** إلى فرع التطوير، SHA الفعلي `62949ec1f29af9aa94869f8a8574a54706cbae5c`.
- `ChartTouchGesture.update`: في حالة إحداثيات Android غير صالحة أثناء pinch نشط، تبقى الشموع بمكانها، ويُلغى أصل pinch القديم فقط؛ أول عينة صالحة لاحقة تصبح أصلًا جديدًا. عند إزالة إصبع مباشرة بعد انقطاع العينة، يُتجاهل أول فرق مركز وهمي بدل القفز في الشارت.
- تمت إضافة اختباري انحدار ومراجعة مسارات رفع الإصبع واستئناف حركة السحب؛ [CI #44800109737](https://github.com/775878805Osamaha/TradeLab/actions/runs/44800109737) **PASS** قبل الدمج. Android Profile **NOT RUN**.
- الخطوة التالية: قياس pan/pinch/momentum على جهاز فعلي فقط، وتوثيق p50/p95/p99 قبل وصف التحسن بكونه FPS محسّنًا.

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