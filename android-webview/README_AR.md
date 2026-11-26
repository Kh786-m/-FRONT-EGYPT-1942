# WAR FRONT: EGYPT 1942 — Android wrapper

هذه حزمة **مصدر مشروع Android** وليست APK. تحتوي نسخة اللعبة التجريبية HTML ضمن assets وتعرضها في WebView بوضع أفقي وملء الشاشة، دون الحاجة إلى اتصال إنترنت.

## البناء
1. افتح المجلد في Android Studio أو بيئة بناء سحابية موثوقة تدعم Gradle وAndroid SDK.
2. استخدم JDK 17 وAndroid SDK 35.
3. شغّل `gradle assembleDebug` (أو Build APK من Android Studio). تحتاج Gradle مثبتاً؛ لم يُضمّن Gradle Wrapper داخل هذه الحزمة.
4. عند نجاح البناء يكون الملف عادةً `app/build/outputs/apk/debug/app-debug.apk`.
5. ثبّت ملف APK على جهاز Android بعد التحقق منه.

## ملاحظات
- هذا تغليف WebView للعبة المتصفح التجريبية، وليس تحويل مشروع Unreal Engine إلى تطبيق أصلي.
- لم يتم تجميع أو اختبار APK هنا لعدم توفر Android SDK/Gradle.
- targetSdk 28 مُختار لتقليل مشكلات توافق العرض المحلي في WebView التجريبي؛ يجب تحديثه وتحديث سياسات الأمان قبل النشر على المتاجر.
- تجنب رفع المشروع إلى خدمة غير موثوقة. قد تتطلب خدمات البناء السحابية تسجيل حساب.
