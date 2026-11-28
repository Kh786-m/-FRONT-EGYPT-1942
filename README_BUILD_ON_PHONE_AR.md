# بناء APK للعبة حَرَق (HARAQ) من الهاتف — GitHub Actions

المستودع فيه مشروع Godot 4.3 في الجذر، وفيه workflow جاهز اسمه `Build Android debug APK`
(الملف `.github/workflows/android-apk.yml`). البناء بيتم كله على سيرفرات GitHub، ومش محتاج كمبيوتر.

## البناء بيشتغل إمتى؟
- تلقائيًا مع كل `push` على فرع `main`.
- أو يدويًا: تبويب **Actions** ← `Build Android debug APK` ← **Run workflow**.

## تنزيل الـAPK من الهاتف
1. افتح المستودع على GitHub (من المتصفح أو تطبيق GitHub) وادخل على تبويب **Actions**.
2. اختار آخر تشغيلة عليها علامة ✅ خضراء.
3. انزل لآخر الصفحة لقسم **Artifacts** ونزّل الملف **`haraq-debug-apk`** (ملف zip).
4. فك الضغط هتلاقي `haraq-debug.apk`. افتحه على موبايل أندرويد ووافق على "التثبيت من مصادر غير معروفة".

> ملاحظة: لازم تكون مسجل دخول على GitHub عشان تقدر تنزل الـArtifact، وبيفضل متاح 90 يوم.

## الـworkflow بيعمل إيه؟
1. بيجهز Java 17 و Android SDK (build-tools 34).
2. بينزل Godot 4.3 الرسمي وقوالب التصدير.
3. بيعمل keystore مؤقت للتوقيع (debug فقط — مش للنشر على Google Play).
4. بيعمل `--import` للمشروع وبعدها `--export-debug "Android"` باستخدام `export_presets.cfg`.
5. بيرفع الناتج كـArtifact باسم `haraq-debug-apk`.

## لو البناء فشل
افتح التشغيلة الحمرا، واضغط على الخطوة اللي فشلت، وانسخ آخر سطور السجل وابعتها للمراجعة.

## نسخة للنشر (Release)
الـworkflow بقى يدعم نسخة Release موقّعة اختياريًا. الخطوات في [RELEASE_SIGNING_AR.md](RELEASE_SIGNING_AR.md).
