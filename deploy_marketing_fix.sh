#!/bin/bash

# 🚀 نشر إصلاح Marketing User
# التاريخ: 10 أبريل 2026

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 نشر إصلاح Marketing User"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# التحقق من وجود Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI غير مثبت"
    echo "قم بتثبيته باستخدام: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI موجود"
echo ""

# التحقق من تسجيل الدخول
echo "🔐 التحقق من تسجيل الدخول..."
if ! firebase projects:list &> /dev/null; then
    echo "❌ لم تقم بتسجيل الدخول"
    echo "قم بتسجيل الدخول باستخدام: firebase login"
    exit 1
fi

echo "✅ تم تسجيل الدخول"
echo ""

# نشر Firestore Rules
echo "📤 نشر Firestore Rules..."
firebase deploy --only firestore:rules --project practice-firebase-72df1

if [ $? -eq 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ تم النشر بنجاح!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📋 الخطوات التالية:"
    echo ""
    echo "1. افتح التطبيق"
    echo "2. سجل دخول كـ Marketing User:"
    echo "   - رقم الهاتف: 01211857725"
    echo "   - كلمة المرور: eYFTHU5p"
    echo "3. تحقق من أنه يمكنك:"
    echo "   ✅ تسجيل الدخول بنجاح"
    echo "   ✅ رؤية الشركات"
    echo "   ✅ رؤية المندوبين"
    echo ""
    echo "📚 للمزيد من المعلومات، راجع: MARKETING_USER_FIX.md"
    echo ""
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ فشل النشر"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🔍 تحقق من:"
    echo "1. اتصالك بالإنترنت"
    echo "2. صلاحياتك في Firebase Console"
    echo "3. ملف firestore.rules صحيح"
    echo ""
    exit 1
fi
