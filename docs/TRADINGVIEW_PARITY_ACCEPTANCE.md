# TradeLab ↔ TradingView Android — معيار قبول المطابقة الكاملة

**آخر مراجعة:** 2026-11-21 (UTC). **الحكم الحالي:** المطابقة الكاملة غير مثبتة / NOT COMPLETE. نجاح اختبارات Flutter لا يعادل اختبار هاتف فعلي أو مطابقة البكسل.

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
| السحب والتكبير والإفلات والقصور الذاتي | PR #587 لمنع phantom fling؛ PR #591 لحالات 2→3→2 أصابع؛ فحوص CI ناجحة | Android Profile حقيقي مع لمس متعدد، pan/pinch/inertia وتاريخ كثيف، إطارات p50/p95/p99 |
| تتبع OHLC وcrosshair على Android | PR #592 وActions #44924414254 PASS: long press ثم lift ثم single-tap exit مع widget test 320/390dp | اختبار بصري/لمسي حقيقي مقابل TradingView، دقة خط السعر وUTC-label |
| تحجيم محور السعر وAUTO ومحور الوقت | ChartViewport/scale widget regression tests؛ AUTO متاح بالشفرة | مقارنة مواقع العلامات والنقر المطول على المقياس؛ قائمة إعدادات مطابقة للمرجع على الهاتف |
| Replay داخل الشارت بخط البداية والأدوات المصغرة | ReplayMobileControls, ReplayStartResolver, ReplayDateSelectionGuard؛ PR #590 لحماية الجلسات، وPR #594 لتثبيت مواضع الشموع عند Play/Seek/Rewind ومنع Play عند EOF (CI #44935284854 PASS) | تطابق كامل لقائمة البداية، المقص الأزرق، تحكم السرعة، موضع الأدوات والـscroll مع المرجع على Android؛ قياس حقيقي لم يكتمل |
| عزل مستقبل Replay والتداول الورقي | CandlePrefix وReplay training/source guards؛ اختبارات replay وPR #590 | اختبار جهاز حقيقي للتنقل/الخروج/إعادة الدخول، ضمان عدم إظهار شموع لاحقة في أي overlay |
| Replay interval مستقل (tick / 1s / 1m / 3m) | القائمة موجودة، بعض الخيارات معطلة حين يفتقر المصدر إلى البيانات الدقيقة | تنفيذ فواصل زمنية فقط عند توافر تيكات/شموع أصلية موثقة بمستوى الدقة المطلوب؛ ممنوع تعويضها ببيانات مُختلقة |
| أدوات الرسم والاختيار والتراجع والتعديل | اختبارات horizontal/trendline/rectangles/short positions وبعض أدوات الشارت | جرد كل أداة مطلوبة مقابل تجربة TradingView واختبار hit-testing/drag/anchor والتراكب والألوان في أحجام 320/390dp |
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
- **الحالة الحالية:** PR #592 (crosshair) MERGED CI #44924414254 PASS؛ PR #593 (قوائم الضغط المطول للمحاور) MERGED CI #44925136335 PASS؛ PR #594 (تثبيت مواضع Replay في playback/seek والـEOF) MERGED عند b7826311823884245ddf44bd4b74f1c6fb1f1278، CI #44935284854 completed/success. **مطابقة الصورة والسلاسة على Android وcTrader live session NOT RUN؛ NOT COMPLETE.**
- **الخطوة التنفيذية التالية:** إجراء اختبار visual/gesture فعلي على Android عند 320 و390dp بنسخة اختبار يصرّح بها المالك، وقياس p50/p95/p99 مع بيانات BID موثقة، ثم إصلاح أكبر فرق مثبت؛ لا إنشاء APK تلقائيًا.
