# مسار الإصدار والتحديث التلقائي

```
 git push main ──► GitHub Actions (.github/workflows/release.yml)
                     ├─ فك تشفير مفاتيح التوقيع (secrets/*.gpg + SECRETS_PASSPHRASE)
                     ├─ flutter analyze --fatal-infos
                     ├─ flutter test                      (كل الاختبارات يجب أن تنجح)
                     ├─ flutter build apk --release arm64 --obfuscate
                     ├─ تحقق: التوقيع، arm64 فقط، versionCode
                     └─ Release: APK + .sha256 + latest.json + symbols.zip + mapping.txt
                                        │
 التطبيق على الهاتف ◄───────────────────┘
   زر «تحديث تلقائي» → يقرأ releases/latest/download/latest.json
   → يقارن versionCode → ينزّل APK مع شريط تقدم → يتحقق SHA‑256
   → يفتح مثبّت النظام (المستخدم يضغط «تثبيت»)
```

## الترقيم
- `versionName` من `pubspec.yaml` (مثل `1.3.0`) — غيّره يدوياً عند تغيير وظيفي.
- `versionCode` = `github.run_number + 100` — **تلقائي ومتزايد دائماً**؛ لا تعدّله يدوياً.
  (الإصدارات اليدوية القديمة انتهت عند 4؛ لذلك البدء من 101.)
- الوسم: `v<versionName>+<versionCode>`، مثل `v1.3.0+101`.

## ما يفعله التطبيق بالضبط عند «تحديث تلقائي»
1. `GET https://github.com/alabasi2025/GPS2/releases/latest/download/latest.json` (مهلة 15 ث).
2. إن `versionCode` المنشور ≤ المثبّت → «لديك أحدث إصدار».
3. وإلا: تنزيل متدفق إلى `cache/updates/point_gps_<code>.apk` مع تقدم كل 120 ms أو 2%.
4. حساب SHA‑256 أثناء التنزيل؛ عدم تطابق = حذف الملف + خطأ واضح. لا يُثبَّت ملف غير مطابق **أبداً**.
5. تحقق من الحجم. ثم تحقق ثانٍ من البصمة قبل تسليم الملف للنظام.
6. إن غاب إذن «تثبيت تطبيقات غير معروفة» → تُفتح شاشة الإذن للتطبيق تحديداً؛ عند العودة يُكمل تلقائياً.
7. مثبّت Android القياسي. التوقيع مطابق للنسخة الحالية ⇒ تثبيت فوق القديم بلا حذف بيانات.

عند الإقلاع يفحص التطبيق بصمت (بلا تنزيل) ويظهر شارة صفراء على زر التحديث إن وُجد إصدار أجدد.

## تشغيل يدوي
Actions → release → **Run workflow** → (ملاحظات اختيارية). يبني وينشر حتى بلا تغيير كود.

## التراجع (rollback)
Release القديم يبقى. لإجبار التطبيقات على العودة: احذف الـRelease الأحدث وعلّم القديم `latest`؛
لكن Android لا يسمح بتثبيت `versionCode` أقل فوق أعلى — سيحتاج المستخدم إلغاء التثبيت. الأفضل: push إصلاح جديد.

## الرموز (symbols) وفك التبهيم
`symbols.zip` + `mapping.txt` في كل Release. لقراءة stack trace مُبهَّم:
```bash
flutter symbolize -i trace.txt -d symbols/app.android-arm64.symbols
```
