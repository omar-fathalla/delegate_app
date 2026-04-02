#!/bin/bash

# 🚀 سكريبت نشر Firestore Rules لنظام المقترحات
# التاريخ: 2 أبريل 2026

echo "=================================================="
echo "🚀 نشر Firestore Rules لنظام المقترحات"
echo "=================================================="
echo ""

# التحقق من وجود Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo "❌ خطأ: Firebase CLI غير مثبت"
    echo "قم بتثبيته عبر: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI موجود"
echo ""

# التحقق من تسجيل الدخول
echo "🔐 التحقق من تسجيل الدخول..."
if ! firebase projects:list &> /dev/null; then
    echo "❌ خطأ: لم تسجل دخول إلى Firebase"
    echo "قم بتسجيل الدخول عبر: firebase login"
    exit 1
fi

echo "✅ تم تسجيل الدخول"
echo ""

# عرض المشروع
PROJECT_ID="practice-firebase-72df1"
echo "📦 المشروع: $PROJECT_ID"
echo ""

# تأكيد النشر
read -p "هل تريد نشر Firestore Rules؟ (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ تم الإلغاء"
    exit 0
fi

echo ""
echo "📤 جاري نشر Firestore Rules..."
echo ""

# نشر Firestore Rules فقط
firebase deploy --only firestore:rules --project $PROJECT_ID

# التحقق من النجاح
if [ $? -eq 0 ]; then
    echo ""
    echo "=================================================="
    echo "✅ تم نشر Firestore Rules بنجاح!"
    echo "=================================================="
    echo ""
    echo "📋 الخطوات التالية:"
    echo "1. افتح Firebase Console للتحقق من القواعد"
    echo "2. اختبر التطبيق للتأكد من عمل كل شيء"
    echo "3. راقب السجلات للتأكد من عدم وجود أخطاء"
    echo ""
    echo "🔗 روابط مفيدة:"
    echo "- Firebase Console: https://console.firebase.google.com/project/$PROJECT_ID/firestore/rules"
    echo "- Usage: https://console.firebase.google.com/project/$PROJECT_ID/firestore/usage"
    echo ""
else
    echo ""
    echo "=================================================="
    echo "❌ فشل نشر Firestore Rules"
    echo "=================================================="
    echo ""
    echo "💡 نصائح:"
    echo "1. تحقق من أن ملف firestore.rules موجود"
    echo "2. تحقق من صحة الصياغة في الملف"
    echo "3. تحقق من اتصالك بالإنترنت"
    echo "4. حاول مرة أخرى"
    echo ""
    exit 1
fi
