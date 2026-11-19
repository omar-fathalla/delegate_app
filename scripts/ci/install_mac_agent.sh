#!/usr/bin/env bash
# Install scripts/ci/mac_agent.sh as a LaunchAgent of the current user (no sudo).
# It runs every 10 minutes while this user is logged in (the Mac's console user).
#
#   bash scripts/ci/install_mac_agent.sh            # install / update
#   bash scripts/ci/install_mac_agent.sh --remove
set -euo pipefail
LABEL="com.tashil.ci.mac-agent"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
if [[ "${1:-}" == "--remove" ]]; then
  rm -f "$PLIST"
  echo "removed $LABEL"
  exit 0
fi

TOOLS="$HOME/toolchains/flutter-3.44.5/bin:$HOME/.pub-cache/bin:$HOME/.maestro/bin:$HOME/Library/Android/sdk/platform-tools"
mkdir -p "$HOME/Library/LaunchAgents" /Users/Shared/tashil-ci/state
cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>${REPO}/scripts/ci/mac_agent.sh</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>TASHIL_CI_REPO</key><string>${REPO}</string>
		<key>PATH</key><string>${TOOLS}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
		<key>LANG</key><string>en_US.UTF-8</string>
		<key>LC_ALL</key><string>en_US.UTF-8</string>
	</dict>
	<key>StartInterval</key><integer>600</integer>
	<key>RunAtLoad</key><true/>
	<key>ProcessType</key><string>Background</string>
	<key>StandardOutPath</key><string>/Users/Shared/tashil-ci/state/mac_agent.stdout.log</string>
	<key>StandardErrorPath</key><string>/Users/Shared/tashil-ci/state/mac_agent.stderr.log</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST"
launchctl bootstrap "$DOMAIN" "$PLIST"
launchctl print "$DOMAIN/$LABEL" | grep -E "^\s*(state|run interval) ="
echo "OK: $LABEL runs every 10 min from $REPO (log: /Users/Shared/tashil-ci/state/mac_agent.log)"
