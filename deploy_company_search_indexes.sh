#!/bin/bash

# 🔍 نشر فهارس البحث عن الشركات واختبار البحث
# Deploy Company Search Indexes and Test Search

echo "🚀 نشر فهارس Firestore للبحث عن الشركات..."
echo "🚀 Deploying Firestore indexes for company search..."

# نشر الفهارس
firebase deploy --only firestore:indexes --project practice-firebase-72df1

if [ $? -eq 0 ]; then
    echo "✅ تم نشر الفهارس بنجاح!"
    echo "✅ Indexes deployed successfully!"
    echo ""
    echo "📋 الفهارس المنشورة:"
    echo "📋 Deployed indexes:"
    echo "   - companies.code (ASCENDING)"
    echo ""
    echo "⏳ قد يستغرق بناء الفهارس عدة دقائق..."
    echo "⏳ Index building may take several minutes..."
    echo ""
    
    # انتظار قليل ثم اختبار البحث
    echo "🔍 اختبار البحث عن الشركات..."
    echo "🔍 Testing company search..."
    
    # تشغيل سكريبت الاختبار
    dart run test_company_search.dart
    
    echo ""
    echo "🔗 تحقق من حالة الفهارس في Firebase Console:"
    echo "🔗 Check index status in Firebase Console:"
    echo "   https://console.firebase.google.com/project/practice-firebase-72df1/firestore/indexes"
    echo ""
    echo "📱 الآن يمكنك اختبار البحث في التطبيق:"
    echo "📱 Now you can test search in the app:"
    echo "   1. flutter run"
    echo "   2. سجل دخول كـ Super Admin"
    echo "   3. اذهب للوحة الإدارة"
    echo "   4. اضغط 'البحث عن الشركات'"
    echo "   5. ابحث عن '1048' أو '6047'"
else
    echo "❌ فشل في نشر الفهارس!"
    echo "❌ Failed to deploy indexes!"
    exit 1
fi