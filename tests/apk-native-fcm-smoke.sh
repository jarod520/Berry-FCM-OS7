#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MON="$ROOT/app/src/main/assets/fcm-monitor.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/data"
cat > "$TMP/bin/cmd" <<'MOCK'
#!/bin/sh
case "$*" in
  "package list packages -U com.google.android.gms") [ "${MCS_UID_FAIL:-0}" = 1 ] && exit 1; echo 'package:com.google.android.gms uid:10200';;
  "package path --user 0 "*) echo 'package:/data/app/base.apk';;
  "package unstop --user 0 "*) exit "${MCS_UNSTOP_RC:-0}";;
  *) exit 1;;
esac
MOCK
cat > "$TMP/bin/pm" <<'MOCK'
#!/bin/sh
case "$*" in
  "list packages -U com.google.android.gms") [ "${MCS_UID_FAIL:-0}" = 1 ] && exit 1; echo 'package:com.google.android.gms uid:10200';;
  "path --user 0 "*) echo 'package:/data/app/base.apk';;
  *) exit 1;;
esac
MOCK
cat > "$TMP/bin/ss" <<'MOCK'
#!/bin/sh
case "${MCS_SS_MODE:-absent}" in
  connected) echo 'ESTAB 0 0 10.0.0.2:45000 142.250.157.188:5228 uid:10200 ino:101';;
  connecting) echo 'SYN-SENT 0 1 10.0.0.2:45000 142.250.157.188:5228 uid:10200 ino:102';;
  untrusted443) echo 'ESTAB 0 0 10.0.0.2:45000 1.1.1.1:443 uid:10200 ino:103';;
  no_uid) echo 'ESTAB 0 0 10.0.0.2:45000 1.1.1.1:443';;
  *) echo 'ESTAB 0 0 10.0.0.2:45000 1.1.1.1:443 uid:1000 ino:104';;
esac
MOCK
cat > "$TMP/bin/am" <<'MOCK'
#!/bin/sh
echo "$*" >> "$MCS_AM_LOG"
if [ "${MCS_AM_FAIL:-0}" = 1 ]; then
    echo 'Permission Denial: fixture'
    exit 1
fi
echo 'Broadcast completed: result=0'
MOCK
cat > "$TMP/bin/id" <<'MOCK'
#!/bin/sh
if [ "$*" = "-u" ]; then echo "${MCS_SENDER_UID:-0}"; else /usr/bin/id "$@"; fi
MOCK
cat > "$TMP/bin/date" <<'MOCK'
#!/bin/sh
if [ "$*" = '+%s' ]; then cat "$MCS_CLOCK"; else /bin/date "$@"; fi
MOCK
cat > "$TMP/bin/dumpsys" <<'MOCK'
#!/bin/sh
echo called >> "$MCS_DUMP_LOG"
exit 99
MOCK
cat > "$TMP/bin/mv" <<'MOCK'
#!/bin/sh
last=
for arg in "$@"; do last="$arg"; done
case "$last" in
  */mcs-monitor.state) [ "${MCS_STATE_MV_FAIL:-0}" = 1 ] && exit 1;;
  */mcs-evidence) [ "${MCS_EVIDENCE_MV_FAIL:-0}" = 1 ] && exit 1;;
esac
exec /bin/mv "$@"
MOCK
chmod +x "$TMP/bin/"*
echo 10000 > "$TMP/uptime"
echo test-boot > "$TMP/bootid"
echo 1 > "$TMP/data/enabled"
: > "$TMP/am.log"
: > "$TMP/dumpsys.log"
export PATH="$TMP/bin:/usr/bin:/bin"
export BERRY_FCM_TEST_MODE=1 BERRY_FCM_DATA="$TMP/data"
export BERRY_UPTIME_FILE="$TMP/uptime" BERRY_BOOT_ID_FILE="$TMP/bootid"
export MCS_AM_LOG="$TMP/am.log" MCS_DUMP_LOG="$TMP/dumpsys.log" MCS_CLOCK="$TMP/epoch"
export BERRY_FCM_AUTO=1 BERRY_AUTO_GATE=ready
settime() { printf '%s\n' "$1" > "$TMP/uptime"; printf '%s\n' "$((1700000000+$1))" > "$MCS_CLOCK"; }
run() { sh "$MON" "$1"; }
requests() { [ "$(wc -l < "$MCS_AM_LOG" | tr -d ' ')" = "$1" ]; }
assert_json() {
    python3 - "$1" "$2" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); k,v=sys.argv[2].split('=',1)
assert str(j[k])==v,(k,j[k],v,j)
PY
}
settime 10000

# A verified GMS-owned MCS socket is positive transport evidence.
export MCS_SS_MODE=connected
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_source=gms_socket
assert_json "$j" fcm_tcp_hint=established
awk -F'|' 'NF == 24 {ok=1} END {exit !ok}' "$TMP/data/mcs-monitor.state"

# Wall-clock changes must not age or reset fresh monotonic socket samples.
settime 10010
run status
echo 1800000000 > "$MCS_CLOCK"
j="$(run snapshot)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_sample_age_seconds=0
! grep -q '|sample_gap|' "$TMP/data/mcs-monitor-events.log"
echo 1600000000 > "$MCS_CLOCK"
j="$(run snapshot)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_sample_age_seconds=0

# A real monotonic sampling gap must still reset continuity even if wall time is unchanged.
echo 1700000020 > "$MCS_CLOCK"
echo 10020 > "$TMP/uptime"
run status
echo 10120 > "$TMP/uptime"
j="$(run status)"
assert_json "$j" fcm_state=connected
grep -q '|sample_gap|' "$TMP/data/mcs-monitor-events.log"

# Failed atomic commits must fail the sample and remove temporary files.
rm -f "$TMP/data/mcs-monitor.state" "$TMP/data/mcs-evidence"
export MCS_STATE_MV_FAIL=1
if run status >/dev/null 2>&1; then echo 'state rename failure was ignored' >&2; exit 1; fi
test -z "$(find "$TMP/data" -name 'mcs-monitor.state.*' -print -quit)"
unset MCS_STATE_MV_FAIL
export MCS_EVIDENCE_MV_FAIL=1
if run status >/dev/null 2>&1; then echo 'evidence rename failure was ignored' >&2; exit 1; fi
test -z "$(find "$TMP/data" -name 'mcs-evidence.*' -print -quit)"
unset MCS_EVIDENCE_MV_FAIL
rm -f "$TMP/data/mcs-monitor.state" "$TMP/data/mcs-evidence"

# Unrelated GMS HTTPS and redacted UID ownership remain unknown, never down.
export MCS_SS_MODE=untrusted443
j="$(run status)"
assert_json "$j" fcm_state=unknown
export MCS_SS_MODE=no_uid
j="$(run status)"
assert_json "$j" fcm_state=unknown

# Legacy dump-derived connected/disconnected state is invalidated on upgrade.
printf 'test-boot|connected|old|0|10000|1700010000|0|0|0|0|0|none|0|0|tcp5228|old-peer|10000|none|0|0|0|0|0\n' > "$TMP/data/mcs-monitor.state"
printf 'gms|202|ERR_IO_RST_HB|none|none|not_evaluated\n' > "$TMP/data/mcs-evidence"
j="$(run snapshot)"
assert_json "$j" fcm_state=unknown
assert_json "$j" fcm_source=unavailable
export MCS_SS_MODE=connected
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_source=gms_socket

# Root absence needs 60 seconds of continuous verified socket-table evidence,
# then 15 seconds of a fresh down observation and a second confirmation read.
rm -f "$TMP/data/mcs-monitor.state" "$TMP/data/mcs-evidence"
: > "$MCS_AM_LOG"
export MCS_SS_MODE=absent MCS_SENDER_UID=0
settime 11000
run monitor
requests 0
j="$(run snapshot)"
assert_json "$j" fcm_state=unknown
assert_json "$j" fcm_source=gms_socket_absence_pending
settime 11060
run monitor
requests 0
j="$(run snapshot)"
assert_json "$j" fcm_state=disconnected
assert_json "$j" fcm_source=gms_socket_absence
settime 11075
run monitor
requests 1
test "$(cat "$MCS_AM_LOG")" = 'broadcast --user 0 -a com.google.android.intent.action.GCM_RECONNECT -p com.google.android.gms'
j="$(run snapshot)"
assert_json "$j" fcm_last_result=requested
assert_json "$j" fcm_recovery_decision=requested

# UID 2000 cannot classify an incomplete socket table as disconnected.
rm -f "$TMP/data/mcs-monitor.state" "$TMP/data/mcs-evidence"
: > "$MCS_AM_LOG"
export MCS_SENDER_UID=2000
settime 12000
run monitor
settime 12060
run monitor
requests 0
j="$(run snapshot)"
assert_json "$j" fcm_state=unknown

# UID lookup failure and failed broadcasts do not invoke dump or fabricate recovery.
rm -f "$TMP/data/mcs-monitor.state" "$TMP/data/mcs-evidence"
export MCS_SENDER_UID=0 MCS_UID_FAIL=1
settime 13000
j="$(run status)"
assert_json "$j" fcm_state=unknown
unset MCS_UID_FAIL
export MCS_SS_MODE=absent MCS_AM_FAIL=1
settime 13100
run monitor
settime 13160
run monitor
settime 13175
run monitor
j="$(run snapshot)"
assert_json "$j" fcm_last_result=failed
test ! -s "$MCS_DUMP_LOG"
echo 'PASS: APK monitor uses kernel socket evidence only; dumpsys is never invoked'
