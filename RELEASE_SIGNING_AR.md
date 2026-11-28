# نسخة Release موقّعة (اختياري)

الـworkflow بيبني دايمًا `haraq-debug-apk`. لو ضفت الـsecrets اللي تحت، هيبني كمان **`haraq-release-apk`** موقّع بمفتاحك. لو الـsecrets مش موجودة، البناء بيكمّل عادي بالـdebug بس.

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

ملاحظة: جوجل بلاي النهارده بتطلب ملف AAB، لكن ده محتاج إعداد Gradle build في Godot. الموجود هنا APK موقّع ينفع للتوزيع المباشر.
