# TradeLab — ملف استكمال العمل من أي محادثة

## دفعة مكتملة — PR #584: منع قفزة الشارت عند أول pinch فاسد (21 نوفمبر 2026)
- **المستودع والفرع:** `775878805Osamaha/TradeLab` / `fix/tradelab-first-invalid-pinch-lift-20261121` من رأس فرع التطوير `8d9cb0141f2431bd310555eb2b870fdf68c86dd6` بعد دمج PR #583. كود [f6b0ac9](https://github.com/775878805Osamaha/TradeLab/commit/f6b0ac9219916fd6ba4fe3bb69dfad4b08ea4d34)، اختبار [712a06d](https://github.com/775878805Osamaha/TradeLab/commit/712a06d8f015ee1e083e7a4de043a6a634246ba8).
- **الخلل المثبت من الكود:** `ChartTouchGesture.update` عندما تصل أول عينة pointerCount>1 بمركز NaN أو scale غير صالح، كانت تتجاهلها ولكن تبقي `_pinching=false`. إذا سحب المستخدم الإصبع الثاني فورًا تأتي أول عينة بإصبع واحد و`deltaX` ناتج عن تحول مركز الإصبعين؛ تُعامل خطأً كسحب فعلي، ويمكن قفز viewport.
- **الإصلاح:** على أول عينة متعددة الأصابع غير صالحة نعيّن `_pinching=true` رغم إلغاء `_pinchOrigin`؛ يعيد أول قياس صحيح للإصبعين ضبط المصدر الحالي، بينما تُتجاهل أول حركة بعد الرفع حتى لو لم تصل أي عينة pinch صحيحة. لا تعديل حساب المصدر أو الأسعار أو Replay.
- **اختبارات الانحدار:** `flutter_app/test/chart_viewport_test.dart` يغطي invalid initial NaN/Infinity/zero scale ثم الرفع مع `deltaX=175px`، والتأكد من ثبات scroll/zoom ومنع حساب travel الوهمي، واستعادة السحب الطبيعي؛ ويختبر إعادة دخول pinch وتثبيت focal جديد وعدم استخدام origin قديم.
- **الملفات:** `flutter_app/lib/chart/chart_viewport.dart`, `flutter_app/test/chart_viewport_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **النتيجة الفعلية:** [PR #584](https://github.com/775878805Osamaha/TradeLab/pull/584) **MERGED/squash** إلى `test/flutter-all-fixes-20261116` عند [SHA d88107c6](https://github.com/775878805Osamaha/TradeLab/commit/d88107c62dd461c72dc8051dcfbde130be3c4094). [GitHub Actions #44914776406](https://github.com/775878805Osamaha/TradeLab/actions/runs/44914776406) = **completed/success** على PR HEAD `9b23a72359e9ed060e4f3572ef85a4874d55ca9a`، بما يشمل Flutter analyze واختبارات التاريخ/Range/Replay/chart وتوقيت اليمن. Android Profile وFPS حقيقي **NOT RUN**؛ لا APK/Release ولا تغيير main/المشاريع الأخرى.
- **الخطوة التالية الوحيدة:** فحص على Android فعلي لجودة انتقالات الأصابع وسلاسة pinch/pan مع قياسات Profile p50/p95/p99، ثم استهداف أي اختناق مثبت دون إنشاء APK تلقائيًا.

## دفعة مكتملة — PR #583: تحليل تأخير Range الحي بمراحل منفصلة (21 نوفمبر 2026)
- **فرع التنفيذ:** `feat/tradelab-live-range-phase-profile-20261121` من التطوير عند `356bc85fd1c1c529e457d26cf266149f9bcd45ba` (بعد دمج PR #582)، مع الشيفرة حتى [4de5ab8](https://github.com/775878805Osamaha/TradeLab/commit/4de5ab87227e7d951f0917549af1b6d08a4db82e).
- **الخلل المعرفي من المصدر:** `ChartScreen._refreshLiveRange` كان يسجّل زمن كامل التحديث الناجح فقط في `liveRangeUpdate` ويستبعد جميع الصفحات التي لم تضف تيكات. بذلك لا يمكن تمييز انتظار cTrader عن تحقق BID وإعادة بناء Range في Profile، وتتجاهل القياسات العمليات الناجحة بلا تغيير.
- **التحسين الفعلي:** أضفنا مراحل `liveRangeBrokerFetch`, `liveRangeVerify`, `liveRangeAppend`, `liveRangeNoChange` إلى مجمع الأوقات، مع إبقاء `liveRangeUpdate` لزمن التحديث الكامل الناجح. كل مرحلة مُقيّدة بهوية الشارت الصالحة بعد `await`، ولا تنشر أسعارًا أو رمزًا أو معرّف حساب أو زمن تيك. لا تنفذ أدوات Stopwatch/logging في البناء الطبيعي دون `TRADELAB_PROFILE_CHART=true`.
- **الاختبار:** `chart_load_profiler_test.dart` يختبر عزل p95 لكل مرحلة والتحديث بلا تغيير، عدم إدخال network wait في append p95، وتجنب أسماء الرموز والحسابات في التقارير.
- **الملفات:** `flutter_app/lib/chart/chart_load_profiler.dart`, `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/test/chart_load_profiler_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **نتيجة ثابتة:** [PR #583](https://github.com/775878805Osamaha/TradeLab/pull/583) **MERGED/squash** إلى التطوير عند [SHA b5b8271a](https://github.com/775878805Osamaha/TradeLab/commit/b5b8271a0b07ea9bc046c000e96dfbc428a29fe0). [Actions #44910151843](https://github.com/775878805Osamaha/TradeLab/actions/runs/44910151843) **completed/success** (Flutter analyze واختبارات التاريخ/Range/Replay/chart وتوقيت اليمن) على PR HEAD `e410978bcf08feac21038b59622062b925ed541a`. **Android Profile/FPS وcTrader live NOT RUN**. لا APK/Release أو تغيير `main`.
- **الخطوة التالية الواحدة:** تشغيل Android Profile على جهاز فعلي بحساب cTrader لاستخراج p50/p95/p99 لمراحل network/verify/append وربطها بفترات بطء pan/pinch الفعلية قبل أي إصلاح أداء إضافي.

## دفعة مكتملة — PR #582: حد ذاكرة الشموع أثناء بناء Range (21 نوفمبر 2026)
- **الفرع:** `fix/tradelab-range-early-bar-budget-20261121` مشتق من فرع التطوير `test/flutter-all-fixes-20261116` عند `8596fdac966d38a73d3bb3e57704ce0c366af384` بعد دمج PR #581. آخر commit للاختبارات [a6e4486](https://github.com/775878805Osamaha/TradeLab/commit/a6e4486f46eb119165be2f0c6bb50d3314d43af0).
- **سبب التعديل من مراجعة الشيفرة:** `RangeBarTimeline.build` و`_appendVerifiedRangeWorker` كانا يفحصان `closedBarLimit` **بعد** قيام `RangeBarBuilder.appendBidTick` بتوليد حتى 100,000 شمعة لقفزة BID واحدة. مع بقاء شمعة واحدة في حد الذاكرة كان يمكن إنشاء آلاف الشموع المؤقتة قبل رفض العملية.
- **تنفيذ فعلي:** `RangeBarBuilder.appendBidTick(price, maxNewClosedBars: remaining)` يراجع الحد قبل إنشاء **كل شمعة**؛ `RangeBarBudgetExceeded` يُحوّل إلى `MarketDataException` برسالة Range التاريخية/الحية المعروفة؛ نتيجة العامل الجزئية تُرفض ولا تنشر بيانات ناقصة إلى الرسم أو Replay. هذا يحافظ على ترتيب تيكات BID الحقيقي ويتيح تحديث الشمعة المتكوّنة فقط عندما يكون حد الإغلاق ممتلئًا. `maxBarsPerSingleTick` السابق باقٍ.
- **الاختبارات المضافة:** ثلاث حالات لمولد Range (قفزة 50k بميزانية صغيرة، صفر مساحة للشموع المغلقة، تطابق تسلسل الإغلاق)، وثلاث حالات للتاريخ وLive Range (رفض قفزة 40k، عدم تغيير snapshot القديمة، إلحاق تحديث للشّمعة المتكوّنة عند الحد).
- **الملفات:** `flutter_app/lib/data/range_bar_builder.dart`, `flutter_app/lib/data/range_bar_timeline.dart`, `flutter_app/test/range_bar_builder_test.dart`, `flutter_app/test/range_bar_timeline_test.dart`, وملفا التسليم.
- **نتيجة مؤكدة:** [PR #582](https://github.com/775878805Osamaha/TradeLab/pull/582) **MERGED/squash** إلى فرع التطوير عند [SHA a18c6383](https://github.com/775878805Osamaha/TradeLab/commit/a18c6383e2cc88b882ca483b5bfcf6c32e92ff20). [Actions #44909751279](https://github.com/775878805Osamaha/TradeLab/actions/runs/44909751279) = **completed/success** للرأس `323e4d32e660453d9161d624beae85d708a93ba7`، وتضم تحليل Flutter واختبارات التاريخ/Range/Replay/chart وتوقيت اليمن. Android Profile/FPS وجلسة cTrader حية **NOT RUN**. لا APK أو Release أو تغيير `main`.
- **الخطوة التالية الواحدة:** إجراء Android Profile حقيقي على حساب cTrader لقياس p50/p95/p99 من لمس الشارت وتحديث Range، ثم معالجة الاختناق المثبت مع الحفاظ على قيود المصدر/Replay. لا APK تلقائيًا.

## دفعة مكتملة — PR #581: حماية حدود مصدر BID وشمعة Range (21 نوفمبر 2026)
- **الفرع:** `fix/tradelab-range-snapshot-boundary-20261121` من التطوير `test/flutter-all-fixes-20261116` عند `358f38532a7347fef92172935c2d465a85b7195b`؛ آخر commit للشيفرة والاختبار [6122183](https://github.com/775878805Osamaha/TradeLab/commit/6122183d0ae425582c21e36af6b527389b233657) قبل تحديث التوثيق.
- **الإصلاح:** `RangeBarTimeline.appendVerifiedSuffixAsync` يرفض الآن اللقطة غير المطابقة عندما يختلف سعر BID الأول/الأخير أو تاريخ أول حدث إغلاق، حتى لو تطابق عدد تيكات المصدر وآخر طابع UTC؛ الفحص ثابت الزمن لا يمسح مليون تيك. `ChartScreen._refreshLiveRange` يسقط نتيجة polling قديمة إذا تغير مضاعف نقطة cTrader أثناء انتظار الشبكة أو عامل Range، منعًا لدمج شموع بمسافة سعرية مختلفة.
- **الانحدار:** `range_bar_timeline_test.dart` يغطي أول سعر مختلف، وآخر سعر مختلف، وزمن إغلاق أول شمعة مختلف، ونجاح إلحاق BID موثق صحيح دون تغيير timeline السابقة.
- **النتيجة:** [PR #581](https://github.com/775878805Osamaha/TradeLab/pull/581) **MERGED/squash** إلى فرع التطوير عند [SHA 9a8997f9](https://github.com/775878805Osamaha/TradeLab/commit/9a8997f92905e77ca28ea9acb371406e2f037de4). [GitHub Actions #44908442478](https://github.com/775878805Osamaha/TradeLab/actions/runs/44908442478) = **completed/success**: Flutter analyze واختبارات التاريخ والشارت وRange وReplay وتوقيت اليمن. **Android Profile وحساب cTrader حي NOT RUN**، ولا ادعاء بقياس FPS.
- **الملفات:** `flutter_app/lib/data/range_bar_timeline.dart`, `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/test/range_bar_timeline_test.dart`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`.
- **الحدود:** دون تغييرات `main`، لا APK/Release ولا مصادر أسعار جديدة ولا تداول حقيقي.
- **الخطوة التالية الوحيدة:** قياس Android Profile على جهاز فعلي بحساب cTrader واستخراج p50/p95/p99 للشارت/Range/Replay ثم معالجة أول اختناق موثق دون APK تلقائيًا.

## دفعة مكتملة — PR #580: عامل واحد للتحقق من صفحة BID الحية
- **MERGED:** [PR #580](https://github.com/775878805Osamaha/TradeLab/pull/580) إلى `test/flutter-all-fixes-20261116` عند SHA [b2c323e](https://github.com/775878805Osamaha/TradeLab/commit/b2c323eeb2a4d110176bdb92a15371d859c0c53c).
- **CI:** [GitHub Actions #44845266471](https://github.com/775878805Osamaha/TradeLab/actions/runs/44845266471) **PASS / completed / success**؛ Flutter analyze واختبارات Range/Replay/chart وتوقيت اليمن.
- **التحسين:** صفحات cTrader BID الكبيرة (5000+ تيك) كانت تخضع لعمليتي `compute` متتاليتين، تنقلان نفس صفحة الوسيط لفحص ترتيبها/أسعارها أولًا ثم مقارنة أحداث المللي ثانية الأخيرة ثانيًا. الآن `RangeLiveBidDelta._verifyAndExtractLiveSuffix` يتحقق من ترتيب وتوقيت وسلامة الصفحة كاملة ويطابق حدود BID في **عامل واحد**، بينما الصفحات الأصغر تنفّذ دون عامل. يحتفظ بتحسين PR #579 بنقل ذيل الـBID فقط بدل مليون تيك.
- **الاختبارات:** 4999، 5000، 6501 أحداث لتغطية كلا المسارين، و5000+ تيك بخطأ في ترتيب الزمن/تجاوز آخر زمن/سعر سالب/تغيير سعر حدث أصلي تُرفض كلها. لا بناء شموع وهمية ولا كشف بيانات Replay المستقبلية.
- **الحالة:** `main` بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`، لا APK أو Release، ولا تطبيق اختبار Android حقيقي أو قياس FPS أو اتصال cTrader فعلي.
- **التالي:** فحص تدفق Range في حساب cTrader وجهاز Android بوضع Profile (p50/p95/p99) لتحديد الاختناق الحقيقي التالي، ثم تعديل محدد بنتيجة قياس؛ لا APK إلا بإذن المستخدم.

## دفعة مكتملة — PR #579: نقل أحداث الحد الفاصل فقط بدل أرشيف مليون BID
- **MERGED:** [PR #579](https://github.com/775878805Osamaha/TradeLab/pull/579) إلى `test/flutter-all-fixes-20261116`، SHA الفعلي [819da6f](https://github.com/775878805Osamaha/TradeLab/commit/819da6f63c5f1b01cbe4217d061a4b4305e7a813).
- **CI النهائي:** [GitHub Actions #44844722298](https://github.com/775878805Osamaha/TradeLab/actions/runs/44844722298) **PASS / completed / success**؛ Flutter analyze واختبارات الشارت/Range/Replay والتوقيت. **التشغيل السابق #44844537479 FAILED** لتحذير `unused_local_variable boundaryMs` وتم تصحيحه بفحص زمني أقوى قبل الدمج.
- **الإصلاح:** `RangeLiveBidBoundary.fromVerified` يعثر ببحث ثنائي على أحداث المللي ثانية الأخيرة في BID المحمّل، ويُرسل قائمة صغيرة غير قابلة للتعديل إلى عامل `compute` بدل كل أرشيف التيكات (حد المليون). مقارنة كل حدث تتم الآن بالطابع الزمني `boundaryMs` والسعر، مع الحفاظ على السعر/الترتيب والعدد الأصلي وفشل مغلق عند تعارض الصفحة. رفض المصادر الأكبر من الحد الآمن قبل لمس بياناتها.
- **الاختبارات:** مصدر `ListBase` افتراضي لمليون تيك + صفحة 6500 تيك؛ أقل من 50 قراءة للمصدر في استخراج الحد الفاصل، وتأكيد عدم إرسال القائمة الكاملة، اختبار duplicate ordinal والرفض عند نقص حدث/جاوز ميزانية الذاكرة. **لا قياس حقيقي لزمن النقل أو FPS على Android**.
- **الحالة:** `main` لم يُعدل، بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`. لم يُبنَ APK أو Release، والنسخة المنشورة أقدم من الإصلاح.
- **الخطوة التالية:** تقليل عدد عمليات نسخ صفحات BID إلى عوامل المعالجة في تحديث Range الحي، مع الحفاظ على التحقق الكامل للمصدر، وCI قبل أي دمج؛ اختبار حي على Android/cTrader عند توفر جهاز/حساب.

## دفعة مكتملة — PR #578: تحديث Range المباشر من تيكات cTrader BID
- **MERGED:** [PR #578](https://github.com/775878805Osamaha/TradeLab/pull/578) في `test/flutter-all-fixes-20261116`، SHA الفعلي [754f500](https://github.com/775878805Osamaha/TradeLab/commit/754f500bd7dde18d92764dc74b928d5ea765d6e4).
- **CI النهائي:** [GitHub Actions #44836462583](https://github.com/775878805Osamaha/TradeLab/actions/runs/44836462583) **PASS / completed / success** على `a60d886f7037c2874685a8b1d3ccbf8dd808d561`، شامل Flutter analyze واختبارات الشارت/Range/Replay والتوقيت في اليمن. **محاولة CI السابقة #44836213938 FAIL** بسبب استيراد `TradeCandle` ناقص في اختبارين؛ صُححت وأعيد الفحص بنجاح.
- **تحديث Range الحي:** بعد فتح شارت Range على cTrader، يُطلب كل 30 ثانية **BID مصدري مؤرخ** من آخر مللي ثانية شاملة. `RangeLiveBidDelta` يثبت أن كل أحداث المللي ثانية القديمة عادت بنفس ترتيب وقيمة المصدر قبل إلحاق الأحداث الجديدة (بما فيها تيكات بنفس المللي ثانية أو BID متطابق)؛ أي تعارض مصدر يفشل بلا شموع أو أسعار تخمينية.
- **أداء البناء:** `RangeBarBuilder.resumeFromVerifiedForming` و`RangeBarTimeline.appendVerifiedSuffixAsync` يحافظان على كل الشموع المغلقة ومؤشرات أحداث Replay القديمة، ويضيفان فقط الزيادة في عامل مستقل حين التاريخ كبير. نشر تيكات BID والشموع والمُؤشرات في لقطة واحدة، الحفاظ على محور الزمن أثناء التحميل، والحماية من تغير الحساب/الرمز/المقاس/Revision أو نشاط Replay/تحميل تاريخ أقدم.
- **بوابة الاختبارات زادت:** `.github/workflows/verify-flutter-range.yml` أصبحت تشمل 6 ملفات اختبار كانت غائبة عن القائمة الثابتة: `range_live_bid_delta_test.dart`، `replay_revealed_exit_index_test.dart`، `chart_load_profiler_test.dart`، `range_bar_validation_test.dart`، `market_history_budget_test.dart`، `candle_prefix_test.dart`. نجحت ضمن تشغيل #44836462583.
- **حدود الاعتماد:** `main` بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` دون تعديل. لا APK أو Release جديد. **Android Profile/FPS واتصال حساب cTrader حقيقي NOT RUN**؛ نجاح اختبارات وهمية/محلية لا يثبت توفر تيكات الوسيط فعليًا أو مطابقة TradingView.
- **الخطوة التالية الوحيدة:** قياس تجربة Live Range على Android مع حساب cTrader فعلي لتأكيد استجابات `[lastMs, now]` المصدرية وتوقيت التحديث وسلاسة الشارت، ثم إصلاح أي اختلاف مثبت. لا إنشاء APK حتى طلب المستخدم صراحة.

## دفعة مكتملة — PR #577: قص خطوط وقف/هدف Replay إلى الشاشة
- **MERGED:** [PR #577](https://github.com/775878805Osamaha/TradeLab/pull/577) إلى `test/flutter-all-fixes-20261116` عند SHA [98db797](https://github.com/775878805Osamaha/TradeLab/commit/98db797faf2bb98941734ea77b9228571d08e159).
- **CI:** [GitHub Actions #44835136904](https://github.com/775878805Osamaha/TradeLab/actions/runs/44835136904) = **PASS/completed/success**؛ Flutter analyze واختبارات الرسم/Replay/Range والتوقيت.
- **المشكلة التي عولجت:** خط SL/TP لصفقة تدريبية قد يبدأ قبل 200 ألف شمعة، فكان رسمه يولد شرطات على امتداد ملايين البكسلات المخفية رغم `clipRect`. بات `visibleDashSegments` يتخطى مباشرة كل الفترات غير المرئية ويحافظ على طور الشرطات المصدرية ويولد فقط O(plotWidth/12) شرطة. `visibleStroke` يقص الخط المتصل، ولا تُرسم علامات دخول/خروج خارج الشاشة.
- **الاختبارات:** عرض 300px مع نقطة بداية -2,000,000px ينتج ≤27 شرطة، اختبار طور الشرطات والقص وNaN، ورسم widget لصفقة على 200 ألف شمعة. هذا لا يغير سعرًا أو Replay cutoff أو نتيجة صفقة.
- **الحالة:** `main` لم يُعدل (SHA `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`)، ولا APK/Release جديد؛ ما زال الأداء الحقيقي على Android غير مقاس.
- **الخطوة التالية:** تحسين تحديث BID Range الحي من صفحات cTrader الموثقة دون إعادة تنزيل التاريخ الطويل، ثم اختبارات حساب/مصدر وتطابق بناء Range وReplay؛ لا APK جديد دون إذن.

## دفعة مكتملة — PR #576: وقف/هدف Replay سريع للقفزات الطويلة
- **MERGED:** [PR #576](https://github.com/775878805Osamaha/TradeLab/pull/576) إلى `test/flutter-all-fixes-20261116`، SHA الفعلي [84e9c5c](https://github.com/775878805Osamaha/TradeLab/commit/84e9c5c3eb038b2cca30427101af8f95149f3851).
- **CI:** [GitHub Actions #44834326339](https://github.com/775878805Osamaha/TradeLab/actions/runs/44834326339) **PASS / completed / success**؛ Flutter analyze واختبارات التاريخ والشارت وReplay/Range وتوقيت اليمن. لا قياسات Android Profile/FPS حقيقية حتى الآن.
- **المسار السريع:** `ReplayRevealedExitIndex` يبني نطاقات min-low/max-high من **الشموع التي كُشفت فقط** حتى cutoff الحالي. عند قفزة تتجاوز 2048 شمعة و8 صفقات SL/TP و100k مقارنة متوقعة، يحل أول hit لكل صفقة ببحث شجري بدل فحص جميع الشموع لكل صفقة. التشغيل شمعة بشمعة يحتفظ بالمسار الخفيف القديم.
- **السياسة لا تتغير:** لا استخدام high/low لشمعة الدخول، SL أولًا في حالة SL/TP بنفس الشمعة، وملء SL عند سعر افتتاح أسوأ عند gap. الفهرس يُلغى عند rewind/prepend/clear أو تغير هوية المصدر، ولا يقرأ أي شمعة مخفية بعد الحد المكشوف. حد Range يتضمن 250000 شمعة مغلقة وواحدة متكوّنة غير منفّذة.
- **الاختبارات:** 100k مصدر مغلق بقراءات محروسة، تمديد تدريجي لحد الكشف، وقف/هدف في أول مصدر حقيقي، و120k شمعة مع 24 صفقة وإعادة اختبار rewind/short entry.
- **الحالة العامة:** `main` عند `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` دون تغيير، والـAPK المنشور سابقًا لا يحتوي #575 ولا #576. لا APK أو Release جديد ولا تغيير باقي المشاريع.
- **التالي:** مراقبة ومعالجة أداء Canvas/Replay على Android Profile بأرقام p50/p95/p99 حقيقية، ومتابعة ميزانية التاريخ الطويل/إدارة نوافذه عند تجاوز 200k شمعة زمنية. لا APK إلا بطلب.

## دفعة مكتملة — PR #575: Replay تاريخي سريع مع حماية اختيار الوقت
- **MERGED:** [PR #575](https://github.com/775878805Osamaha/TradeLab/pull/575) إلى `test/flutter-all-fixes-20261116`، SHA الفعلي [e7ffbd8](https://github.com/775878805Osamaha/TradeLab/commit/e7ffbd80db2add402cc16b89a7ef60576a7b6887).
- **CI:** [GitHub Actions #44833280061](https://github.com/775878805Osamaha/TradeLab/actions/runs/44833280061) **PASS / completed / success**؛ Flutter analyze واختبارات الشارت وRange وReplay والتوقيت في اليمن. لا اختبار هاتف Android فعلي ولا FPS مقاس.
- **العمل:** `ReplayVerifiedTimeIndex` يعيد استخدام التحقق في نفس snapshot الموثق، ثم يجري اختيارات التاريخ ببحث ثنائي `O(log N)` بدل إعادة مسح كامل 200 ألف توقيت. `ReplayDateSelectionGuard` يمنع تطبيق نتائج نافذة تاريخ/وقت قديمة بعد تبديل الرمز/الحساب/الفريم/المنطقة الزمنية أو إعادة بناء مصدر Replay. يظل آخر عمود مغلق غير صالح كبداية دون شمعة مستقبلية.
- **الاختبارات:** 200 ألف توقيت و180 بحثًا بحساب عدد القراءات؛ تغيير هوية التوقيتات، بيانات غير مرتبة، الأحداث المتساوية في مللي ثانية Range، وإبطال اختيار التاريخ لكل متغير من متغيرات الجلسة.
- **الحدود:** لم يُنشأ APK؛ الإصلاح #575 غير موجود في أحدث APK سابق. `main` بقي عند `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc`. لا تغيير مصادر الأسعار أو تداول حقيقي.
- **الخطوة التالية:** تسريع مراجعة الصفقات الورقية في Replay عند القفز الطويل مع الحفاظ على stop/target وحجب المستقبل، ثم CI/دمج التطوير فقط، وقياس FPS على هاتف لاحقًا.

## دفعة مكتملة — PR #574: سلامة صفحات SQLite القديمة وقياس Range
- **MERGED:** [PR #574](https://github.com/775878805Osamaha/TradeLab/pull/574) إلى `test/flutter-all-fixes-20261116` عند SHA [32ae4f8](https://github.com/775878805Osamaha/TradeLab/commit/32ae4f83fc47f8541a70b756b508fc39d23c9939).
- **CI:** [GitHub Actions #44832321863](https://github.com/775878805Osamaha/TradeLab/actions/runs/44832321863) **PASS / completed / success**، يشمل Flutter analyze واختبارات SQLite/الشارت/Range/Replay وتوقيت اليمن.
- `MarketCandleStore.contiguousOlderPage`: لا يخترق التاريخ المحمّل جزيرة SQLite أقدم بينها وبين الشارت فترة لم يثبت تنزيلها؛ يستخدم اتصالًا معروفًا لشموع المصدر، ثم يستعين بوسيط cTrader أو Binance الحقيقي عند gap أو مدة شهر متغيرة. صفحة متصلة كاملة (2000 شمعة) تُعاد بدون نسخ إضافي. لا تعبئة شموع وهمية أو تغيير Replay.
- فصل سجل p50/p95/p99 حسب `(مرحلة التحميل، نوع الرسم)` حتى لا تختلط أزمنة Range والشموع الزمنية.
- **التسليم:** جميع تغييرات #573 و#574 موجودة في فرع التطوير فقط؛ `main` بقي `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` دون تغيير. APK المنشور سابقًا **لا يحتوي هذه التغييرات**. **Android Profile/قياس FPS/اتصال cTrader الحقيقي NOT RUN**.
- **الخطوة التالية:** اختبار أداء الشارت وRange/Replay على جهاز Android بوضع Profile وتوثيق p50/p95/p99 ثم معالجة اختناق مثبت، أو تطوير إدارة نوافذ التاريخ فوق حد 200 ألف شمعة دون اختلاق بيانات. لا APK جديد دون طلب صريح.

## دفعة مدمجة — PR #573: قياس مراحل تحميل TradeLab على Android
- **MERGED:** [PR #573](https://github.com/775878805Osamaha/TradeLab/pull/573)، SHA [5750837](https://github.com/775878805Osamaha/TradeLab/commit/5750837b87f2c6a974b2b3ebb480defaccff7dc2) إلى `test/flutter-all-fixes-20261116`. أبقينا `main` عند `b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc` بدون تعديل.
- **CI المعتمد:** [GitHub Actions #44831381260](https://github.com/775878805Osamaha/TradeLab/actions/runs/44831381260) = **PASS / completed / success**. نجح Flutter analyze واختبارات الشارت وSQLite وRange/Replay وYemen timezone.
- إعداد `--dart-define=TRADELAB_PROFILE_CHART=true` يفعّل قياس 12 مرحلة للأداء (SQLite/cTrader/Binance/Range/Replay) باستخدام Stopwatch حقيقي مع p50/p95/p99 لكل مرحلة عبر 40 عينة، والتسجيل لا يتضمن رمز تداول/بيانات حساب/سعر/تواريخ سوق. **لم تُشغّل جلسة Android Profile حقيقية**؛ هذا تجهيز للقياس وليس نتيجة سرعة.
- **أحدث APK منشور أقدم من هذا التعديل** ولا يحتوي #567–#573؛ لا APK جديد دون طلب صريح.
- **التالي:** منع اختصار قفزات تاريخية غير مؤكدة بين شموع SQLite المحفوظة، ثم اختبارات رجعية ودمج في التطوير؛ لاحقًا قياس Android Profile على جهاز.

## آخر دفعة مكتملة — PR #572: تحميل الشموع المحلي وReplay مستقر
- **MERGED:** [PR #572](https://github.com/775878805Osamaha/TradeLab/pull/572) إلى `test/flutter-all-fixes-20261116` عند SHA [d746dea](https://github.com/775878805Osamaha/TradeLab/commit/d746dea22a7d11804ad5e19b56f5465a306f1c9d).
- **الاختبارات:** [Actions #44830135551](https://github.com/775878805Osamaha/TradeLab/actions/runs/44830135551) = **SUCCESS / completed** لتحليل Flutter، واختبارات مصدر التاريخ/SQLite/Range/Replay، وتوقيت اليمن. المحاولتان السابقتان [#44829082109](https://github.com/775878805Osamaha/TradeLab/actions/runs/44829082109) و[#44829601262](https://github.com/775878805Osamaha/TradeLab/actions/runs/44829601262) **FAIL** بسبب `pumpAndSettle` بعد سحب Replay؛ عولج السبب في الكود وجُرب اختبار انحدار لا يصدر طلبًا إضافيًا أثناء Replay.
- **كود الإنتاج:** استعادة أحدث **4000** شمعة زمنية محفوظة عند فتح الشارت، ثم صفحات SQLite محلية **2000** شمعة أقدم حسب حساب cTrader/الرمز/الفريم و`timestamp < cursor`، قبل طلب الوسيط عند فقد الكاش. الحد الآمن الحالي للشارت **200000 شمعة معتمدة بالذاكرة**؛ التاريخ الأقدم قد يبقى على القرص.
- **سلامة Replay:** السحب/التكبير داخل Replay أو أثناء اختيار بدايته لا يفتح تحميلًا تلقائيًا من الحافة. أمر `ReplayExtrasAction.loadOlder` اليدوي ما زال يعمل حين يطلب المستخدم تاريخًا أقدم. لا افتراضات أسعار أو تيكات وهمية ولا تسريب المستقبل.
- **الملفات:** `flutter_app/lib/data/market_candle_store.dart`, `flutter_app/lib/screens/chart_screen.dart`, `flutter_app/test/market_candle_store_test.dart`, `flutter_app/test/replay_training_widget_test.dart` وملفا التوثيق.
- **المتبقي:** لم يُقَس تحسين زمن فتح الشارت أو p50/p95/p99 لفريمات السحب على جهاز Android فعلي؛ هذا التغيير **غير موجود في APK المنشور بتاريخ 2026-11-20**. لا APK جديد دون طلب؛ `main` لم يتغير.
- **الخطوة التالية:** إجراء اختبار Android Profile حقيقي على شارت cTrader / Binance مع 4k و100k+ وRange وReplay، ثم إصلاح أي اختناق مثبت دون تغيير `main`.

## اكتمل توحيد تاريخ الشموع الزمنية — PR #571
- **MERGED:** [PR #571](https://github.com/775878805Osamaha/TradeLab/pull/571) إلى `test/flutter-all-fixes-20261116`، SHA الحقيقي [35444db](https://github.com/775878805Osamaha/TradeLab/commit/35444db050757d40561cd8f54525773709ed11c0).
- [Actions #44827584931](https://github.com/775878805Osamaha/TradeLab/actions/runs/44827584931) = **PASS / completed / success**: Flutter analyze واختبارات SQLite وRange/Replay وتوقيت اليمن؛ 4 اختبارات انحدار جديدة.
- `MarketCandleStore.read`/`mergeVerified`: استعادة/دمج حتى **200,000** شمعة مصدرية زمنية بدل قص القديم عند 100,000 افتراضيًا؛ المصدر المشترك `MarketHistoryBudget` يحمي أيضًا `OlderCandlePrepend` و`VerifiedMarketHistorySnapshot` وتحديثات cTrader.
- هذا حد **نافذة عرض في ذاكرة الشارت** وليس نهاية أرشيف الوسيط؛ إذا تم تجاوزه يُرفض نسخ مزيد من arrays بدل خطر انهيار التطبيق. لا أسعار وهمية ولا بيانات مستقبل Replay.
- ملف APK المنشور بتاريخ 2026-11-20 أقدم من PR #567–#571؛ لا ينقل هذا الإصلاح للهاتف إلا APK جديد بطلب صريح. **Android FPS وcTrader على جهاز فعلي NOT RUN**. `main` كما هو.
- **التالي:** اختبار شارت كامل على هاتف Android بالـProfile لقياس pan/pinch والمحتوى الحقيقي وBID Range، ثم إصلاح أول اختناق مثبت. لا APK تلقائيًا.

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