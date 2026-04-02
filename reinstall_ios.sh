#!/bin/bash

# 🔄 سكريبت إعادة تثبيت التطبيق على iOS
# يحذف التطبيق القديم ويثبت النسخة الجديدة

echo "🧹 تنظيف المشروع..."
flutter clean

echo "📦 تحميل التبعيات..."
flutter pub get

echo "🍎 تحديث CocoaPods..."
cd ios
pod deintegrate
pod install
cd ..

echo "🗑️  حذف التطبيق من الجهاز..."
echo "⚠️  يرجى حذف التطبيق يدوياً من iPhone"
echo "   1. اضغط مطولاً على أيقونة التطبيق"
echo "   2. اختر 'Remove App'"
echo "   3. اضغط 'Delete App'"
echo ""
read -p "اضغط Enter بعد حذف التطبيق..."

echo "🔨 بناء وتثبيت التطبيق الجديد..."
flutter run --release

echo "✅ تم!"
