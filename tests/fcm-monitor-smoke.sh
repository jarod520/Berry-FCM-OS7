#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MON="${BERRY_MONITOR_SCRIPT:-$ROOT/module/bin/fcm-monitor.sh}"
grep -Fq '"$TOYBOX_BIN" timeout --foreground -k 1 3 nslookup "$host"' "$MON"
grep -Fq 'timeout --foreground 3 nslookup "$host"' "$MON"
grep -Fq '*"Run PROG."*) timeout 3 nslookup "$host"' "$MON"
grep -Fq '"$@" -xn 9 sh "$0" "$command" --locked "$lock_result"' "$MON"
grep -Fq '(run_monitor_command "$command")' "$MON"
grep -Fq '无法登记 GMS monitor 进程身份，拒绝启动未受监管的检查' "$MON"
grep -Fq 'monitor_rc=14' "$MON"
grep -Fq 'if ! write_lock_owner; then' "$MON"
grep -Fq 'owner_tmp="$LOCK_OWNER.tmp.$lock_owner_pid"' "$MON"
grep -Fq 'rm -f "$owner_tmp"' "$MON"
! grep -Fq 'write_lock_owner || :' "$MON"
grep -Fq 'case "$lock_result" in "$DATA"/mcs-monitor.lock.result.*)' "$MON"
TMP="$(mktemp -d)"
cleanup() {
    if [ -n "${first_monitor_pid:-}" ]; then
        kill "$first_monitor_pid" 2>/dev/null || :
        wait "$first_monitor_pid" 2>/dev/null || :
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/data"
cat > "$TMP/bin/dumpsys" <<'MOCK'
#!/bin/sh
case "$*" in
  *"activity service"*)
    [ -z "${MCS_DUMPSYS_LOG:-}" ] || echo "$*" >> "$MCS_DUMPSYS_LOG"
    if [ -n "${MCS_DUMPSYS_BLOCK:-}" ]; then
      echo started > "$MCS_DUMPSYS_BLOCK"
      /bin/sleep "${MCS_DUMPSYS_BLOCK_SECONDS:-2}"
    fi
    if [ -n "${MCS_NEXT_FIXTURE:-}" ] && [ -f "$MCS_NEXT_FIXTURE" ]; then
      cat "$MCS_FIXTURE"
      mv "$MCS_NEXT_FIXTURE" "$MCS_FIXTURE"
    else cat "$MCS_FIXTURE"; fi;;
  *"package"*) echo "    User 0: ceDataInode=1 installed=true stopped=${MCS_STOPPED:-false} suspended=false hidden=false";;
esac
MOCK
cat > "$TMP/bin/cmd" <<'MOCK'
#!/bin/sh
echo 'package:com.google.android.gms uid:10200'
MOCK
cat > "$TMP/bin/ss" <<'MOCK'
#!/bin/sh
if [ "${MCS_SS_MODE:-connected}" = unknown ]; then
    echo 'ESTAB 0 0 192.168.1.8:45000 142.250.157.188:5228'
elif [ "${MCS_SS_MODE:-connected}" = mtalk443 ]; then
    echo 'ESTAB 0 0 192.168.1.8:45000 142.250.157.188:443 uid:10200 ino:204'
elif [ "${MCS_SS_MODE:-connected}" = connecting ]; then
    echo 'SYN-SENT 0 0 192.168.1.8:45000 142.250.157.188:5228 uid:10200 ino:203'
elif [ "${MCS_SS_MODE:-connected}" = absent ]; then
    echo 'TIME-WAIT 0 0 192.168.1.8:45000 142.250.157.188:5228 uid:10200 ino:202'
else
    echo 'ESTAB 0 0 192.168.1.8:45000 142.250.157.188:5228 uid:10200 ino:101'
fi
MOCK
cat > "$TMP/bin/nslookup" <<'MOCK'
#!/bin/sh
echo "$1" >> "$MCS_DNS_LOG"
if [ "${MCS_DNS_SUCCESS:-0}" = 1 ]; then
    echo 'Address: 142.250.157.188'
    exit 0
fi
exit 1
MOCK
cat > "$TMP/bin/am" <<'MOCK'
#!/bin/sh
echo "$*" >> "$MCS_AM_LOG"
if [ "${MCS_AM_FAIL:-0}" = 1 ]; then
    echo 'Permission Denial: fixture'
    echo 'Broadcast completed: result=0'
    exit 1
fi
echo 'Broadcast completed: result=0'
# Model a reconnect that actually leads to a new native connected sample.
if [ -n "${MCS_AM_CONNECTED_FIXTURE:-}" ]; then
    cp "$MCS_AM_CONNECTED_FIXTURE" "$MCS_FIXTURE"
fi
MOCK
cat > "$TMP/bin/id" <<'MOCK'
#!/bin/sh
if [ "$*" = "-u" ]; then
    echo "${MCS_UID:-0}"
else /usr/bin/id "$@"; fi
MOCK
cat > "$TMP/bin/date" <<'MOCK'
#!/bin/sh
if [ "$*" = '+%s' ]; then cat "$MCS_CLOCK"; else /bin/date "$@"; fi
MOCK
chmod +x "$TMP/bin/"*
echo 10000 > "$TMP/uptime"
echo test-boot > "$TMP/bootid"
echo 1 > "$TMP/data/enabled"
: > "$TMP/am.log"
: > "$TMP/dns-default.log"
export MCS_DNS_LOG="$TMP/dns-default.log"
export PATH="$TMP/bin:/usr/bin:/bin"
export BERRY_FCM_TEST_MODE=1 BERRY_FCM_DATA="$TMP/data"
export BERRY_UPTIME_FILE="$TMP/uptime" BERRY_BOOT_ID_FILE="$TMP/bootid"
export BERRY_PROC_NET_DIR="$TMP/proc-unavailable"
export MCS_FIXTURE="$TMP/dump" MCS_AM_LOG="$TMP/am.log" MCS_CLOCK="$TMP/epoch"
settime() { printf '%s\n' "$1" > "$TMP/uptime"; printf '%s\n' "$((1700000000+$1))" > "$MCS_CLOCK"; }
settime 10000
run() { sh "$MON" "$1"; }
requests() { [ "$(wc -l < "$MCS_AM_LOG" | tr -d ' ')" = "$1" ]; }
assert_json() {
    python3 - "$1" "$2" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); k,v=sys.argv[2].split('=',1)
assert str(j[k])==v,(k,j[k],v,j)
PY
}
printf "%s\n" "DeviceID: [fixture]" "connected=mtalk.google.com/142.250.157.188,port=5228" "connectTime=03:22/00:00" > "$MCS_FIXTURE"
j="$(run status)"; assert_json "$j" fcm_state=connected; assert_json "$j" fcm_native_duration=202
test ! -e "$BERRY_FCM_DATA/mcs-monitor.lock.owner"
printf '%s\n' 'DeviceID: [fixture]' 'connected=mtalk.google.com/[2001:db8::1],port=443' 'connectTime=00:03/00:00' > "$MCS_FIXTURE"
j="$(run status)"; assert_json "$j" fcm_state=connected; assert_json "$j" 'fcm_remote=mtalk.google.com/[2001:db8::1]:443'
run reconnect; requests 0

export MCS_SS_MODE=unknown
printf "%s\n" "Permission Denial" > "$MCS_FIXTURE"
j="$(run status)"; assert_json "$j" fcm_state=unknown; assert_json "$j" fcm_tcp_hint=unknown
run monitor; run reconnect; requests 0
echo "PASS: native state is authoritative; TCP alone is auxiliary"

settime 10030
printf "%s\n" "DeviceID: [fixture]" "Not connected" > "$MCS_FIXTURE"
run monitor; requests 0
settime 10060
export MCS_NEXT_FIXTURE="$TMP/next"
printf "%s\n" "DeviceID: [fixture]" "connected=mtalk.google.com/142.250.157.188,port=5228" "connectTime=00:01/00:00" > "$MCS_NEXT_FIXTURE"
run monitor; requests 0
j="$(run snapshot)"; assert_json "$j" fcm_recovery_decision=confirmation_changed
unset MCS_NEXT_FIXTURE

# A fresh native timer after resume permits a double check in the same window.
settime 10360
printf "%s\n" "DeviceID: [fixture]" "Not connected" "disconnectTime=02:00/00:00" > "$MCS_FIXTURE"
run monitor; requests 1
test "$(tail -n 1 "$MCS_AM_LOG")" = "broadcast --user 0 -a com.google.android.intent.action.GCM_RECONNECT -p com.google.android.gms"
j="$(run snapshot)"; assert_json "$j" fcm_recovery_decision=requested; assert_json "$j" fcm_state=disconnected
run events | grep -q "|sample_gap|"
settime 10390; run reconnect; requests 1
settime 10660; run monitor; requests 2
settime 10720; run monitor; requests 2
settime 11260; run monitor; requests 3
printf "%s\n" "DeviceID: [fixture]" "connected=mtalk.google.com/142.250.157.188,port=5228" "connectTime=00:01/00:00" > "$MCS_FIXTURE"
settime 11290
j="$(run status)"; assert_json "$j" fcm_last_result=restored; assert_json "$j" fcm_retry_streak=0
echo "PASS: suspend gap, double confirmation, UID 0 broadcast, shared backoff and native restoration"

settime 11600
printf "%s\n" "No services match" > "$MCS_FIXTURE"
export MCS_SS_MODE=unknown MCS_STOPPED=true
run monitor; requests 3
# A stopped GMS package is expected to have no MCS socket; absence must not
# be promoted to a network outage or trigger an automatic reconnect.
settime 11601
export MCS_SS_MODE=absent
run monitor; requests 3
j="$(run snapshot)"
assert_json "$j" fcm_state=unknown
assert_json "$j" fcm_tcp_hint=absent
assert_json "$j" fcm_native_reason=gms_stopped
assert_json "$j" fcm_recovery_decision=gms_stopped_unknown
[ "$(awk -F'|' '{print $23}' "$BERRY_FCM_DATA/mcs-monitor.state")" = 0 ]
# Manual recovery also rechecks the stopped condition after a deferred native poll.
unset BERRY_FCM_TEST_MODE
settime 11641
run reconnect; requests 3
j="$(run snapshot)"
assert_json "$j" fcm_recovery_decision=gms_stopped_unknown
export BERRY_FCM_TEST_MODE=1 MCS_SS_MODE=unknown
unset MCS_STOPPED
echo 0 > "$BERRY_FCM_DATA/enabled"; run monitor; requests 3
echo 1 > "$BERRY_FCM_DATA/enabled"
export MCS_UID=2000
if run reconnect; then echo "non-root request unexpectedly accepted" >&2; exit 1; fi
unset MCS_UID
requests 3
settime 11642
printf "%s\n" "DeviceID: [fixture]" "Not connected" "disconnectTime=01:00/00:00" > "$MCS_FIXTURE"
export MCS_AM_FAIL=1; run monitor; requests 4
j="$(run snapshot)"; assert_json "$j" fcm_recovery_decision=request_failed
unset MCS_AM_FAIL
echo "PASS: stopped GMS, opt-out, non-root rejection and failed-broadcast classification"

(
    flock -xn 9
    if run reconnect; then echo "concurrent request unexpectedly acquired lock" >&2; exit 1; fi
) 9>"$BERRY_FCM_DATA/mcs-monitor.lock"
requests 4
echo "PASS: daemon and WebUI share a single lock"
# A manager-provided BusyBox can exist while omitting the flock applet.
# With no system flock on PATH, the same monitor must still read GMS.
mkdir -p "$TMP/compatible"
for bin in awk cat cp cut grep head mkdir mv rm rmdir sed sleep tail tr wc; do
    ln -s "$(command -v "$bin")" "$TMP/compatible/$bin"
done
cat > "$TMP/bin/busybox-minimal" <<'MOCK'
#!/bin/sh
[ "$1" = --list ] && printf '%s\n' awk mkdir
MOCK
chmod +x "$TMP/bin/busybox-minimal"
export BERRY_KSU_BUSYBOX="$TMP/bin/busybox-minimal"
printf '%s\n' 'DeviceID: [fixture]' 'connected=mtalk.google.com/142.250.157.188,port=5228' 'connectTime=00:30/00:00' > "$MCS_FIXTURE"
settime 11630
j="$(PATH="$TMP/bin:$TMP/compatible" /bin/sh "$MON" status)"
assert_json "$j" fcm_state=connected
[ ! -e "$BERRY_FCM_DATA/mcs-monitor-test-boot.lockdir" ]
echo "PASS: native reading works with a KernelSU BusyBox lacking flock"
# Reclaim stale no-flock lock directory after owner process was killed.
lockdir="$BERRY_FCM_DATA/mcs-monitor-test-boot.lockdir"
mkdir -p "$lockdir"
echo 999999 > "$lockdir/pid"
echo 1 > "$lockdir/starttime"
j="$(PATH="$TMP/bin:$TMP/compatible" /bin/sh "$MON" status)"
assert_json "$j" fcm_state=connected
[ ! -e "$lockdir" ]
echo "PASS: stale lockdir owner is reclaimed"
# Also recover a directory interrupted before its owner metadata was written.
mkdir -p "$lockdir"
j="$(PATH="$TMP/bin:$TMP/compatible" /bin/sh "$MON" status)"
assert_json "$j" fcm_state=connected
[ ! -e "$lockdir" ]
echo "PASS: incomplete lockdir initialization is recoverable"

# If owner publication fails, neither lock backend may run an untracked monitor.
cat > "$TMP/bin/mv" <<'MOCK'
#!/bin/sh
dest=
for arg do dest="$arg"; done
case "$dest" in "$BERRY_FCM_DATA/mcs-monitor.lock.owner") exit 1;; esac
exec /bin/mv "$@"
MOCK
chmod +x "$TMP/bin/mv"
export BERRY_FCM_DATA="$TMP/owner-fail-flock-data" MCS_DUMPSYS_LOG="$TMP/owner-fail-flock-dumpsys.log"
mkdir -p "$BERRY_FCM_DATA"
: > "$MCS_DUMPSYS_LOG"
if sh "$MON" monitor > "$TMP/owner-fail-flock.out" 2>&1; then
    echo "monitor unexpectedly ran without a published owner" >&2; exit 1
fi
grep -q "无法登记 GMS monitor 进程身份" "$TMP/owner-fail-flock.out"
test ! -s "$MCS_DUMPSYS_LOG"
test ! -e "$BERRY_FCM_DATA/mcs-monitor.lock.owner"
set -- "$BERRY_FCM_DATA"/mcs-monitor.lock.owner.tmp.*
test ! -e "$1"
echo "PASS: flock owner publication failure refuses untracked monitor"

export BERRY_FCM_DATA="$TMP/owner-fail-dir-data" MCS_DUMPSYS_LOG="$TMP/owner-fail-dir-dumpsys.log"
mkdir -p "$BERRY_FCM_DATA"
: > "$MCS_DUMPSYS_LOG"
if PATH="$TMP/bin:$TMP/compatible" /bin/sh "$MON" monitor > "$TMP/owner-fail-dir.out" 2>&1; then
    echo "directory-lock monitor unexpectedly ran without a published owner" >&2; exit 1
fi
grep -q "无法登记 GMS monitor 进程身份" "$TMP/owner-fail-dir.out"
test ! -s "$MCS_DUMPSYS_LOG"
test ! -e "$BERRY_FCM_DATA/mcs-monitor-test-boot.lockdir"
test ! -e "$BERRY_FCM_DATA/mcs-monitor.lock.owner"
set -- "$BERRY_FCM_DATA"/mcs-monitor.lock.owner.tmp.*
test ! -e "$1"
echo "PASS: directory-lock owner publication failure releases lock and refuses monitor"

# Background patrol samples sockets every cycle but refreshes native GMS state only once per minute.
export BERRY_FCM_DATA="$TMP/native-poll-data" MCS_DUMPSYS_LOG="$TMP/native-poll.log" MCS_SS_MODE=connected
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
: > "$MCS_DUMPSYS_LOG"
: > "$MCS_AM_LOG"
unset BERRY_FCM_TEST_MODE
settime 70000
printf "%s\n" "DeviceID: [fixture]" "connected=mtalk.google.com/142.250.157.188,port=5228" "connectTime=00:10/00:00" > "$MCS_FIXTURE"
run monitor
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d " ")" = 1 ]
settime 70020
printf "%s\n" "DeviceID: [fixture]" "Not connected" > "$MCS_FIXTURE"
run monitor
assert_json "$(run snapshot)" fcm_state=connected
assert_json "$(run snapshot)" fcm_source=gms_socket
! grep -q "|sample_unknown|reason=not_polled" "$BERRY_FCM_DATA/mcs-monitor-events.log"
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d " ")" = 1 ]
settime 70030
export MCS_SS_MODE=absent
run monitor
assert_json "$(run snapshot)" fcm_state=connected
assert_json "$(run snapshot)" fcm_source=gms_socket
settime 70040
export MCS_SS_MODE=unknown
run monitor
assert_json "$(run snapshot)" fcm_state=connected
assert_json "$(run snapshot)" fcm_source=gms_socket
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d " ")" = 1 ]
export MCS_SS_MODE=connected
settime 70060
run monitor
assert_json "$(run snapshot)" fcm_state=disconnected
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d " ")" = 2 ]
settime 70070
run monitor
assert_json "$(run snapshot)" fcm_state=disconnected
assert_json "$(run snapshot)" fcm_source=gms
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d " ")" = 2 ]
grep -q '|socket_native_conflict|' "$BERRY_FCM_DATA/mcs-monitor-events.log"
requests 0
settime 70072
export MCS_SS_MODE=absent
run monitor
assert_json "$(run snapshot)" fcm_state=disconnected
assert_json "$(run snapshot)" fcm_source=gms
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d " ")" = 2 ]
settime 70074
export MCS_SS_MODE=unknown
run monitor
assert_json "$(run snapshot)" fcm_state=disconnected
assert_json "$(run snapshot)" fcm_source=gms
settime 70080
j="$(run status)"
assert_json "$j" fcm_state=disconnected
assert_json "$j" fcm_source=gms
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d " ")" = 2 ]
export MCS_SS_MODE=connected
: > "$MCS_AM_LOG"
settime 70140
printf "%s\n" "DeviceID: [fixture]" "Not connected" "disconnectTime=00:20/00:00" > "$MCS_FIXTURE"
run monitor
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d " ")" = 4 ]
requests 1
assert_json "$(run snapshot)" fcm_recovery_decision=requested
export BERRY_FCM_TEST_MODE=1
echo 'PASS: native GMS dumps are rate-limited while socket samples remain continuous'

# ActivityManager can return only wrapper lines with exit code zero.
export MCS_NEXT_FIXTURE="$TMP/next-state-dump" MCS_DUMPSYS_LOG="$TMP/dumpsys.log"
: > "$MCS_DUMPSYS_LOG"
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '  (no client detail)' > "$MCS_FIXTURE"
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService' 'Server: Connected' > "$MCS_NEXT_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=connected
grep -q 'sample_retry|first=no_current_state retry_rc=0 state=connected' "$BERRY_FCM_DATA/mcs-monitor-events.log"
unset MCS_NEXT_FIXTURE
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '  (no client detail)' > "$MCS_FIXTURE"
settime 70160
j="$(run status)"
assert_json "$j" fcm_state=unknown
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d " ")" = 3 ]
echo 'PASS: wrapper-only dump retries once, then rate-limits duplicate dumps to 60 seconds'

# OriginOS GMS current-state fields used by newer GMS builds.
export BERRY_FCM_DATA="$TMP/client-state-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
settime 13000
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService 1234abcd pid=321 user=0' '  Is client connected: true' '  connectTime=03:22/00:00' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_source=gms
assert_json "$j" fcm_native_duration=202
# Neighboring services must not override the GMS service's explicit state.
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService 1234abcd pid=321 user=0' '  Is client connected: true' '  connectTime=03:22/00:00' 'SERVICE com.example.other/.PushService pid=999' '  Is client connected: false' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=connected
printf '%s\n' 'SERVICE com.example.other/.PushService pid=999' '  Is client connected: false' 'SERVICE com.google.android.gms/.gcm.GcmService 1234abcd pid=321 user=0' '  Is client connected: true' '  connectTime=03:22/00:00' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=connected
# A legacy preamble must not contaminate the scoped GMS service state.
printf '%s\n' 'DeviceID: [legacy]' 'Not connected' 'disconnectTime=01:00/00:00' 'SERVICE com.google.android.gms/.gcm.GcmService 1234abcd pid=321 user=0' '  Is client connected: true' '  connectTime=03:22/00:00' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_native_duration=202
# Conflicting explicit values in the target service remain unknown.
export BERRY_FCM_DATA="$TMP/conflict-state-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService' '  Is client connected: true' '  Is client connected: false' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=unknown
grep -Fq 'if(gms_block_seen) multiple_gms_blocks=1' "$ROOT/module/bin/fcm-monitor.sh"
grep -Fq 'if(multiple_gms_blocks || conflict || state=="" || state=="unknown" ||' "$ROOT/module/bin/fcm-monitor.sh"
# A repeated GMS service block must not inherit Connected from the prior block.
export BERRY_FCM_DATA="$TMP/repeated-empty-gms-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService pid=321' '  Is client connected: true' 'SERVICE com.google.android.gms/.gcm.GcmService pid=322' '  (no current client state)' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=unknown
# A repeated GMS service block with contradictory status must remain unknown.
export BERRY_FCM_DATA="$TMP/repeated-conflict-gms-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService pid=321' '  Is client connected: true' 'SERVICE com.google.android.gms/.gcm.GcmService pid=322' '  Is client connected: false' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=unknown
export BERRY_FCM_DATA="$TMP/client-state-data"
settime 13001
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService 1234abcd pid=321 user=0' '  Is client connected: false' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=disconnected
assert_json "$j" fcm_source=gms
settime 13002
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService pid=321' '  Is client connected:true' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=connected
settime 13003
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService pid=321' '  Is client connected:false' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=disconnected
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService 1234abcd pid=321 user=0' '  Not connected' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=disconnected
assert_json "$j" fcm_source=gms
settime 13017
run monitor
requests 2
grep -q '|reconnect_requested|auto UID=0 GCM_RECONNECT' "$BERRY_FCM_DATA/mcs-monitor-events.log"
echo 'PASS: explicit GMS client state triggers confirmed auto recovery'
export BERRY_FCM_DATA="$TMP/data"

# When a wrapper-only dump has no current fields, a Root-visible exact MCS
# socket supplies positive connected evidence instead of leaving the card blank.
settime 11700
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '  (no client detail)' > "$MCS_FIXTURE"
export MCS_SS_MODE=connected
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_source=gms_socket
assert_json "$j" fcm_tcp_hint=established
echo 'PASS: exact GMS MCS TCP evidence resolves wrapper-only state'

# A recent explicit GMS down sample plus root-visible MCS socket absence must
# still recover when subsequent dumps contain only ActivityManager wrappers.
export MCS_SS_MODE=absent
settime 11800
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService' 'Server: Not connected' > "$MCS_FIXTURE"
run monitor; requests 2
settime 11820
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '  (no client detail)' > "$MCS_FIXTURE"
j="$(run monitor)"; requests 2
assert_json "$(run snapshot)" fcm_state=unknown
settime 11860
j="$(run monitor)"; requests 3
j="$(run snapshot)"
assert_json "$j" fcm_state=disconnected
assert_json "$j" fcm_source=gms_socket_fallback
assert_json "$j" fcm_recovery_decision=requested
grep -q '|tcp_absence_confirmed|' "$BERRY_FCM_DATA/mcs-monitor-events.log"
grep -q '|reconnect_requested|auto UID=0 GCM_RECONNECT' "$BERRY_FCM_DATA/mcs-monitor-events.log"
unset MCS_SS_MODE
echo 'PASS: recent native down + root TCP absence recovers through unreadable dumps'

# A single unverified GMS-owned 443 socket in tcp6 must outrank an empty tcp
# table. Otherwise the empty IPv4 table falsely reports total MCS absence.
mkdir -p "$TMP/proc-mixed"
printf '%s\n' 'sl local_address rem_address st tx_queue:rx_queue tr:tm->when retrnsmt uid timeout inode' > "$TMP/proc-mixed/tcp"
printf '%s\n' 'sl local_address rem_address st tx_queue:rx_queue tr:tm->when retrnsmt uid timeout inode' \
  '0: 00000000000000000000000000000000:C001 8EFA0000000000000000000000000000:01BB 01 00000000:00000000 00:00000000 00000000 10200 0 12345' > "$TMP/proc-mixed/tcp6"
export BERRY_PROC_NET_DIR="$TMP/proc-mixed"
export MCS_SS_MODE=unknown
settime 32000
j="$(run status)"
assert_json "$j" fcm_state=unknown
assert_json "$j" fcm_tcp_hint=unknown
echo 'PASS: unverified IPv6 443 evidence is not downgraded to IPv4 absence'

# The /proc/net/tcp6 fallback must also recognize an established exact MCS port.
mkdir -p "$TMP/proc-positive"
printf '%s\n' 'sl local_address rem_address st tx_queue:rx_queue tr:tm->when retrnsmt uid timeout inode' > "$TMP/proc-positive/tcp"
printf '%s\n' 'sl local_address rem_address st tx_queue:rx_queue tr:tm->when retrnsmt uid timeout inode' \
  '0: 00000000000000000000000000000000:C001 8EFA0000000000000000000000000000:146C 01 00000000:00000000 00:00000000 00000000 10200 0 12346' > "$TMP/proc-positive/tcp6"
export BERRY_PROC_NET_DIR="$TMP/proc-positive"
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_source=gms_socket
assert_json "$j" fcm_transport=tcp5228
echo 'PASS: IPv6 kernel TCP table confirms GMS-owned MCS 5228'
export BERRY_PROC_NET_DIR="$TMP/proc-unavailable"

# Unknown native state plus continuous GMS UID socket absence must age into
# a confirmed outage even when no earlier native disconnected sample exists.
export BERRY_FCM_DATA="$TMP/unknown-absence-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
export MCS_SS_MODE=absent
settime 12500
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '  (no client detail)' > "$MCS_FIXTURE"
run monitor; requests 3
assert_json "$(run snapshot)" fcm_state=unknown
settime 12529
run monitor; requests 3
settime 12530
run monitor; requests 4
assert_json "$(run snapshot)" fcm_state=disconnected
assert_json "$(run snapshot)" fcm_source=gms_socket_fallback
grep -q '|tcp_absence_confirmed|' "$BERRY_FCM_DATA/mcs-monitor-events.log"
grep -q '|reconnect_requested|auto UID=0 GCM_RECONNECT' "$BERRY_FCM_DATA/mcs-monitor-events.log"
unset MCS_SS_MODE
echo 'PASS: unknown-only state ages continuous Root socket absence into confirmed auto recovery'

# Continuous absence must not return to unknown after 15 minutes; only a real
# sampling gap resets the continuity anchor and starts a fresh confirmation.
export BERRY_FCM_DATA="$TMP/long-absence-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
export MCS_SS_MODE=absent
settime 14000
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '  (no client detail)' > "$MCS_FIXTURE"
run monitor
n=0
while [ "$n" -lt 55 ]; do
    settime $((14020+n*20))
    run monitor
    n=$((n+1))
done
j="$(run snapshot)"; assert_json "$j" fcm_state=disconnected
assert_json "$j" fcm_source=gms_socket_fallback
# A 100-second unobserved gap must not be mistaken for continuous absence.
settime 15200
run monitor
j="$(run snapshot)"; assert_json "$j" fcm_state=unknown
grep -q '|sample_gap|' "$BERRY_FCM_DATA/mcs-monitor-events.log"
echo 'PASS: long continuous absence remains disconnected; suspend gap resets evidence'

# A persistent SYN-SENT socket must retain its first-seen time and eventually
# request recovery; each poll must not restart the 60-second connecting timer.
export BERRY_FCM_DATA="$TMP/connecting-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
: > "$MCS_AM_LOG"
export MCS_SS_MODE=connecting
settime 16000
run monitor; requests 0
settime 16020
run monitor; requests 0
settime 16040
run monitor; requests 0
settime 16060
run monitor; requests 1
test "$(tail -n 1 "$MCS_AM_LOG")" = 'broadcast --user 0 -a com.google.android.intent.action.GCM_RECONNECT -p com.google.android.gms'
grep -q '|reconnect_requested|auto UID=0 GCM_RECONNECT' "$BERRY_FCM_DATA/mcs-monitor-events.log"
echo 'PASS: continuous GMS SYN-SENT state ages into recovery'

# A frozen positive native GMS connection timer is checked twice, then receives
# one targeted reconnect request. It does not force-stop the GMS package.
export BERRY_FCM_DATA="$TMP/timer-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
: > "$MCS_AM_LOG"
settime 20000
printf '%s\n' 'DeviceID: [fixture]' 'connected=mtalk.google.com/142.250.157.188,port=5228' 'connectTime=10:00/00:00' > "$MCS_FIXTURE"
run monitor; requests 0
settime 20299
run monitor; requests 0
settime 20300
run monitor; requests 1
j="$(run snapshot)"; assert_json "$j" fcm_state=connected; assert_json "$j" fcm_recovery_decision=requested
grep -q '|native_timer_stalled|GMS 原生仍报告 Connected' "$BERRY_FCM_DATA/mcs-monitor-events.log"
grep -q '|reconnect_requested|stalled_timer UID=0 GCM_RECONNECT' "$BERRY_FCM_DATA/mcs-monitor-events.log"
settime 20330
run monitor; requests 1
echo 'PASS: stalled native connection timer gets one confirmed, targeted reconnect request'

# Native GMS Close history can confirm a down state even when dumpsys has no
# current-state fields and ss cannot expose UID ownership.
export BERRY_FCM_DATA="$TMP/native-close-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
: > "$MCS_AM_LOG"
export MCS_SS_MODE=unknown
settime 30000
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '11-22 17:32:56.013 net=0: Close err:20 time:41' > "$MCS_FIXTURE"
run monitor; requests 0
settime 30029
run monitor; requests 0
assert_json "$(run snapshot)" fcm_state=unknown
settime 30030
run monitor; requests 1
j="$(run snapshot)"
assert_json "$j" fcm_state=disconnected
assert_json "$j" fcm_source=gms_native_event_fallback
assert_json "$j" fcm_recovery_decision=requested
grep -q '|native_close_confirmed|' "$BERRY_FCM_DATA/mcs-monitor-events.log"
echo 'PASS: recent native GMS Close event resolves missing current-state dump'

# The manual recovery entry point must accept the same confirmed native Close
# fallback that the background patrol accepts.
export BERRY_FCM_DATA="$TMP/manual-close-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
: > "$MCS_AM_LOG"
settime 31000
run reconnect; requests 0
settime 31030
run reconnect; requests 1
grep -q '|reconnect_requested|manual UID=0 GCM_RECONNECT' "$BERRY_FCM_DATA/mcs-monitor-events.log"
echo 'PASS: manual recovery accepts confirmed native Close fallback evidence'

# Recovery actions advance only after a later sample still confirms outage.
export BERRY_FCM_DATA="$TMP/action-stages-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
: > "$MCS_AM_LOG"
settime 40000
printf '%s\n' 'SERVICE com.google.android.gms/.gcm.GcmService' 'Server: Not connected' > "$MCS_FIXTURE"
run monitor; requests 0
settime 40015
run monitor; requests 1
test "$(sed -n '1p' "$MCS_AM_LOG")" = 'broadcast --user 0 -a com.google.android.intent.action.GCM_RECONNECT -p com.google.android.gms'
settime 40077
run monitor; requests 2
test "$(sed -n '2p' "$MCS_AM_LOG")" = 'broadcast --user 0 -a com.google.android.intent.action.MCS_HEARTBEAT -p com.google.android.gms'
settime 40197
run monitor; requests 3
test "$(sed -n '3p' "$MCS_AM_LOG")" = 'broadcast --user 0 -a com.google.android.gms.gcm.ACTION_HEARTBEAT_NOW -p com.google.android.gms'
settime 40377
run monitor; requests 4
test "$(sed -n '4p' "$MCS_AM_LOG")" = 'broadcast --user 0 -a com.google.android.intent.action.GTALK_HEARTBEAT -p com.google.android.gms'
echo 'PASS: staged GMS reconnect fallbacks are ordered and independently rate-limited'

# If Toybox exists but was built without the timeout applet, use PATH timeout.
export BERRY_FCM_DATA="$TMP/toybox-no-timeout-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
cat > "$TMP/bin/toybox-no-timeout" <<'MOCK'
#!/bin/sh
if [ "$1" = --list ]; then
    echo id
    exit 0
fi
exit 127
MOCK
chmod +x "$TMP/bin/toybox-no-timeout"
export BERRY_TOYBOX_BIN="$TMP/bin/toybox-no-timeout"
export MCS_SS_MODE=mtalk443 MCS_DNS_SUCCESS=1 MCS_DNS_LOG="$TMP/toybox-no-timeout-dns.log"
: > "$MCS_DNS_LOG"
settime 45000
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_transport=tcp443
[ "$(wc -l < "$MCS_DNS_LOG" | tr -d ' ')" = 2 ]
unset BERRY_TOYBOX_BIN
echo 'PASS: DNS lookup falls back to PATH timeout when Toybox lacks timeout'

# BusyBox timeout has no --foreground option and does not create a process group.
# Detect its documented help text and keep the probe in the monitor's group.
export BERRY_TOYBOX_BIN="$TMP/bin/toybox-no-timeout"
export BERRY_FCM_DATA="$TMP/busybox-path-timeout-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
cat > "$TMP/bin/timeout" <<'MOCK'
#!/bin/sh
if [ "$1" = --help ]; then
    echo 'Run PROG. Send SIG to it if it is not gone in SECS seconds.'
    exit 1
fi
[ "$1" = 3 ] || exit 2
shift
exec "$@"
MOCK
chmod +x "$TMP/bin/timeout"
export MCS_DNS_LOG="$TMP/busybox-path-timeout-dns.log"
: > "$MCS_DNS_LOG"
settime 45001
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_transport=tcp443
[ "$(wc -l < "$MCS_DNS_LOG" | tr -d ' ')" = 2 ]
rm -f "$TMP/bin/timeout"
unset BERRY_TOYBOX_BIN
echo 'PASS: BusyBox PATH timeout is recognized without creating a nested process group'

# Failed DNS lookups are cached too; repeated unknown samples must not spend
# up to six seconds resolving mtalk on every 20-second patrol cycle.
export BERRY_FCM_DATA="$TMP/dns-failure-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
export MCS_SS_MODE=unknown MCS_DNS_LOG="$TMP/dns.log"
: > "$MCS_DNS_LOG"
settime 50000
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '  (no client detail)' > "$MCS_FIXTURE"
run status
[ "$(wc -l < "$MCS_DNS_LOG" | tr -d ' ')" = 2 ]
settime 50020
run status
[ "$(wc -l < "$MCS_DNS_LOG" | tr -d ' ')" = 2 ]
echo 'PASS: failed mtalk DNS lookup is cached for 10 minutes'

# DNS answers are short-lived evidence. If a refresh fails, an expired mtalk
# IP must not continue validating an unrelated GMS-owned HTTPS socket.
export BERRY_FCM_DATA="$TMP/dns-expiry-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
export MCS_SS_MODE=mtalk443 MCS_DNS_SUCCESS=1 MCS_DNS_LOG="$TMP/dns-expiry.log"
: > "$MCS_DNS_LOG"
settime 60000
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '  (no client detail)' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_transport=tcp443
settime 60600
export MCS_DNS_SUCCESS=0
j="$(run status)"
assert_json "$j" fcm_state=unknown
assert_json "$j" fcm_tcp_hint=unknown
test ! -s "$BERRY_FCM_DATA/mcs-mtalk-dns-ips.txt"
echo 'PASS: expired mtalk DNS addresses are discarded after failed refresh'


# Learned MCS peers may validate GMS-owned :443 only briefly.
# entries are discarded; a fresh exact MCS socket refreshes the timestamp.
export BERRY_FCM_DATA="$TMP/learned-ip-ttl-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
printf '%s\n' '203.0.113.9' '142.250.157.188|1700060900' '142.250.157.188|1700060990' '999.999.999.999|1700060999' '142.250.157.188|1700062000' > "$BERRY_FCM_DATA/mcs-mtalk-learned-ips.txt"
export MCS_SS_MODE=connected MCS_DNS_SUCCESS=0
settime 61000
printf '%s\n' 'ACTIVITY MANAGER SERVICES' '  (service wrapper)' '  (no client detail)' > "$MCS_FIXTURE"
j="$(run status)"
assert_json "$j" fcm_state=connected
grep -qx '142.250.157.188|1700061000' "$BERRY_FCM_DATA/mcs-mtalk-learned-ips.txt"
[ "$(wc -l < "$BERRY_FCM_DATA/mcs-mtalk-learned-ips.txt" | tr -d ' ')" = 1 ]
! grep -q '203.0.113.9' "$BERRY_FCM_DATA/mcs-mtalk-learned-ips.txt"
export MCS_SS_MODE=mtalk443
settime 61060
j="$(run status)"
assert_json "$j" fcm_state=connected
assert_json "$j" fcm_transport=tcp443
# At 121 seconds the learned peer is expired; an unrelated HTTPS socket must
# no longer be promoted to MCS. Recent-state retention has also elapsed.
settime 61121
j="$(run status)"
assert_json "$j" fcm_state=unknown
assert_json "$j" fcm_tcp_hint=unknown
test ! -s "$BERRY_FCM_DATA/mcs-mtalk-learned-ips.txt"
echo 'PASS: learned MCS peer IPs expire after 120 seconds and legacy entries are discarded'

# The descriptor lock must remain held until the complete monitor command exits.
export BERRY_FCM_DATA="$TMP/flock-lifecycle-data"
mkdir -p "$BERRY_FCM_DATA"
echo 1 > "$BERRY_FCM_DATA/enabled"
export MCS_SS_MODE=connected MCS_DUMPSYS_LOG="$TMP/flock-dumpsys.log"
export MCS_DUMPSYS_BLOCK="$TMP/flock-dumpsys-started" MCS_DUMPSYS_BLOCK_SECONDS=2
: > "$MCS_DUMPSYS_LOG"
rm -f "$MCS_DUMPSYS_BLOCK"
printf '%s\n' 'DeviceID: [fixture]' 'connected=mtalk.google.com/142.250.157.188,port=5228' 'connectTime=00:30/00:00' > "$MCS_FIXTURE"
settime 62000
sh "$MON" monitor > "$TMP/flock-first.out" 2>&1 &
first_monitor_pid=$!
n=0
while [ ! -s "$MCS_DUMPSYS_BLOCK" ] && [ "$n" -lt 50 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
test -s "$MCS_DUMPSYS_BLOCK"
if sh "$MON" reconnect > "$TMP/flock-second.out" 2>&1; then
    echo 'concurrent reconnect unexpectedly acquired monitor lock' >&2
    exit 1
fi
grep -q '后台正在检查 GMS' "$TMP/flock-second.out"
wait "$first_monitor_pid"
first_monitor_pid=
[ "$(wc -l < "$MCS_DUMPSYS_LOG" | tr -d ' ')" = 1 ]
echo 'PASS: flock remains held for the full monitor operation and rejects concurrent requests'
