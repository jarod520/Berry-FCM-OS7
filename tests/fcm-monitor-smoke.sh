#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MON="${BERRY_MONITOR_SCRIPT:-$ROOT/module/bin/fcm-monitor.sh}"
TMP="$(mktemp -d)"
cleanup() {
    [ -z "${monitor_pid:-}" ] || { kill "$monitor_pid" 2>/dev/null || :; wait "$monitor_pid" 2>/dev/null || :; }
    rm -rf "$TMP"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

fail() { echo "FAIL: $*" >&2; exit 1; }
grep -Fq 'kernel-visible GMS UID MCS sockets are the sole connection-state evidence' "$MON" ||
    fail "monitor must declare kernel socket evidence as its only state source"
if grep -Eiq 'dumpsys|parse_mcs|native_close_fallback|force_native|gms_stopped' "$MON"; then
    fail "dumpsys/native state decision path remains in monitor"
fi

mkdir -p "$TMP/bin" "$TMP/data"
cat > "$TMP/bin/id" <<'MOCK'
#!/bin/sh
if [ "$1" = "-u" ]; then echo 0; else exec /usr/bin/id "$@"; fi
MOCK
cat > "$TMP/bin/cmd" <<'MOCK'
#!/bin/sh
case "$*" in
  "package list packages -U com.google.android.gms")
    echo 'package:com.google.android.gms uid:10200';;
  *) exit 1;;
esac
MOCK
cat > "$TMP/bin/ss" <<'MOCK'
#!/bin/sh
mode="$(cat "$MCS_MODE_FILE")"
case "$mode" in
  connected) echo 'ESTAB 0 0 192.168.1.8:45000 142.250.157.188:5228 uid:10200 ino:100';;
  connecting) echo 'SYN-SENT 0 0 192.168.1.8:45000 142.250.157.188:5228 uid:10200 ino:101';;
  absent) echo 'TIME-WAIT 0 0 192.168.1.8:45000 142.250.157.188:5228 uid:10200 ino:102';;
  stalled)
    echo 'ESTAB 0 0 192.168.1.8:45000 142.250.157.188:5228 uid:10200 ino:103 unacked:0 retrans:0/0'
    echo ' cubic wscale:7,7 rto:204 rtt:20/2 unacked:1 retrans:3/10'
    ;;
  idle)
    echo 'ESTAB 0 0 192.168.1.8:45000 142.250.157.188:5228 uid:10200 ino:104 unacked:0 retrans:0/0'
    echo ' cubic wscale:7,7 rto:204 rtt:20/2 lastrcv:1800001'
    ;;
  unknown|proc_connected) echo 'ESTAB 0 0 192.168.1.8:45000 142.250.157.188:5228';;
  *) exit 2;;
esac
MOCK
cat > "$TMP/bin/am" <<'MOCK'
#!/bin/sh
echo "$*" >> "$MCS_AM_LOG"
if [ "${MCS_AM_FAIL:-0}" = 1 ] ||
   { [ -n "${MCS_AM_FAIL_ACTION:-}" ] && printf '%s' "$*" | grep -Fq "$MCS_AM_FAIL_ACTION"; }; then
    echo 'Permission Denial: fixture' >&2
    exit 1
fi
echo 'Broadcast completed: result=0'
MOCK
cat > "$TMP/bin/nslookup" <<'MOCK'
#!/bin/sh
exit 1
MOCK
cat > "$TMP/bin/dumpsys" <<'MOCK'
#!/bin/sh
echo "$*" >> "$MCS_DUMPSYS_LOG"
exit 91
MOCK
cat > "$TMP/bin/date" <<'MOCK'
#!/bin/sh
if [ "$1" = "+%s" ]; then cat "$MCS_CLOCK"; else exec /bin/date "$@"; fi
MOCK
chmod +x "$TMP/bin/"*

echo 1 > "$TMP/data/enabled"
echo 10000 > "$TMP/uptime"
echo test-boot > "$TMP/bootid"
echo connected > "$TMP/mode"
: > "$TMP/am.log"
: > "$TMP/dumpsys.log"
echo 1700010000 > "$TMP/epoch"

export PATH="$TMP/bin:/usr/bin:/bin"
export BERRY_FCM_TEST_MODE=1 BERRY_FCM_DATA="$TMP/data"
export BERRY_UPTIME_FILE="$TMP/uptime" BERRY_BOOT_ID_FILE="$TMP/bootid"
export BERRY_PROC_NET_DIR="$TMP/proc-unavailable"
export BERRY_SS_BIN="$TMP/bin/ss" BERRY_CMD_BIN="$TMP/bin/cmd" BERRY_AM_BIN="$TMP/bin/am"
export MCS_MODE_FILE="$TMP/mode" MCS_AM_LOG="$TMP/am.log"
export MCS_DUMPSYS_LOG="$TMP/dumpsys.log" MCS_CLOCK="$TMP/epoch"

settime() {
    printf '%s\n' "$1" > "$TMP/uptime"
    printf '%s\n' "$((1700010000+$1-10000))" > "$TMP/epoch"
}
run() { sh "$MON" "$1"; }
requests() { [ "$(wc -l < "$TMP/am.log" | tr -d ' ')" = "$1" ] || fail "expected $1 recovery commands"; }
assert_json() {
    python3 - "$1" "$2" <<'PY'
import json,sys
data=json.loads(sys.argv[1])
key,value=sys.argv[2].split("=",1)
assert str(data[key]) == value, (key,data.get(key),value)
PY
}

# A live GMS-owned MCS TCP socket is positive transport evidence.
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_source=gms_socket
assert_json "$j" fcm_native_duration=-1
assert_json "$j" fcm_native_reason=not_used
requests 0

# A persistent SYN-SENT connection must not remain "unknown" forever.
echo connecting > "$TMP/mode"
settime 10001
j="$(run status)"
assert_json "$j" fcm_state=connecting
settime 10061
export MCS_AM_FAIL_ACTION=GCM_RECONNECT
run monitor >/dev/null
unset MCS_AM_FAIL_ACTION
requests 1
grep -Fq 'GCM_RECONNECT' "$TMP/am.log" || fail "first recovery stage missing"

# If the first request does not restore transport, continue through every next action.
settime 10091
run monitor >/dev/null
requests 2
grep -Fq 'MCS_HEARTBEAT' "$TMP/am.log" || fail "second recovery stage missing"
settime 10136
run monitor >/dev/null
requests 3
grep -Fq 'ACTION_HEARTBEAT_NOW' "$TMP/am.log" || fail "third recovery stage missing"
settime 10196
run monitor >/dev/null
requests 4
grep -Fq 'GTALK_HEARTBEAT' "$TMP/am.log" || fail "fourth recovery stage missing"

# A later kernel socket observation, not broadcast exit status, confirms recovery.
echo connected > "$TMP/mode"
settime 10197
run monitor >/dev/null
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_last_result=restored
requests 4

# TCP_INFO can identify an established-but-blackholed MCS socket.
echo stalled > "$TMP/mode"
settime 10198
j="$(run status)"
assert_json "$j" fcm_state=disconnected
assert_json "$j" fcm_tcp_hint=stalled
settime 10213
run monitor >/dev/null
requests 5
echo connected > "$TMP/mode"
settime 10214
run monitor >/dev/null
j="$(run status)"
assert_json "$j" fcm_state=connected
requests 5

# A connected socket with no TCP data received for 30 minutes is also suspected stalled.
echo idle > "$TMP/mode"
settime 10215
j="$(run status)"
assert_json "$j" fcm_state=disconnected
assert_json "$j" fcm_tcp_hint=stalled
settime 10230
run monitor >/dev/null
requests 6
echo connected > "$TMP/mode"
settime 10231
run monitor >/dev/null
j="$(run status)"
assert_json "$j" fcm_state=connected
requests 6

# Continuous, successfully-readable absence is timed; one absent sample is not enough.
echo absent > "$TMP/mode"
settime 10257
j="$(run status)"
assert_json "$j" fcm_state=unknown
requests 6
settime 10302
j="$(run status)"
assert_json "$j" fcm_state=disconnected
settime 10317
run monitor >/dev/null
requests 7

# An unreadable ownership/source sample is unavailable, not falsely disconnected.
echo unknown > "$TMP/mode"
settime 10318
j="$(run status)"
assert_json "$j" fcm_state=unknown
requests 7

# When ss cannot expose UID, the root-readable /proc TCP tables are the fallback.
mkdir -p "$TMP/proc"
cat > "$TMP/proc/tcp" <<'PROC'
  sl  local_address rem_address   st tx_queue:rx_queue tr:tm->when retrnsmt   uid  timeout inode
   0: 0801A8C0:C350 8EFA9D8E:146C 01 00000000:00000000 00:00000000 00000000 10200 0 12345
PROC
cat > "$TMP/proc/tcp6" <<'PROC'
  sl  local_address rem_address   st tx_queue:rx_queue tr:tm->when retrnsmt   uid  timeout inode
PROC
export BERRY_PROC_NET_DIR="$TMP/proc"
echo proc_connected > "$TMP/mode"
settime 10319
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_source=gms_socket
assert_json "$j" fcm_tcp_hint=established
requests 7

[ ! -s "$TMP/dumpsys.log" ] || fail "dumpsys was invoked by the monitor"
echo "PASS: kernel-only detection, bounded absence confirmation, TCP_INFO retransmission and 30-minute receive-idle recovery, four-stage recovery, and dump independence"
