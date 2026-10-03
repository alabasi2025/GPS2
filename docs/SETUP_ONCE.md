# إعداد لمرة واحدة (دقيقتان) — بعدها كل شيء تلقائي

> سبب هذه الخطوات: التوكن المتاح للوكيل لا يملك صلاحيتين فقط — إنشاء ملفات workflow وإضافة Secrets.
> كل ما عداهما تم ودُفع للمستودع.

## الخطوة 1 — إضافة كلمة فك التشفير (Secret)
1. افتح https://github.com/alabasi2025/GPS2/settings/secrets/actions
2. **New repository secret**
3. Name: `SECRETS_PASSPHRASE`
4. Value: `oYi242XaRPXMgdHGeK1Yo5nCx6cxnBUv` (موجودة أيضاً في `docs/معلومات_التثبيت.md`)
5. **Add secret**

## الخطوة 2 — إضافة ملف الـworkflow
1. افتح https://github.com/alabasi2025/GPS2/new/main?filename=.github/workflows/release.yml
2. انسخ محتوى [`docs/release.workflow.yml`](release.workflow.yml) كاملاً والصقه.
3. **Commit changes** (مباشرة إلى `main`).

## ماذا يحدث بعدها
- فور الحفظ يبدأ أول بناء: https://github.com/alabasi2025/GPS2/actions
- بعد ~8 دقائق يظهر Release `v1.3.0+101` مع APK موقّع و`latest.json`.
- التطبيق على هاتفك (إصدار ≥ 1.3.0) يكتشفه بزر «تحديث تلقائي».
- **كل push لاحق** إلى `main` → Release جديد تلقائياً. لا شيء آخر يُطلب منك.

## تحقق سريع
```bash
curl -sL https://github.com/alabasi2025/GPS2/releases/latest/download/latest.json
```
يجب أن يُرجع JSON فيه `versionCode` و`sha256`.
