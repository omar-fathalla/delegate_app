#!/bin/bash

# 🔧 سكريبت إعادة بناء التطبيق على iOS
# يستخدم بعد إصلاح مشكلة الفروع

echo "🧹 تنظيف المشروع..."
flutter clean

echo "📦 تحميل التبعيات..."
flutter pub get

echo "🍎 تحديث CocoaPods..."
cd ios
pod repo update
pod install
cd ..

echo "🔨 بناء التطبيق..."
flutter build ios --debug --no-codesign

echo "✅ تم! الآن يمكنك تشغيل التطبيق:"
echo "   flutter run"
