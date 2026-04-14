#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# 🔍 البحث عن الشركة بالكود 512 في Firestore
# ═══════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════"
echo "🔍 البحث عن الشركة بالكود 512"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# التحقق من وجود Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI غير مثبت"
    echo "يرجى تثبيته باستخدام: npm install -g firebase-tools"
    exit 1
fi

PROJECT_ID="practice-firebase-72df1"

echo "📦 المشروع: $PROJECT_ID"
echo ""
echo "⚠️  ملاحظة: هذا السكريبت يتطلب صلاحيات Firebase Admin"
echo ""

# استخدام Firebase CLI للبحث
echo "🔍 جاري البحث في Firestore..."
echo ""

# ملاحظة: Firebase CLI لا يدعم الاستعلامات المباشرة
# يجب استخدام Firebase Console أو كتابة سكريبت Node.js

echo "═══════════════════════════════════════════════════════════════"
echo "📋 للبحث عن الشركة، استخدم إحدى الطرق التالية:"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "1️⃣  Firebase Console:"
echo "   https://console.firebase.google.com/project/$PROJECT_ID/firestore/data"
echo ""
echo "2️⃣  في التطبيق:"
echo "   - سجل دخول كـ Super Admin أو Org Admin"
echo "   - اذهب إلى قائمة الشركات"
echo "   - ابحث عن الكود 512"
echo ""
echo "3️⃣  استخدم سكريبت Dart:"
echo "   flutter run test_marketing_search.dart"
echo ""
echo "═══════════════════════════════════════════════════════════════"
