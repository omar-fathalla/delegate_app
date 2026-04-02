#!/bin/bash

# ========================================
# نشر Storage Rules إلى Firebase
# ========================================

echo "🚀 نشر Storage Rules..."
echo ""

# التحقق من تسجيل الدخول
echo "📝 التحقق من تسجيل الدخول..."
firebase login:list

# نشر Storage Rules
echo ""
echo "📤 نشر Storage Rules..."
firebase deploy --only storage --project practice-firebase-72df1

echo ""
echo "✅ تم النشر بنجاح!"
echo ""
echo "🔍 تحقق من Firebase Console:"
echo "https://console.firebase.google.com/project/practice-firebase-72df1/storage/rules"
