# معمارية «نقطة» (Point GPS)

## الطبقات

```
android/.../GnssStreamPlugin.kt      Fused (Play Services) + GPS_PROVIDER + GnssStatus + GnssMeasurements
android/.../UpdateInstallerPlugin.kt FileProvider + مثبّت النظام + versionCode
android/.../MainActivity.kt          تسجيل الجسور + صلاحيات
        │ EventChannel: point_gps/fix, point_gps/status, point_gps/raw
        │ MethodChannel: point_gps/control, point_gps/update
lib/services/gnss_service.dart       GnssSource (واجهة) + GnssService (قنوات) 
lib/services/simulated_gnss_source.dart  محاكٍ واقعي للويب/الاختبار
lib/engine/position_estimator.dart   Kalman [e,n,ve,vn] + Doppler + χ² + سكون + تجميع
lib/engine/solution_arbiter.dart     تحكيم GNSS ↔ Fused (اتساق، هستيرية، ضعف)
lib/services/session_controller.dart دورة الحياة، وضع سريع/دقة قصوى، تثبيت، CSV، نقاط
lib/services/update_service.dart     تحديث ذاتي من GitHub Releases
lib/ui/*                             Flutter Material 3، RTL، خريطة OSM
```

## تدفق البيانات (كل ثانية تقريباً)
1. Kotlin يبث حل Fused (`source=assist`) وحل GPS (`source=gnss`) على نفس القناة.
2. `SessionController._onFix`: assist → `arbiter.updateAssist`؛ gnss → `estimator.update` ثم `arbiter.decide`.
3. `DisplaySolution` هو **الوحيد** الذي تعرضه/تشاركه الواجهة. يحمل المصدر والسبب والـσ.
4. الوضع السريع: يحتفظ بالأفضل، يثبّت عند σ≤5 م بعد ≥3 ث أو عند 10 ث، ويوقف المستشعرات.

## القرارات الهندسية وأسبابها
| القرار | السبب | المرجع |
|---|---|---|
| Fused أساس، GNSS تحسين | داخل المباني GPS ينعكس؛ Fused يستخدم Wi‑Fi | Google I/O 2018 |
| تضخيم دقة الشريحة ×1.5 | الدقة المبلّغة متفائلة ~32% | Barbeau 2019 |
| Doppler كقياس سرعة | أدق 10× من اشتقاق المواضع؛ يمنع التأخّر | Groves |
| χ²(2)=5.991 | 95% بدرجتي حرية | إحصاء قياسي |
| σ_avg = 1.6/√Σw | الأخطاء مرتبطة زمنياً (ρ≈0.7) | أدبيات GNSS الثابت |
| أرضية عرض 0.5 م | لا هاتف يحقق أقل بلا RTK | — |
| مُحكِّم بهستيرية 3 عينات | منع التذبذب بين المصدرين | — |
| arm64 فقط | 99% من الأجهزة الحديثة؛ APK أصغر | — |
| بلا حل PVT من pseudorange | أسوأ من الشريحة بلا محطة قاعدية | Weng & Ling 2023 |

## الاختبارات (36)
- `test/engine/position_estimator_test.dart` — محاكي AR(1): تقارب، σ صادقة، تكرارية 20 جلسة، قفزات، mock، مشي، NaN.
- `test/engine/solution_arbiter_test.dart` — سيناريو المبنى، الاتساق، الضعف، القِدم، الهستيرية.
- `test/services/session_controller_test.dart` — قنوات وهمية: ترتيب الاشتراك، الوضع السريع، التثبيت، التحديث.
- `test/services/update_service_test.dart` — HTTP وهمي: فحص، تقدم، SHA‑256 مزيّف، إذن، 404، إعادة استخدام.

## ما هو مخطَّط (انظر RESEARCH_2026-10.md §3)
PDR‑lite أثناء المشي (كاشف خطوات + Weinberg بمعايرة ذاتية + heading من Fused Orientation Provider) مدمجاً في Kalman.
