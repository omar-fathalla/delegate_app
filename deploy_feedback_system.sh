#!/bin/bash

# 🚀 نشر نظام المقترحات - Feedback System Deployment
# تاريخ الإنشاء: 1 أبريل 2026

echo "🚀 بدء نشر نظام المقترحات..."
echo ""

# التحقق من وجود Firebase CLI
if ! command -v firebase &> /dev/null
then
    echo "❌ Firebase CLI غير مثبت"
    echo "يرجى تثبيته عبر: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI موجود"
echo ""

# 1. نشر Firestore Rules
echo "📋 نشر Firestore Rules..."
firebase deploy --only firestore:rules --project practice-firebase-72df1
if [ $? -eq 0 ]; then
    echo "✅ تم نشر Firestore Rules بنجاح"
else
    echo "❌ فشل نشر Firestore Rules"
    exit 1
fi
echo ""

# 2. نشر Storage Rules
echo "📦 نشر Storage Rules..."
firebase deploy --only storage --project practice-firebase-72df1
if [ $? -eq 0 ]; then
    echo "✅ تم نشر Storage Rules بنجاح"
else
    echo "❌ فشل نشر Storage Rules"
    exit 1
fi
echo ""

# 3. نشر Firestore Indexes
echo "🔍 نشر Firestore Indexes..."
firebase deploy --only firestore:indexes --project practice-firebase-72df1
if [ $? -eq 0 ]; then
    echo "✅ تم نشر Firestore Indexes بنجاح"
else
    echo "❌ فشل نشر Firestore Indexes"
    exit 1
fi
echo ""

echo "🎉 تم نشر نظام المقترحات بنجاح!"
echo ""
echo "📝 الخطوات التالية:"
echo "1. تشغيل التطبيق: flutter run"
echo "2. اختبار إرسال مقترح من المندوب"
echo "3. اختبار عرض المقترحات من Super Admin"
echo ""
echo "📚 للمزيد من المعلومات، راجع:"
echo "   lib/features/feedback/DEPLOYMENT_COMPLETE.md"
echo ""
