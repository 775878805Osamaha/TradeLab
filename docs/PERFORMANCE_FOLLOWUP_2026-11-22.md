# TradeLab — متابعة هندسية لأداء الشارت (22 نوفمبر 2026)

## النطاق والمبدأ
هذا التقرير يميز **نجاح تحسين العمليات في الكود** عن **تسارع أداء Android غير المقاس بعد**. العمل في `test/flutter-all-fixes-20261116` فقط (بعد دمج `8707e6c5fc08a555f82285b61b591380f4971c84`). لا APK جديد ولا تعديل `main` أو أسعار وسطاء cTrader/Binance أو بيانات BID أو حدود Replay.

## التغييرات المثبتة
| الدفعة | التغيير | الدليل | المقياس المثبت |
|---|---|---|---|
| [#610](https://github.com/775878805Osamaha/TradeLab/pull/610) | قص رسومات محدودة تاريخية قبل إسقاط السعر Y في اللمس | [CI #45018066145](https://github.com/775878805Osamaha/TradeLab/actions/runs/45018066145) نجاح | 2 sourceY للرسم المرئي بدل 12002 للسيناريو القديم |
| [#612](https://github.com/775878805Osamaha/TradeLab/pull/612) | كاش محور السعر عندما يبقى نفس نطاق فهارس الشموع مع pan كسري | [CI #45022185183](https://github.com/775878805Osamaha/TradeLab/actions/runs/45022185183) نجاح | 0 قراءات OHLC إضافية عبر 240 حركة كسريّة لنفس النافذة |
| [#613](https://github.com/775878805Osamaha/TradeLab/pull/613) | تحميل الشموع الأقدم مسبقًا بمقدار شاشتين (25–256 بار) عند pan | [CI #45022570244](https://github.com/775878805Osamaha/TradeLab/actions/runs/45022570244) نجاح | تحقق شرط الطلب من فهارس المصدر بلا تغيير Replay |
| [#614](https://github.com/775878805Osamaha/TradeLab/pull/614) | قص مبكر بواسطة فهرس الشمعة قبل حساب X في painter وhit | [CI #45024043207](https://github.com/775878805Osamaha/TradeLab/actions/runs/45024043207) نجاح | سيناريو 120k/6000: 2 sourceX بدل 12002 مع اختبارات سلامة clipping |
| [#615](https://github.com/775878805Osamaha/TradeLab/pull/615) | Cache ثوابت اللوغاريتم لكل إطار رسم وليس لكل OHLC | [CI #45024347884](https://github.com/775878805Osamaha/TradeLab/actions/runs/45024347884) نجاح | اختبار تكافؤ إحداثيات y مع المسار الأصلي على 320/390/640px |

كل رقم أعلاه من unit/workload test محلي في GitHub Actions، **لا يمثل نتيجة على جهاز المستخدم**.

## أين قد يستمر البطء؟
1. **التخزين/الشبكة:** زمن cTrader/SQLite/Binance في جلب شموع زمنية، وتوفر صفحات BID كاملة ومتتابعة في Range خصوصًا عند نهاية الأسبوع؛ الكود يحافظ على التحقق من المصدر قبل العرض.
2. **المعالجة:** تحضير Range timeline، جلب بيانات عالية الكثافة، نقل قوائم كبيرة بين isolates، وملء الفجوات التاريخية الموثقة دون تصنيع بيانات.
3. **الرسم واللمس:** تكلفة Raster/Build للشموع والرسومات وقت pan/pinch، استهلاك الذاكرة، ودقة محور السعر. لا يمكن تعيين السبب الأكبر دون القياس على الهاتف.

## بروتوكول القياس المقترح قبل الادعاء بالمطابقة أو تحسين FPS
- ابنِ **فقط عند تصريح المستخدم** نسخة Android Profile تحتوي على الدمجات؛ آخر APK Release من 20 نوفمبر 2026 أقدم من هذه الإصلاحات.
- عند بناء نسخة Android Profile مأذون بها، مرّر `--dart-define=TRADELAB_PROFILE_CHART=true` إلى أمر Flutter لتفعيل `ChartFrameProfiler` و`ChartLoadProfiler`؛ لأن `bool.fromEnvironment` يقرأ قيمة مُعرّفة وقت البناء، ولا يكفي متغير بيئة shell. لا تُنشئ تقديرات وهمية للفريمات.
- شغّل نفس الرمز/الإطار/عدد شموع المصدر (مثل 120k) ووضعي Candles/Heikin Ashi/Range عند عرضَي plot 259/329 وbarWidth 3/10/60، ثم تحقق من pan/pinch/momentum/replaySelection/ruler.
- سجّل frame build/raster/total P50/P95/P99، وعدد الإطارات >16.667ms و>8.333ms، مع نسبة العينة وعدد العينات. فارق بين أوقات `initialCacheRead`, `initialBrokerFetch`, `olderCacheRead`, `olderBrokerFetch`, `olderRangeRebuild`, `liveRangeVerify` وتجنب جمعها في رقم واحد مضلل.
- قارن صور TradeLab مع TradingView في **نفس بيانات OHLC، الوقت، حالة LOG/Invert/الزووم، اتجاه المحور RTL وتكثيف الملصقات**؛ لا تعلن طبق الأصل من دون screenshot/pixel فحص حقيقي.
- عند ظهور bottleneck موثق أصلحه في PR منفصل، ولا تدمج عند فشل CI، وسجّل SHA والتغيير والاختبار في `docs/CHANGE_REPORTS.md` و`docs/HANDOFF.md`.

## الحالة الحالية
العمل البرمجي الموصوف في #610/#612/#613/#614/#615 مدمج في فرع التطوير واجتاز CI. **السلاسة النهائية، سرعة الشبكة الفعلية، مطابقة TradingView وملف APK اختبار حديث: غير متحقق منها بعد.**
