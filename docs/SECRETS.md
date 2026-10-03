# الأسرار ومفاتيح التوقيع — كيف تعمل، وما الذي تحتاج فعله مرة واحدة

> **الخلاصة:** كل شيء داخل المستودع **مشفّر**. المفتاح الوحيد خارج المستودع هو كلمة فك التشفير
> `SECRETS_PASSPHRASE` في GitHub → Settings → Secrets and variables → Actions. تُضاف **مرة واحدة** وتبقى.

## 1. ما الموجود في `secrets/`

| الملف | المحتوى | التشفير |
|---|---|---|
| `secrets/release-key.jks.gpg` | keystore توقيع الإصدار (RSA 2048، صلاحية 10000 يوم، alias `pointgps`) | GPG symmetric AES‑256 |
| `secrets/key.properties.gpg` | كلمات مرور الـkeystore + alias + المسار | GPG symmetric AES‑256 |

**لماذا في المستودع؟** حتى لا يضيع المفتاح أبداً ويبقى كل إصدار موقّعاً بنفس المفتاح (وإلا لن يقبل Android التحديث فوق
النسخة القديمة — سيطلب إلغاء التثبيت). أي جلسة تطوير جديدة تستطيع البناء بمجرد معرفة كلمة فك التشفير.

**بصمة الشهادة (للتحقق):**
```
SHA-256: d65b5937aedbc1d76f3e8e7f74953648544885de1689bd22e5f6d705fac2e73b
SHA-1:   80b70688aa4235a78e133b504c2604d6fed20220
DN:      CN=Point GPS, OU=Mobile, O=PointGPS, L=Sanaa, C=YE
```
تحقق على أي APK: `apksigner verify --print-certs app.apk`

## 2. الخطوة اليدوية الوحيدة (مرة واحدة)

1. افتح: `https://github.com/alabasi2025/GPS2/settings/secrets/actions`
2. **New repository secret** → Name: `SECRETS_PASSPHRASE` → Value: كلمة فك التشفير (موجودة عند مالك المستودع
   — محفوظة بقرار المالك في `docs/معلومات_التثبيت.md`).
3. Add secret. انتهى — كل push إلى `main` يبني ويوقّع وينشر Release تلقائياً.

> إن غاب الـSecret، يفشل الـworkflow بخطوة «تحقق من وجود كلمة فك التشفير» برسالة واضحة.
> لا شيء آخر يحتاج إعداداً.

## 3. استخدام محلي (جلسة تطوير جديدة)

```bash
export PASSPHRASE='...'   # كلمة فك التشفير
gpg --batch --yes --decrypt --passphrase "$PASSPHRASE" -o android/release-key.jks  secrets/release-key.jks.gpg
gpg --batch --yes --decrypt --passphrase "$PASSPHRASE" -o android/key.properties   secrets/key.properties.gpg
flutter build apk --release --target-platform=android-arm64 --obfuscate --split-debug-info=build/symbols
```
`android/key.properties` و`android/release-key.jks` في `.gitignore` — لا تُرفع أبداً بشكل مفكوك.

## 4. تدوير كلمة فك التشفير (إن تسرّبت)

```bash
for f in release-key.jks key.properties; do
  gpg --batch --yes --decrypt --passphrase "$OLD" secrets/$f.gpg | \
  gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase "$NEW" -o secrets/$f.gpg
done
git commit -am "secrets: rotate passphrase" && git push
```
ثم حدّث `SECRETS_PASSPHRASE` في GitHub. **المفتاح نفسه (jks) لا يتغيّر** — فتبقى التحديثات متوافقة.

## 5. ما لا يوجد في المستودع عمداً
- كلمة فك التشفير.
- أي توكن GitHub (CI يستخدم `GITHUB_TOKEN` التلقائي بصلاحية `contents: write` فقط).
- لا مفاتيح API خارجية إطلاقاً (التطبيق لا يستخدم أي خدمة مدفوعة).
