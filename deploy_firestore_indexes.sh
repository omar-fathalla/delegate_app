#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# 🔥 نشر Firestore Indexes - Deploy Firestore Indexes
# ═══════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════"
echo "🔥 نشر Firestore Indexes"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# التحقق من وجود Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI غير مثبت"
    echo "يرجى تثبيته باستخدام: npm install -g firebase-tools"
    exit 1
fi

echo "📋 نشر Firestore Indexes..."
echo ""
echo "⚠️  ملاحظة: قد يستغرق بناء الـ Indexes عدة دقائق"
echo ""

firebase deploy --only firestore:indexes --project practice-firebase-72df1

if [ $? -eq 0 ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "✅ تم نشر Firestore Indexes بنجاح!"
    echo ""
    echo "⏳ الـ Indexes الآن في حالة 'Building'"
    echo "   سيستغرق بناءها من 5-10 دقائق"
    echo ""
    echo "📊 تحقق من الحالة في Firebase Console:"
    echo "   https://console.firebase.google.com/project/practice-firebase-72df1/firestore/indexes"
    echo "═══════════════════════════════════════════════════════════════"
else
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "❌ فشل نشر Firestore Indexes"
    echo "═══════════════════════════════════════════════════════════════"
    exit 1
fi
