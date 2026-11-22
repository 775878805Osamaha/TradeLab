# TradeLab ↔ TradingView Android — معيار قبول المطابقة الكاملة

## تحديث 2026-11-22 — منع إعادة الرسم بلا تغير بصري بسبب أسعار BID/ASK
- [PR #616](https://github.com/775878805Osamaha/TradeLab/pull/616) **MERGED**؛ [GitHub Actions #45027698225](https://github.com/775878805Osamaha/TradeLab/actions/runs/45027698225) **completed/success** بعد تصحيح [الإخفاق الأول الموثق #45027351182](https://github.com/775878805Osamaha/TradeLab/actions/runs/45027351182).
- **سلوك موثّق باختبارات الكود:** عندما `bidAsk=hidden` (الإعداد الافتراضي)، لا تؤدي 240 revisions للسعر إلى استدعاء repaint للشارت. عند إظهار BID/ASK تعيد التغيرات المرئية الرسم، كما تبقى تحذيرات تأخر المصدر في رأس الشارت عاملة. لم تُغيّر شموع broker أو Future Replay.
- **ليس دليل أداء فعلي:** اختبارات الاستدعاءات وFlutter analyze ناجحة؛ لا قياسات إطار Android Profile على الجهاز، ولا لقطات مقارنة pixel-perfect لـTradingView، ولا APK أحدث. معيار المطابقة على الهاتف **غير مكتمل**، ولا يجوز ادعاء الاكتمال.


## 2026-11-22 — نتيجة قبول #614 والأداء المتبقي
- [PR #614](https://github.com/775878805Osamaha/TradeLab/pull/614) **تم دمجه**، [اختبارات Flutter CI](https://github.com/775878805Osamaha/TradeLab/actions/runs/45024043207) **ناجحة**. تم تخفيض إسقاطات X للرسومات المحدودة غير المرئية في اختبار 120k/6000 إلى اثنتين في حالة الرسم المرئي، بينما حافظ اختبار pixel geometry على عدم رفض أي خط قد يدخل الشارت في الحالات المختبرة.
- معيار **سلامة الكود** الخاص بالدفعة: اجتاز التحليل والاختبارات. معيار **مطابقة TradingView على Android**: **لم يجتز بعد** لأن القياس لم يُجرَ.
- الاختبار الناقص: Android profile على 320/390dp؛ السحب/التكبير/المسار الحركي مع OHLC 100k+، Range BID مكتمل دون كشف مستقبل Replay، P95/P99 لإطارات build/raster مع زمن cTrader/SQLite/Range source. لا تعد هذه الأهداف أو قيم الميزانية أرقام نتائج فعلية.
- تاريخ آخر APK المنشور يسبق تحسينات 22 نوفمبر، ولذلك لا يثبت أداء النسخة المطورة. لا تغيير `main` أو APK لهذه الدفعة.


## 2026-11-22 — تحديث قبول الأداء بعد #614 و#615
- [#614](https://github.com/775878805Osamaha/TradeLab/pull/614) (دمج `7f3f2f0`، [CI ناجح](https://github.com/775878805Osamaha/TradeLab/actions/runs/45024043207)): استبعاد X/Y للرسومات التاريخية المحدودة غير المرئية عبر فهارس المصدر، بشرط المحافظة على ray/extended/crossline/fibonacci/parallel والرسومات المختارة وحدود Replay. اختبار الوحدة 120k مصدر/6000 رسمة: 2 إسقاط X للحالة المعروفة، وليس معدل إطارات.
- [#615](https://github.com/775878805Osamaha/TradeLab/pull/615) (دمج `8707e6c`، [CI ناجح](https://github.com/775878805Osamaha/TradeLab/actions/runs/45024347884)): حساب حدود LOG مرة في frame؛ اختبارات تحوّل السعر إلى y متطابقة عدديًا ضمن 1e-10 على ثلاث ارتفاعات شاشة، مع Inverted وFallback modes. المصدر وReplay unchanged.
- **حالة معيار القبول:** نجاح التحليل/الوحدة والتكامل عبر CI، **لكن لم تُجرب الدفعتان على Android الفعلي ولا قورنت لقطات TradeLab/TradingView**. لا إثبات تطابق 100% أو FPS/latency. فرع التطوير `test/flutter-all-fixes-20261116`، لا APK جديد، و`main` دون تغيير.
- **المتبقي:** اختبار فعلي عند 320/390dp و3/10/60px لكل شمعة، تحميل 120k verified candles وRange BID مع إغلاق السوق، قياس Flutter Engine `frameP95Us/frameP99Us` ووقت SQLite/cTrader منفصلين، ثم Pixel comparison مع TradingView في المصدر/الوقت/الزووم نفسه.


## تحديث 2026-11-22 — تقدم أداء الكود لا يعادل جاهزية Android
- [PR #610](https://github.com/775878805Osamaha/TradeLab/pull/610) حسّن لمس آلاف الرسومات خارج plot، [CI ناجح #45018066145](https://github.com/775878805Osamaha/TradeLab/actions/runs/45018066145). اختبار 120k bar/6000 drawings يحصي عمليتين `sourceY` للرسم المرئي بدلاً من آلاف التحويلات، دون قياس FPS على هاتف.
- [PR #612](https://github.com/775878805Osamaha/TradeLab/pull/612) يثبت كاش نطاق محور السعر للـpan الكسري داخل نفس شموع المصدر، [CI ناجح #45022185183](https://github.com/775878805Osamaha/TradeLab/actions/runs/45022185183)؛ اختبار 240 حركة pan لنفس نافذة 120k لا يقرأ OHLC مجددًا.
- [PR #613](https://github.com/775878805Osamaha/TradeLab/pull/613) يقدم تحميل الشموع الأقدم حتى مسافتَي شاشة، ضمن 25–256 بار، [CI ناجح #45022570244](https://github.com/775878805Osamaha/TradeLab/actions/runs/45022570244). لا تحميل Replay تلقائي، لا أسعار وهمية، ولا إثبات انخفاض latency للشبكة بعد.
- **قبول الأداء المتبقي:** مقارنة أجهزة Android حقيقية عند 320/390dp وفواصل 3–60px شمعة، تسجيل عدد/زمن إطارات gesture وp95/p99 وفترات التوقف، وزمن تحميل cache وbroker وRange BID مع >100k المصدر. هدف 16.7ms لإطار 60Hz هو معيار مطلوب اختباره **وليس نتيجة مقاسة**.
- آخر APK في Releases بتاريخ 2026-11-20 يسبق هذه التعديلات؛ **لا يمكن وصف النسخة المثبتة بأنها أسرع بمجرد دمج الكود**. التطوير الحالي `test/flutter-all-fixes-20261116` @ `974196e3c62ef67919c71031c235b57c3c245cad`، وليس `main`، وبدون APK جديد. حالة «طبق الأصل»: **NOT COMPLETE**.


## تقدم التحقق 2026-11-22 — تحسين كلفة لمس الرسومات
- [PR #610](https://github.com/775878805Osamaha/TradeLab/pull/610) **MERGED** في فرع التطوير عند `37bc5d56f2a807d97be046ab49359789b4f81e90`؛ [GitHub CI #45018066145](https://github.com/775878805Osamaha/TradeLab/actions/runs/45018066145) **SUCCESS**.
- كلفة تحويل إحداثيات السعر في `ChartDrawingHitTest.hit` أصبحت مقصوصة للخطوط المحدودة غير المرئية. اختبار 120k index/6000 offscreen patterns على شاشتي 259/329dp نجح: `sourceY` استُدعي مرتين للرسم الظاهر بدل 12002 في المسار القديم، مع بقاء Rays/Fibonacci/Crossline/Parallel قابلة للتحديد ومنع ظهور المستقبل في Replay.
- **لا يستوفي معيار 100% حتى الآن:** هذا قياس عمليات حسابية ضمن اختبارات وحدة وليس FPS أو صورة بكسل أو اختبار Android. ينبغي التقاط واجهات TradingView وTradeLab على جهاز حقيقي وقياس p50/p95/p99 قبل الحكم على السلاسة. لا APK ولا `main`.


## تحديث تحقق 2026-11-22: سلامة الرسومات ومغناطيس LOG
- PR #608 ([الدمج](https://github.com/775878805Osamaha/TradeLab/pull/608)، [CI ناجح](https://github.com/775878805Osamaha/TradeLab/actions/runs/44964541908)) يعالج الفهارس السالبة لمرسات Replay والبيانات NaN/Infinity والرسم غير المحدود.
- PR #609 ([الدمج](https://github.com/775878805Osamaha/TradeLab/pull/609)، [CI ناجح](https://github.com/775878805Osamaha/TradeLab/actions/runs/44965028176)) يحسب قرب OHLC للمغناطيس بالبكسلات الحقيقية في LOG/Inverted على نماذج شاشات 320/390dp. فشل analyzer سابق موثق في `CHANGE_REPORTS.md` وأعيد الفحص بعد إصلاحه بنجاح.
- **حالة القبول:** اختبارات الكود الآلية ناجحة، لكن لقطة Android المرجعية والمطابقة البصرية واللمس وp50/p95/p99 على الجهاز **غير منفذة**؛ لا يجوز إعلان 100% أو جاهزية التطبيق. فرع التطوير `test/flutter-all-fixes-20261116` @ `07e2edeef9a0dcf74631f1f5094b5b856d5d3df2`، دون APK أو إصدار أو تعديل `main`.


**آخر مراجعة:** 2026-11-22 بتوقيت اليمن / 2026-11-21 UTC. **الحكم الحالي:** المطابقة الكاملة غير مثبتة / NOT COMPLETE. نجاح اختبارات Flutter لا يعادل اختبار هاتف فعلي أو مطابقة البكسل.

## المرجع الوظيفي الرسمي

- TradingView Mobile gestures and OHLC tracking: https://www.tradingview.com/charting-library-docs/latest/mobile_specifics/
- Supercharts navigation, drawing and Replay: https://www.tradingview.com/support/solutions/43000746464-getting-started-with-supercharts/
- Price axis autoscale: https://www.tradingview.com/support/solutions/43000762826-how-to-enable-autoscale/
- Bar Replay controls: https://www.tradingview.com/support/solutions/43000474024-how-do-i-turn-bar-replay-on/
- Mobile Replay interval: https://www.tradingview.com/support/solutions/43000747376-how-to-select-replay-interval-for-the-bar-replay-in-mobile-apps/
- TradingView chart type restrictions (Range charts **not supported** by its own Bar Replay): https://www.tradingview.com/support/solutions/43000712747-bar-replay-how-and-why-to-test-a-strategy-in-the-past/

## مصفوفة قبول TradeLab

| المجال | دليل الشفرة/الاختبارات المتاح | المتبقي للتحقق قبل إعلان «طبق الأصل» |
| --- | --- | --- |
| شارت شموع يملأ الشاشة، السعر يمينًا والوقت أسفل | Flutter chart وchart_viewport/widget tests | تصوير Android عند 320/390dp في الثيمين ومقارنة حقيقية للمسافات والخطوط والرموز والطبقات مع مرجع ثابت |
| السحب والتكبير والإفلات والقصور الذاتي | PR #587 لمنع phantom fling؛ PR #591 لحالات 2→3→2 أصابع؛ PR #599 أعطى سحب مقابض Long/Short مسار paint-only مع 4 widget tests ناجحة (Actions #44958411202) | Android Profile حقيقي مع لمس متعدد، pan/pinch/inertia وتاريخ كثيف، إطارات p50/p95/p99؛ تحسين المصدر لا يساوي قياس FPS |
| تتبع OHLC وcrosshair على Android | PR #592 وActions #44924414254 PASS: long press ثم lift ثم single-tap exit مع widget test 320/390dp | اختبار بصري/لمسي حقيقي مقابل TradingView، دقة خط السعر وUTC-label |
| تحجيم محور السعر وAUTO ومحور الوقت | PR #602 LOG فعلي وتحويلات price/y، #603 عكس المحور linear/LOG، #604 يمنع تزاحم علامات 84/155/440dp في الوضعين والمعكوس، #605 يضيف Percent وIndexed to 100 بأرقام مأخوذة من أول إغلاق لشمعة مصدر ظاهرة، مع الحفاظ على الأسعار الأصلية وReplay prefix — جميعها MERGED ونجح CI #44960370219، #44960941431، #44961365235 و#44962189024 | Android: **لم تنفّذ** مقارنة بكسل/لمس مقابل TradingView أو قياسات p50/p95/p99، ومرجع أول إغلاق ظاهر للوضع النسبي يحتاج اختبارًا مع المرجع. مفاتيح Price/Bar ratio lock وأوضاع إضافية لا تزال بحاجة تدقيق/تنفيذ |
| Replay داخل الشارت بخط البداية والأدوات المصغرة | ReplayMobileControls, ReplayStartResolver, ReplayDateSelectionGuard؛ PR #590 لحماية الجلسات، وPR #594 لتثبيت مواضع الشموع عند Play/Seek/Rewind ومنع Play عند EOF (CI #44935284854 PASS) | تطابق كامل لقائمة البداية، المقص الأزرق، تحكم السرعة، موضع الأدوات والـscroll مع المرجع على Android؛ قياس حقيقي لم يكتمل |
| عزل مستقبل Replay والتداول الورقي | CandlePrefix وReplay training/source guards؛ اختبارات replay وPR #590 | اختبار جهاز حقيقي للتنقل/الخروج/إعادة الدخول، ضمان عدم إظهار شموع لاحقة في أي overlay |
| Replay interval مستقل (tick / 1s / 1m / 3m) | القائمة موجودة، بعض الخيارات معطلة حين يفتقر المصدر إلى البيانات الدقيقة | تنفيذ فواصل زمنية فقط عند توافر تيكات/شموع أصلية موثقة بمستوى الدقة المطلوب؛ ممنوع تعويضها ببيانات مُختلقة |
| أدوات الرسم والاختيار والتراجع والتعديل | PR #596 double-tap و#597 حماية مصدر الرسم؛ #598 Long/Short Position؛ #599 سحب Stop paint-only؛ #600 حجب وسوم SL/TP خارج viewport؛ #601 Crossline من نقطة مصدر واحدة مع خطوط plot-clipped ووسمي سعر/زمن، Widget 320/390dp؛ و#606 Info Line من نقطتين أصليتين مع Δ/%/UTC/bars/زاوية و#607 Trend Angle مستقل بتحديد مرساتين وعرض ° مع متانة Inverted/Replay، Widget 320/390dp؛ الاثنان MERGED وCI #44963130021 و#44963619641 PASS | ما زالت Regression Trend وGann/Fibonacci Extension وأدوات كتالوج أخرى غير منفذة؛ Crossline advanced style/visibility غير مثبتة، واختبار hit-testing/drag/anchor واللون على Android 320/390dp يحتاج مرجع Golden أصلي وقياس الجهاز |
| التاريخ وRange المتصل ببيانات السوق | Forex/Gold: cTrader BID فقط؛ Crypto: Binance؛ اختبارات Range/history في CI | قياس التحميل على جهاز Android مع بيانات حقيقية تتجاوز 100k bars، معرفة حدود ذاكرة الجهاز وزمن الاستجابة |
| نتائج الحساب والتداول التجريبي | وحدات paper/results موجودة ولها اختبارات | قياس مطابقة الصفحات والأرصدة والتصفية على الجهاز ومراجعة كامل التدفقات |

**مهم:** تداول Replay على Range في TradeLab هو امتداد مستقل يطلبه صاحب المشروع؛ TradingView نفسه يصرّح بأن Range غير مدعوم في Bar Replay. لا يجوز أن نقول إن هذه الخاصية «مطابقة» لخيار غير موجود لدى المرجع. وأيضًا اختلاف مزود الشموع (cTrader/Binance مقابل مصدر TradingView لأي رمز) قد ينتج فروقات سوقية حقيقية، فلا تُفبرك أسعار لمطابقة لقطة شاشة.

## اختبار المطابقة البصرية الفعلي (لم يُنفّذ)

1. تثبيت هدف المقارنة: نفس رمز السوق، إطار الشموع، وقت الإغلاق، المقاس الفيزيائي وDPI والاتجاه، ألوان الثيم، وحالة القوائم، مع صور مرجعية أصلية.
2. التقاط TradeLab وTradingView بنفسيهما على الهاتف (320/390dp وAndroid)، لا صور AI أو mock؛ مقارنة شبكات محوري السعر/الوقت والخط/شموع OHLC وأيقونات الأدوات ونقاط لمسها.
3. تقييم سلاسة pan / pinch / Replay / crosshair على Android Profile مع عدد كافٍ من الإطارات، وتقرير p50/p95/p99 لكل تفاعل؛ **16.7ms للإطار على شاشة 60Hz هو سقف ميزانية مرجعي فقط وليس FPS مقاسًا**.
4. تشغيل المرور على فواصل Replay الحقيقية فقط (بدون إظهار المستقبل)، وقراءة الملفات/النتائج المحلية من دون تعديل مصدر حساب الوسيط.
5. لا يُعتبر الإنجاز «100%» قبل نجاح كل صفوف السلوك والتمثيل المرئي اللازمة على هاتف حقيقي. عند أي فشل يُسجل screenshot/steps/expected/actual/commit في docs/CHANGE_REPORTS.md.

## قيود تنفيذ وتكاليف

- ملف .github/workflows/chart-screenshot.yml يحتوي شرطًا معطلاً عمدًا لتجنب APK/emulator المدفوع. لا تُفعِّله ولا تبنِ APK أو Release دون إذن المستخدم الصريح.
- لا تعدل main، ولا تنسخ أي بيانات حقيقية من حساب التداول إلى تقارير GitHub، ولا تُدخل أسعارًا وهمية إلى التطبيق. سجل الأدلة وSHA ونتائج CI في HANDOFF/CHANGE_REPORTS.
- **الحالة الحالية:** PR #592 crosshair و#593 قوائم المحاور و#594 Replay anchor و#595 CandlePrefixCache و#596 double-tap guides و#597 حماية انتقال المصدر و#598 Long Position و#599 paint-only position drag و#600 offscreen SL/TP tags و#601 Crossline source price/time labels و#602 LOG scale و#603 invert scale و#604 mobile axis density و#605 Percent/Indexed100 و#606 Info Line و#607 Trend Angle — جميعها **MERGED في فرع التطوير** بعد فحوص GitHub Actions (الأخيرة #44940022375، #44958411202، #44958775049، #44959351046، #44960370219، #44960941431، #44961365235، #44962189024 و#44963130021 و#44963619641 **completed/success**). تفاصيل كل SHA محفوظة في `docs/HANDOFF.md` و`docs/CHANGE_REPORTS.md`. *الاختبارات البصرية Golden المرجعية المفقودة ليست مثبتة*، ولم تُجرَ مقارنة بكسل أو قياسات سلاسة Android Profile أو جلسة cTrader live. **NOT COMPLETE**.
- **الخطوة التنفيذية التالية:** إجراء اختبار visual/gesture فعلي على Android عند 320 و390dp بنسخة اختبار يصرّح بها المالك، وقياس p50/p95/p99 مع بيانات BID موثقة، ثم إصلاح أكبر فرق مثبت؛ لا إنشاء APK تلقائيًا.
