#!/bin/bash

# 🔐 سكريبت التحقق من iOS Signing
# يتحقق من جميع متطلبات التوقيع الرقمي

echo "🔍 التحقق من iOS Signing..."
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

# Function to check
check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $1${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ $1${NC}"
        ((FAILED++))
    fi
}

# 1. Check Xcode
echo "📱 التحقق من Xcode..."
xcodebuild -version > /dev/null 2>&1
check "Xcode مثبت"

# 2. Check Certificates
echo ""
echo "🔐 التحقق من Certificates..."
CERT_COUNT=$(security find-identity -v -p codesigning | grep "Apple Distribution" | grep "TX5G7GZL6T" | wc -l)
if [ $CERT_COUNT -gt 0 ]; then
    echo -e "${GREEN}✅ Distribution Certificate موجود${NC}"
    security find-identity -v -p codesigning | grep "Apple Distribution" | grep "TX5G7GZL6T"
    ((PASSED++))
else
    echo -e "${RED}❌ Distribution Certificate غير موجود${NC}"
    echo "   يجب إنشاء Certificate من: https://developer.apple.com/account/resources/certificates/list"
    ((FAILED++))
fi

# 3. Check Provisioning Profiles
echo ""
echo "🎫 التحقق من Provisioning Profiles..."
PROFILE_DIR=~/Library/MobileDevice/Provisioning\ Profiles
if [ -d "$PROFILE_DIR" ]; then
    PROFILE_COUNT=$(ls -1 "$PROFILE_DIR"/*.mobileprovision 2>/dev/null | wc -l)
    if [ $PROFILE_COUNT -gt 0 ]; then
        echo -e "${GREEN}✅ وجد $PROFILE_COUNT Provisioning Profile(s)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ لا توجد Provisioning Profiles${NC}"
        echo "   يجب تحميل Profile من: https://developer.apple.com/account/resources/profiles/list"
        ((FAILED++))
    fi
else
    echo -e "${RED}❌ مجلد Provisioning Profiles غير موجود${NC}"
    ((FAILED++))
fi

# 4. Check Bundle ID in Xcode project
echo ""
echo "📦 التحقق من Bundle ID..."
if [ -f "ios/Runner.xcodeproj/project.pbxproj" ]; then
    BUNDLE_ID=$(grep -m 1 "PRODUCT_BUNDLE_IDENTIFIER" ios/Runner.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/' | tr -d ' ')
    if [ "$BUNDLE_ID" == "io.flutter.delegate_app" ]; then
        echo -e "${GREEN}✅ Bundle ID صحيح: $BUNDLE_ID${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ Bundle ID غير صحيح: $BUNDLE_ID${NC}"
        echo "   يجب أن يكون: io.flutter.delegate_app"
        ((FAILED++))
    fi
else
    echo -e "${RED}❌ ملف Xcode project غير موجود${NC}"
    ((FAILED++))
fi

# 5. Check Team ID
echo ""
echo "👥 التحقق من Team ID..."
if [ -f "ios/Runner.xcodeproj/project.pbxproj" ]; then
    TEAM_ID=$(grep -m 1 "DEVELOPMENT_TEAM" ios/Runner.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/' | tr -d ' ')
    if [ "$TEAM_ID" == "TX5G7GZL6T" ]; then
        echo -e "${GREEN}✅ Team ID صحيح: $TEAM_ID${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠️  Team ID: $TEAM_ID${NC}"
        echo "   يجب أن يكون: TX5G7GZL6T"
    fi
fi

# 6. Check ExportOptions.plist
echo ""
echo "📝 التحقق من ExportOptions.plist..."
if [ -f "ios/ExportOptions.plist" ]; then
    echo -e "${GREEN}✅ ExportOptions.plist موجود${NC}"
    
    # Check method
    METHOD=$(grep -A 1 "<key>method</key>" ios/ExportOptions.plist | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>/\1/')
    if [ "$METHOD" == "app-store" ]; then
        echo -e "${GREEN}   ✅ method: app-store${NC}"
    else
        echo -e "${YELLOW}   ⚠️  method: $METHOD (يجب أن يكون app-store)${NC}"
    fi
    
    # Check teamID
    TEAM_ID_PLIST=$(grep -A 1 "<key>teamID</key>" ios/ExportOptions.plist | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>/\1/')
    if [ "$TEAM_ID_PLIST" == "TX5G7GZL6T" ]; then
        echo -e "${GREEN}   ✅ teamID: TX5G7GZL6T${NC}"
    else
        echo -e "${YELLOW}   ⚠️  teamID: $TEAM_ID_PLIST${NC}"
    fi
    
    ((PASSED++))
else
    echo -e "${RED}❌ ExportOptions.plist غير موجود${NC}"
    echo "   يجب إنشاء الملف في: ios/ExportOptions.plist"
    ((FAILED++))
fi

# 7. Check CocoaPods
echo ""
echo "☕ التحقق من CocoaPods..."
if [ -f "ios/Podfile.lock" ]; then
    echo -e "${GREEN}✅ CocoaPods مثبت${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️  CocoaPods غير مثبت${NC}"
    echo "   شغل: cd ios && pod install"
fi

# 8. Check Flutter
echo ""
echo "🐦 التحقق من Flutter..."
flutter --version > /dev/null 2>&1
check "Flutter مثبت"

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 النتيجة:"
echo -e "   ${GREEN}✅ نجح: $PASSED${NC}"
echo -e "   ${RED}❌ فشل: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 جميع الفحوصات نجحت! جاهز للبناء.${NC}"
    echo ""
    echo "الخطوة التالية:"
    echo "  flutter build ios --release"
    exit 0
else
    echo -e "${RED}⚠️  يوجد $FAILED مشكلة. راجع الأخطاء أعلاه.${NC}"
    echo ""
    echo "للمساعدة، راجع:"
    echo "  IOS_SIGNING_COMPLETE_GUIDE.md"
    exit 1
fi
