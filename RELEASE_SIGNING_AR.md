# نسخة Release موقّعة + ملف AAB لجوجل بلاي

الـworkflow فيه شغلانتين منفصلين:
- **android**: بيبني دايمًا `haraq-debug-apk`، ولو الـsecrets موجودة بيبني كمان **`haraq-release-apk`** موقّع.
- **aab** (من 0.7.0): بيبني ملف **Android App Bundle** بـ Gradle. من غير secrets بيطلع `haraq-debug-aab` (موقّع بمفتاح debug، للتجربة بس — جوجل بلاي بترفضه). ولو الـsecrets موجودة بيطلع **`haraq-release-aab`** موقّع بمفتاحك وجاهز للرفع.

الشغلانتين منفصلين، فلو بناء الـAAB وقع لأي سبب، الـAPK بيفضل شغال.

> ⚠️ المفتاح (keystore) ده هو هويتك على جوجل بلاي. لو ضاع مش هتقدر تحدّث اللعبة. احتفظ بنسخة منه برا الريبو، وعمره ما يتعمله commit.

## 1) اعمل المفتاح (مرة واحدة على جهازك)
محتاج Java (فيها `keytool`):
```bash
keytool -genkeypair -v -keystore haraq-release.keystore -alias haraq \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "باسورد_قوي" -keypass "نفس_الباسورد" \
  -dname "CN=Khaled Abdalla, O=HARAQ, C=EG"
```
مهم: خلّي **باسورد المخزن وباسورد المفتاح واحد**، لأن Godot 4.3 بياخد باسورد واحد بس.

## 2) حوّله لـ base64
- لينكس: `base64 -w0 haraq-release.keystore > keystore.txt`
- ماك: `base64 -i haraq-release.keystore -o keystore.txt`
- ويندوز (PowerShell): `[Convert]::ToBase64String([IO.File]::ReadAllBytes("haraq-release.keystore")) > keystore.txt`

## 3) ضيف الـsecrets في GitHub
الريبو ← Settings ← Secrets and variables ← Actions ← New repository secret:

| الاسم | القيمة |
|---|---|
| `HARAQ_KEYSTORE_BASE64` | محتوى `keystore.txt` كله |
| `HARAQ_KEYSTORE_PASSWORD` | الباسورد |
| `HARAQ_KEY_ALIAS` | `haraq` (أو الاسم اللي اخترته) |

## 4) شغّل البناء
اعمل push أو من تبويب Actions اضغط Run workflow. هتلاقي artifact اسمه `haraq-release-apk`. الـworkflow بيتأكد من التوقيع بـ `apksigner verify` وبيمسح ملف المفتاح من جهاز البناء بعد ما يخلص.

الـAPK الموقّع ينفع للتوزيع المباشر (تبعته لحد وينزّله). لجوجل بلاي استخدم الـAAB.

## 5) الرفع على Google Play Console
1. اعمل حساب مطوّر على https://play.google.com/console (رسوم مرة واحدة 25 دولار، وهتحتاج تأكيد هويتك). الحسابات الشخصية الجديدة لازم تعمل **اختبار مغلق (closed testing) مع 12 مختبِر على الأقل لمدة 14 يوم** قبل ما تقدر تنشر للكل.
2. **Create app**: الاسم «حَرَق - HARAQ»، اللغة الافتراضية العربية، النوع Game، مجاني.
3. **Play App Signing**: سيبه شغال (ده الافتراضي). المفتاح بتاعك `haraq-release.keystore` بيبقى «upload key»، وجوجل بتمضي النسخة النهائية بمفتاحها. لو ضاع الـupload key تقدر تطلب تغييره من الكونسول.
4. نزّل الـartifact `haraq-release-aab` من تبويب Actions، وفك الـzip، هتلاقي `haraq-release.aab`.
5. **Testing ← Internal testing ← Create new release**، وارفع الـ`.aab`. اكتب ملاحظات النسخة بالعربي.
6. كمّل **App content**: سياسة الخصوصية (لينك صفحة بسيطة؛ اللعبة مش بتجمع بيانات)، الإعلانات: لا، **Content rating** (استبيان IARC: عنف حربي غير واقعي، من غير دم)، الجمهور المستهدف (13+)، وData safety: «لا يتم جمع أو مشاركة بيانات». ملاحظة: اللعب الجماعي على نفس الواي فاي بيستخدم إذن INTERNET، بس من غير سيرفر خارجي.
7. **Store listing**: وصف قصير وطويل، أيقونة 512×512، صورة مميزة 1024×500، وصورتين على الأقل من اللعبة.
8. بعد ما الاختبار الداخلي يشتغل، رقّي نفس النسخة لـ Closed testing ← ثم Production.

**كل تحديث جديد لازم رقم `version/code` يزيد** في `export_presets.cfg` (في الـpreset الاتنين «Android» و«Android AAB»)، وإلا جوجل بلاي هترفض الملف. حاليًا version/code = 7 (النسخة 0.7.0).
