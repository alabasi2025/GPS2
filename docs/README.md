# فهرس التوثيق

| الملف | ماذا تجد فيه |
|---|---|
| [SECRETS.md](SECRETS.md) | مفاتيح التوقيع المشفّرة في `secrets/`، الخطوة اليدوية الوحيدة (`SECRETS_PASSPHRASE`)، الاستخدام المحلي، التدوير |
| [RELEASE_PROCESS.md](RELEASE_PROCESS.md) | كيف يبني CI وينشر، الترقيم التلقائي، ما يفعله زر «تحديث تلقائي» خطوة بخطوة، التراجع، الرموز |
| [ARCHITECTURE.md](ARCHITECTURE.md) | الطبقات، تدفق البيانات، القرارات الهندسية ومراجعها، خريطة الاختبارات |
| [RESEARCH_2026-10.md](RESEARCH_2026-10.md) | البحث: Google FLP/FOP، ساعات الرياضة، أوراق PDR، تحدي Google Decimeter، تدقيق الادعاءات الشائعة، التصميم المستنتج |
| [PROMPT_FOR_OTHER_AGENTS.md](PROMPT_FOR_OTHER_AGENTS.md) | برومبت جاهز لإعطائه لأي وكيل/نموذج لمراجعة أو امتداد التصميم بقيود صلبة |
| [TESTING.md](TESTING.md) | منهجية الاختبار الميداني بثلاثة مستويات وتحليل CSV |
| [CHANGELOG.md](CHANGELOG.md) | سجل الإصدارات |

## روابط سريعة
- آخر إصدار: https://github.com/alabasi2025/GPS2/releases/latest
- بيان التحديث الذي يقرؤه التطبيق: https://github.com/alabasi2025/GPS2/releases/latest/download/latest.json
- حالة البناء: https://github.com/alabasi2025/GPS2/actions

## بدء جلسة تطوير جديدة (أي وكيل)
```bash
git clone https://github.com/alabasi2025/GPS2 && cd GPS2
flutter pub get && flutter analyze && flutter test
# للبناء الموقّع محلياً: انظر SECRETS.md §3
```
أي push إلى `main` يُنتج Release موقّعاً تلقائياً — والتطبيق المثبّت يراه عبر زر «تحديث تلقائي».
