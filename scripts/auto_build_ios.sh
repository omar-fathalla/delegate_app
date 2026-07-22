#!/bin/bash
# ============================================
# auto_build_ios.sh
# سكريبت تلقائي لتحديث Build Number وبناء
# وتصدير ورفع iOS IPA
# مع مخرجات مُنسّقة عبر xcpretty
# ============================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"
ARCHIVE_PATH="$PROJECT_DIR/build/ios/Runner.xcarchive"
IPA_DIR="$PROJECT_DIR/build/ios/ipa"
EXPORT_OPTIONS="$PROJECT_DIR/ios/ExportOptions.plist"
LOG_DIR="$PROJECT_DIR/build/ios/logs"
TEAM_ID="TX5G7GZL6T"
FIREBASE_APP_ID="1:564223619997:ios:6a342f9eb34ad80f233574"
FIREBASE_PROJECT="practice-firebase-72df1"

# إضافة مسار xcpretty
export PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH"

# إنشاء مجلد اللوقات
mkdir -p "$LOG_DIR"

# ======== ألوان للمخرجات ========
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ======== تحقق من xcpretty ========
USE_XCPRETTY=false
if command -v xcpretty &> /dev/null; then
  USE_XCPRETTY=true
  echo -e "${DIM}  📋 xcpretty detected — clean logs enabled${NC}"
fi

# ======== دالة تشغيل xcodebuild ========
run_xcodebuild() {
  local step_name="$1"
  shift
  local log_file="$LOG_DIR/${step_name}.log"
  mkdir -p "$LOG_DIR"

  if [ "$USE_XCPRETTY" = true ]; then
    # تشغيل مع xcpretty + حفظ اللوق الكامل
    set -o pipefail
    xcodebuild "$@" 2>&1 | tee "$log_file" | xcpretty --color --report html --output "$LOG_DIR/${step_name}_report.html"
    set +o pipefail
  else
    # بدون xcpretty — عرض آخر 20 سطر + حفظ كامل
    xcodebuild "$@" 2>&1 | tee "$log_file" | tail -20
  fi

  echo -e "${DIM}  📄 Full log: ${log_file}${NC}"
}

# ======== Header ========
echo ""
echo -e "${BLUE}${BOLD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${BLUE}${BOLD}┃  🚀 Tashil Delegate — iOS Auto Build   ┃${NC}"
echo -e "${BLUE}${BOLD}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo ""

START_TIME=$(date +%s)

# ======== الخطوة 1: تحديث Build Number ========
echo -e "${CYAN}${BOLD}━━━ 📦 الخطوة 1/6: تحديث Build Number ━━━${NC}"

CURRENT_VERSION=$(grep "^version:" "$PUBSPEC" | sed 's/version: //')
VERSION_NAME=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)
CURRENT_BUILD=$(echo "$CURRENT_VERSION" | cut -d'+' -f2)
NEW_BUILD=$((CURRENT_BUILD + 1))
NEW_VERSION="${VERSION_NAME}+${NEW_BUILD}"

sed -i '' "s/^version: .*/version: ${NEW_VERSION}/" "$PUBSPEC"

echo -e "  ${DIM}قديم:${NC} ${RED}${CURRENT_VERSION}${NC}"
echo -e "  ${DIM}جديد:${NC} ${GREEN}${NEW_VERSION}${NC}"
echo -e "  ${GREEN}✅ تم التحديث${NC}"
echo ""

# ======== الخطوة 2: تنظيف وتحضير ========
echo -e "${CYAN}${BOLD}━━━ 🧹 الخطوة 2/6: تنظيف المشروع ━━━${NC}"
cd "$PROJECT_DIR"
flutter clean 2>&1 | tail -5
flutter pub get 2>&1 | tail -3
echo -e "  ${GREEN}✅ التنظيف والتحضير تم${NC}"
echo ""

# ======== الخطوة 3: بناء iOS Release ========
echo -e "${CYAN}${BOLD}━━━ 🔨 الخطوة 3/6: بناء iOS Release ━━━${NC}"
flutter build ios --release --no-codesign \
  --build-number="$NEW_BUILD" \
  --build-name="$VERSION_NAME" 2>&1 | tail -5
echo -e "  ${GREEN}✅ بناء iOS Release تم${NC}"
echo ""

# ======== الخطوة 4: Archive مع التوقيع ========
echo -e "${CYAN}${BOLD}━━━ 📁 الخطوة 4/6: Xcode Archive + Signing ━━━${NC}"
run_xcodebuild "archive" \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner -sdk iphoneos \
  -configuration Release archive \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  PROVISIONING_PROFILE=""
echo -e "  ${GREEN}✅ Archive تم بنجاح${NC}"
echo ""

# ======== الخطوة 5: تصدير IPA ========
echo -e "${CYAN}${BOLD}━━━ 📲 الخطوة 5/6: تصدير IPA ━━━${NC}"
rm -rf "$IPA_DIR"
run_xcodebuild "export" \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$IPA_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates
IPA_FILE=$(find "$IPA_DIR" -name "*.ipa" | head -1)
IPA_SIZE=$(du -h "$IPA_FILE" | cut -f1)
echo -e "  ${DIM}ملف:${NC} ${IPA_FILE}"
echo -e "  ${DIM}حجم:${NC} ${IPA_SIZE}"
echo -e "  ${GREEN}✅ IPA تم تصديره${NC}"
echo ""

# ======== الخطوة 6: رفع على Firebase ========
echo -e "${CYAN}${BOLD}━━━ ☁️  الخطوة 6/6: Firebase App Distribution ━━━${NC}"
firebase appdistribution:distribute "$IPA_FILE" \
  --app "$FIREBASE_APP_ID" \
  --release-notes "iOS v${VERSION_NAME} (Build ${NEW_BUILD})" \
  --project "$FIREBASE_PROJECT" 2>&1 | grep -E "✔|✗|⚠|Error"
echo -e "  ${GREEN}✅ تم الرفع على Firebase${NC}"
echo ""

# ======== الملخص ========
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
MINUTES=$(( DURATION / 60 ))
SECONDS=$(( DURATION % 60 ))

echo -e "${BLUE}${BOLD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${BLUE}${BOLD}┃  🎉 BUILD COMPLETE                     ┃${NC}"
echo -e "${BLUE}${BOLD}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
echo -e "${BLUE}┃${NC}  📱 الإصدار: ${GREEN}v${VERSION_NAME}${NC} (Build ${GREEN}${NEW_BUILD}${NC})"
echo -e "${BLUE}┃${NC}  📦 IPA:     ${CYAN}${IPA_SIZE}${NC}"
echo -e "${BLUE}┃${NC}  ⏱  المدة:   ${YELLOW}${MINUTES}m ${SECONDS}s${NC}"
echo -e "${BLUE}┃${NC}  📄 اللوقات: ${DIM}${LOG_DIR}/${NC}"
echo -e "${BLUE}${BOLD}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
