#!/bin/bash
# سكريبت تشغيل build_runner لتوليد ملفات freezed و json_serializable
# استخدم: bash scripts/run_build_runner.sh

set -e

echo "📦 جاري تثبيت الحزم..."
flutter pub get

echo "🔨 جاري تشغيل build_runner..."
dart run build_runner build --delete-conflicting-outputs

echo "✅ تم توليد جميع الملفات بنجاح!"
echo ""
echo "📋 الملفات المولدة:"
find lib -name "*.g.dart" -o -name "*.freezed.dart" | sort
