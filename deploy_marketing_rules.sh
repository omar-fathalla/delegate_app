#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# 🚀 نشر Firestore Rules - Marketing Access
# ═══════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════"
echo "🔐 نشر Firestore Rules - Marketing Access"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# التحقق من وجود Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI غير مثبت"
    echo "يرجى تثبيته باستخدام: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI موجود"
echo ""

# التحقق من تسجيل الدخول
echo "🔍 التحقق من تسجيل الدخول..."
if ! firebase projects:list &> /dev/null; then
    echo "❌ لم تسجل دخول إلى Firebase"
    echo "يرجى تسجيل الدخول باستخدام: firebase login"
    exit 1
fi

echo "✅ تم تسجيل الدخول"
echo ""

# عرض المشروع
PROJECT_ID="practice-firebase-72df1"
echo "📦 المشروع: $PROJECT_ID"
echo ""

# نشر Firestore Rules
echo "🚀 جاري نشر Firestore Rules..."
echo ""

firebase deploy --only firestore:rules --project $PROJECT_ID

# التحقق من النجاح
if [ $? -eq 0 ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "✅ تم نشر Firestore Rules بنجاح!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "📋 التغييرات المنشورة:"
    echo "  ✅ إضافة صلاحيات قراءة للتسويق (Marketing)"
    echo "  ✅ إضافة قاعدة collectionGroup للشركات"
    echo "  ✅ تحديث تعليقات القواعد"
    echo ""
    echo "🔗 روابط مفيدة:"
    echo "  • Firebase Console: https://console.firebase.google.com/project/$PROJECT_ID/firestore/rules"
    echo "  • التوثيق: FIRESTORE_RULES_MARKETING_ACCESS.md"
    echo ""
else
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "❌ فشل نشر Firestore Rules"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "يرجى التحقق من:"
    echo "  1. اتصالك بالإنترنت"
    echo "  2. صلاحياتك على المشروع"
    echo "  3. صحة ملف firestore.rules"
    echo ""
    exit 1
fi
