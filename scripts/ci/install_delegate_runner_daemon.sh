#!/usr/bin/env bash
# Run the delegate_app self-hosted runner (tashil-delegate-mac) as a LaunchDaemon.
#
# Why: it was installed as a LaunchAgent for user delegate-ci, which only runs
# while delegate-ci has a login session. After 2026-11-13 nobody was logged in
# as delegate-ci, so the runner went offline and CI stopped. The Data-Sharing
# runners (tashil-ci) use LaunchDaemons and stayed up; this mirrors them.
#
# Usage (needs admin password):
#   sudo bash scripts/ci/install_delegate_runner_daemon.sh          # install + start
#   sudo bash scripts/ci/install_delegate_runner_daemon.sh --remove # stop + remove
#   RUNNER_NAME=tashil-delegate-mac-2 RUNNER_DIR=/Users/delegate-ci/actions-runner-2 \
#     sudo -E bash scripts/ci/install_delegate_runner_daemon.sh     # extra runner
set -euo pipefail

RUNNER_USER="delegate-ci"
RUNNER_HOME="/Users/${RUNNER_USER}"
RUNNER_NAME="${RUNNER_NAME:-tashil-delegate-mac}"
RUNNER_DIR="${RUNNER_DIR:-${RUNNER_HOME}/actions-runner}"
LABEL="actions.runner.omar-fathalla-delegate_app.${RUNNER_NAME}"
DAEMON="/Library/LaunchDaemons/${LABEL}.plist"
AGENT="${RUNNER_HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="${RUNNER_HOME}/Library/Logs"
RUNNER_UID="$(id -u "$RUNNER_USER")"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run with sudo" >&2
  exit 1
fi

stop_all() {
  launchctl bootout "system/${LABEL}" 2>/dev/null || true
  launchctl bootout "gui/${RUNNER_UID}/${LABEL}" 2>/dev/null || true
  launchctl bootout "user/${RUNNER_UID}/${LABEL}" 2>/dev/null || true
}

if [[ "${1:-}" == "--remove" ]]; then
  stop_all
  rm -f "$DAEMON"
  echo "removed $DAEMON"
  exit 0
fi

[[ -x "${RUNNER_DIR}/runsvc.sh" ]] || { echo "missing ${RUNNER_DIR}/runsvc.sh" >&2; exit 1; }

stop_all
# Keep the old LaunchAgent from starting a second listener on next login.
if [[ -f "$AGENT" ]]; then
  mv "$AGENT" "${AGENT}.disabled"
  echo "disabled LaunchAgent -> ${AGENT}.disabled"
fi

mkdir -p "$LOG_DIR"
chown "${RUNNER_USER}:staff" "$LOG_DIR"

# Clean PATH: nothing from /Users/fathalla (EACCES for delegate-ci, see ci.yml).
cat > "$DAEMON" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>${LABEL}</string>
	<key>UserName</key><string>${RUNNER_USER}</string>
	<key>GroupName</key><string>staff</string>
	<key>WorkingDirectory</key><string>${RUNNER_DIR}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>${RUNNER_DIR}/runsvc.sh</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>HOME</key><string>${RUNNER_HOME}</string>
		<key>USER</key><string>${RUNNER_USER}</string>
		<key>LOGNAME</key><string>${RUNNER_USER}</string>
		<key>LANG</key><string>en_US.UTF-8</string>
		<key>LC_ALL</key><string>en_US.UTF-8</string>
		<key>PATH</key><string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
		<key>JAVA_HOME</key><string>/Applications/Android Studio.app/Contents/jbr/Contents/Home</string>
	</dict>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ThrottleInterval</key><integer>10</integer>
	<key>ProcessType</key><string>Background</string>
	<key>StandardOutPath</key><string>${LOG_DIR}/${LABEL}.stdout.log</string>
	<key>StandardErrorPath</key><string>${LOG_DIR}/${LABEL}.stderr.log</string>
</dict>
</plist>
PLIST

chown root:wheel "$DAEMON"
chmod 644 "$DAEMON"
plutil -lint "$DAEMON"
launchctl bootstrap system "$DAEMON"
sleep 3
launchctl print "system/${LABEL}" | grep -E "^\s*(state|pid) ="
echo "OK: ${LABEL} runs as ${RUNNER_USER} at boot. Logs: ${LOG_DIR}"
