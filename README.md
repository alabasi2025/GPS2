# نقطة — Point GPS

[![release](https://github.com/alabasi2025/GPS2/actions/workflows/release.yml/badge.svg)](https://github.com/alabasi2025/GPS2/actions/workflows/release.yml)
[![latest](https://img.shields.io/github/v/release/alabasi2025/GPS2?label=%D8%A2%D8%AE%D8%B1%20%D8%A5%D8%B5%D8%AF%D8%A7%D8%B1)](https://github.com/alabasi2025/GPS2/releases/latest)

**التثبيت:** حمّل الـAPK من [آخر إصدار](https://github.com/alabasi2025/GPS2/releases/latest). بعدها لا تحتاج هذه الصفحة —
زر **«تحديث تلقائي»** داخل التطبيق يجلب كل إصدار جديد ويثبّته (مع تحقق SHA‑256).

**التوثيق الكامل:** [docs/](docs/README.md) — الأسرار، مسار الإصدار، المعمارية، البحث، الاختبار.

تطبيق Android يحدّد موقعك بأعلى دقة يمكن لهاتف أن يصل إليها **بدون أي خدمة مدفوعة**:
يقرأ حل GNSS الصافي من الشريحة (لا Fused/Wi-Fi)، يرشّحه بمرشّح Kalman مع بوابة
Mahalanobis، ويجمّع العينات أثناء السكون بمتوسط موزون بعكس التباين. يعرض دائرة ثقة
**صادقة** (95%) ويسجّل كل شيء في CSV حتى تختبر الدقة بنفسك.

- الحزمة: `com.pointgps.location` · Android 8.0+ (API 26) · **arm64-v8a فقط**
- مجاني بالكامل: خرائط OpenStreetMap، Google Play Services للموقع المدمج (مجاني، لا مفتاح)، لا خوادم، لا تتبع.

## ما الذي تتوقعه فعلاً (بصدق)

| الحالة | WhatsApp / Fused عادة | نقطة |
|---|---|---|
| واقف 60 ث سماء مفتوحة، هاتف L5 | 3–5 م | **≈ 1 م أو أقل** |
| واقف 60 ث، هاتف L1 فقط | 5–8 م | 1.5–3 م |
| يمشي 1.4 م/ث | 5–10 م + تأخّر | 2–3 م بلا تأخّر (Doppler) |
| داخل البيت / بين مبانٍ | 10–30 م (Wi-Fi) | **نفس WhatsApp تماماً** — يُعرض Fused مع تنبيه «اخرج لسماء مفتوحة» |

سنتيمترات؟ **مستحيل بدون محطة RTK قاعدية** — لا يدّعي التطبيق ذلك. الحد الأدنى
للعرض 0.5 م حتى لو قال الحساب أقل.

## كيف يعمل (مختصر تقني)

```
Fused Location Provider (Google Play Services, HIGH_ACCURACY)   ─► الحل الأساسي فوراً
  GPS + Wi-Fi + خلوي + حساسات — نفس مصدر WhatsApp / Find My Device   (داخل المباني يُعرض كما هو)
                                                                  │
LocationManager.GPS_PROVIDER + GnssStatus + GnssMeasurements      │
  ─► PositionEstimator (Kalman + Doppler + تجميع ثابت)  ──────────┤
                                                                  ▼
                                               SolutionArbiter — يختار ما يُعرض:
  • GNSS متسق مع Fused (≤ 2.5·σ مشتركة) وأدق منه و≥5 أقمار  ⇒ GNSS (≈1 م في العراء)
  • غير ذلك (انعكاسات داخل مبنى، أقمار قليلة)                ⇒ Fused بدقته (لا أسوأ من WhatsApp أبداً)
  • هستيرية 3 عينات قبل الرجوع إلى GNSS؛ Fused أقدم من 15 ث يُهمل
```

**لماذا ليس GNSS فقط؟** Google (I/O 2018، Frank van Diggelen): GPS في العراء ≈ 5 م ولا يعمل
داخل المباني؛ Wi-Fi عبر Fused يعطي < 10 م داخلها. **ولماذا ليس Fused فقط؟** لأنه لا يتجاوز
3–5 م في العراء، والتجميع الثابت على GNSS الخام يصل تحت المتر.

المحرك: إطار ENU على WGS-84؛ Kalman [e, n, ve, vn]؛ قياس Doppler للسرعة؛ بوابة χ²(2)=5.991؛
متوسط موزون 1/σ² مع σ_avg = 1.6/√Σw؛ دقة الشريحة ×1.5 (Barbeau 2019).

## منهجية الاختبار (3 مستويات)

1. **التكرارية** — قف على علامة ثابتة حتى يظهر «ثابت» ومرّ ≥ 60 ث، اضغط **حفظ نقطة**،
   ابتعد 50 م وارجع، كرّر 5 مرات. في «التحليل → النقاط المحفوظة» ترى أقصى تشتت وRMS.
   هذا رقم دقتك الحقيقي، ويجب أن يكون داخل دائرة ±95% المعروضة.
2. **النسبي بشريط قياس** — نقطتان على طرفي شريط 50 م؛ قارن «آخر نقطتين».
3. **المطلق** — قارن مع علامة مساحية معلومة الإحداثيات (أو جهاز مرجعي).

فعّل **تسجيل CSV** طوال الاختبار. الأعمدة: الخام مقابل المُرشَّح، σ، نصف قطر 95%،
حالة الحركة، عدد العينات، الأقمار، L5، C/N0، رقم الجلسة.

## البناء

```bash
flutter pub get
flutter analyze && flutter test
flutter build apk --release --target-platform=android-arm64 \
  --obfuscate --split-debug-info=build/symbols/android/1.0.0
```

التوقيع: `android/key.properties` + `android/release-key.jks` (خارج Git).
