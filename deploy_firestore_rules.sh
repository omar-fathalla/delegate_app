#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# 🔥 نشر Firestore Rules - Deploy Firestore Rules
# ═══════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════"
echo "🔥 نشر Firestore Rules"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# التحقق من وجود Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI غير مثبت"
    echo "يرجى تثبيته باستخدام: npm install -g firebase-tools"
    exit 1
fi

echo "📋 نشر Firestore Rules..."
firebase deploy --only firestore:rules --project practice-firebase-72df1

if [ $? -eq 0 ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "✅ تم نشر Firestore Rules بنجاح!"
    echo "═══════════════════════════════════════════════════════════════"
else
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "❌ فشل نشر Firestore Rules"
    echo "═══════════════════════════════════════════════════════════════"
    exit 1
fi
