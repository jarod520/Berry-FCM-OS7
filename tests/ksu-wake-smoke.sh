#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
grep -q 'MODULE_HOT_INSTALL_REQUEST=true' "$ROOT/module/customize.sh"
grep -q 'MODULE_HOT_RUN_SCRIPT=hotinstall.sh' "$ROOT/module/customize.sh"
test -f "$ROOT/module/hotinstall.sh"
test -x "$ROOT/module/uninstall.sh"
grep -q 'sh "$DIR/service.sh" </dev/null >/dev/null 2>&1 &' "$ROOT/module/hotinstall.sh"
grep -q 'kill -TERM "$pid"' "$ROOT/module/uninstall.sh"
grep -Fq '[ "$n" -lt 24 ]' "$ROOT/module/hotinstall.sh"
grep -Fq '[ "$n" -lt 24 ]' "$ROOT/module/uninstall.sh"
grep -Fq '旧 BerryFCM 守护进程仍未退出' "$ROOT/module/hotinstall.sh"
grep -Fq 'while [ -e "$MODDIR/module.prop" ] && [ ! -e "$MODDIR/disable" ]; do' "$ROOT/module/service.sh"
grep -Fq 'while [ -e "$MODDIR/module.prop" ] && [ ! -e "$MODDIR/disable" ] && parent_alive; do' "$ROOT/module/bin/patrol.sh"
grep -Fq 'MONITOR_TIMEOUT="${BERRY_MONITOR_TIMEOUT_SECONDS:-25}"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'MONITOR_TIMEOUT=25;; esac' "$ROOT/module/bin/patrol.sh"
grep -Fq 'MONITOR_KILL_GRACE="${BERRY_MONITOR_KILL_GRACE:-3}"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'result="$(run_bounded "$MONITOR_TIMEOUT" sh "$MODDIR/bin/fcm-monitor.sh" monitor 2>&1)"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'sleep 20 &' "$ROOT/module/bin/patrol.sh"
grep -Fq 'patrol_identity_alive()' "$ROOT/module/service.sh"
grep -Fq 'proc_state()' "$ROOT/module/service.sh"
grep -Fq 'patrol_stop_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'timer_stop_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'stop_timer || return 1' "$ROOT/module/service.sh"
grep -Fq 'while patrol_identity_alive' "$ROOT/module/service.sh"
grep -Fq 'rm -f "$DATA/patrol.heartbeat"' "$ROOT/module/service.sh"
grep -Fq 'elif [ "$hb" -eq 0 ]' "$ROOT/module/service.sh"
grep -Fq 'patrol.sample.heartbeat' "$ROOT/module/bin/patrol.sh"
grep -Fq 'sample_stale=1' "$ROOT/module/service.sh"
grep -Fq 'reason=monitor_sample' "$ROOT/module/service.sh"
grep -Fq 'monitor_owner_alive()' "$ROOT/module/service.sh"
grep -Fq 'stop_monitor_owner()' "$ROOT/module/service.sh"
grep -Fq 'mcs-monitor.lock.owner' "$ROOT/module/service.sh"
grep -Fq 'service_cleanup() { stop_timer; stop_monitor_owner; stop_patrol;' "$ROOT/module/service.sh"
hot_stop_line="$(grep -n '^if is_guardian' "$ROOT/module/hotinstall.sh" | head -n 1 | cut -d: -f1)"
hot_enabled_line="$(grep -n 'berry_fcm_ksu/enabled' "$ROOT/module/hotinstall.sh" | head -n 1 | cut -d: -f1)"
[ "$hot_stop_line" -lt "$hot_enabled_line" ]
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/data" "$TMP/module/bin" "$TMP/bin"
export TEST_DIR="$TMP"
export PATH="$TMP/bin:$PATH"
export BERRY_TOYBOX_BIN="$TMP/bin/toybox" BERRY_MONITOR_TIMEOUT_SECONDS=1 BERRY_MONITOR_KILL_GRACE=1 BERRY_PATROL_RESTART_DELAY_SECONDS=0
sed 's|^DATA=/data/adb/berry_fcm_ksu$|DATA="$TEST_DIR/data"|' "$ROOT/module/service.sh" > "$TMP/module/service.sh"
sed 's|^DATA=/data/adb/berry_fcm_ksu$|DATA="$TEST_DIR/data"|' "$ROOT/module/bin/patrol.sh" > "$TMP/module/bin/patrol.sh"
cat > "$TMP/bin/id" <<'MOCK'
#!/bin/sh
echo 0
MOCK
cat > "$TMP/bin/getprop" <<'MOCK'
#!/bin/sh
echo 1
MOCK
cat > "$TMP/bin/sleep" <<'MOCK'
#!/bin/sh
echo "$1" >> "$TEST_DIR/sleeps"
/bin/sleep 0.15
if [ "${TEST_KILL_PATROL:-0}" = 1 ] && [ ! -e "$TEST_DIR/kill.done" ] && [ -s "$TEST_DIR/data/service.lock/patrol" ]; then
    p="$(awk '{print $1}' "$TEST_DIR/data/service.lock/patrol")"
    kill -KILL "$p" 2>/dev/null || :
    touch "$TEST_DIR/kill.done"
fi
if [ "${TEST_KILL_PATROL:-0}" = 1 ] && [ "$(grep -c patrol_supervisor_start "$TEST_DIR/data/guard.log" 2>/dev/null || true)" -ge 2 ]; then rm -f "$TEST_DIR/module/module.prop"; fi
if [ "$(wc -l < "$TEST_DIR/samples")" -ge 3 ]; then
    [ -e "$TEST_DIR/fix.done" ] || touch "$TEST_DIR/samples_during_fix"
    rm -f "$TEST_DIR/module/module.prop"
fi
MOCK
cat > "$TMP/module/bin/wake-timer-arm64" <<'MOCK'
#!/bin/sh
echo "$1" >> "$TEST_DIR/timer"
echo 'wake_timer_armed pid=123 delay_s=180'
if [ -e "$TEST_DIR/block-timer" ]; then
    echo "$$" > "$TEST_DIR/alarm-pid"
    exec /bin/sleep 30
fi
if [ "$(wc -l < "$TEST_DIR/timer")" = 1 ]; then
    /bin/sleep 0.05
    echo 'wake_timer_fired pid=123 elapsed_s=180 suspend_s=150 late_s=0'
    exit 0
fi
echo 'timerfd_create: fixture permission denied' >&2
exit 1
MOCK
cat > "$TMP/module/bin/fcm-monitor.sh" <<'MOCK'
if [ "$1" = snapshot ]; then
    if [ "${TEST_MONITOR_UNKNOWN:-0}" = 1 ]; then
        echo '{"fcm_state":"unknown","fcm_sample_time":1234,"fcm_recovery_decision":"sample_unavailable"}'
    else
        echo '{"fcm_state":"connected","fcm_sample_time":1234,"fcm_recovery_decision":"not_disconnected"}'
    fi
else
    before="$(wc -l < "$TEST_DIR/samples")"
    echo "$1" >> "$TEST_DIR/samples"
    if [ "${TEST_HANG_FIRST:-0}" = 1 ] && [ "$before" = 0 ]; then
        echo "$$" > "$TEST_DIR/hung-pid"
        exec /bin/sleep 30
    fi
fi
MOCK
cat > "$TMP/bin/toybox" <<'MOCK'
#!/bin/sh
if [ "$1" = --list ]; then echo timeout; exit 0; fi
[ "$1" = timeout ] || exit 2
shift
grace=5
if [ "$1" = -k ]; then grace="$2"; shift 2; fi
duration="$1"; shift
exec /usr/bin/timeout -k "$grace" "$duration" "$@"
MOCK
cat > "$TMP/module/bin/ctl.sh" <<'MOCK'
#!/bin/sh
if [ ! -e "$TEST_DIR/fix.done" ]; then
    /bin/sleep 4
    touch "$TEST_DIR/fix.done"
fi
exit 0
MOCK
chmod +x "$TMP/bin/"* "$TMP/module/bin/wake-timer-arm64"
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo timed > "$TMP/data/wake-mode"
timeout 8 sh "$TMP/module/service.sh"
n=0
while [ ! -e "$TMP/fix.done" ] && [ "$n" -lt 60 ]; do /bin/sleep 0.1; n=$((n + 1)); done
test -e "$TMP/fix.done"
test -e "$TMP/samples_during_fix"
test "$(cat "$TMP/data/wake-status")" = fallback
test "$(wc -l < "$TMP/samples")" -ge 3
test -s "$TMP/data/patrol.sample.heartbeat"
test "$(wc -l < "$TMP/timer")" -eq 2
grep -qx 3 "$TMP/timer"
test -s "$TMP/sleeps"
grep -q '定时器触发' "$TMP/data/guard.log"
grep -q 'wake_timer_armed .*delay_s=180' "$TMP/data/wake-timer.log"
grep -q 'wake_timer_fired .*elapsed_s=180 suspend_s=150 late_s=0' "$TMP/data/wake-timer.log"
grep -q 'timer_worker_started service_pid=.*interval_min=3' "$TMP/data/wake-timer.log"
grep -q 'timer_worker_exited service_pid=.*rc=1' "$TMP/data/wake-timer.log"
grep -q 'wake_gms_check_finished rc=0 state=connected sample_epoch=1234 recovery=not_disconnected' "$TMP/data/guard.log"
grep -q 'service_started pid=.*wake_mode=timed enabled=1 cgroup_ready=1' "$TMP/data/guard.log"
grep -q 'fcm_check_start pid=.*wake=1 mode=timed' "$TMP/data/guard.log"
grep -q 'fcm_check_end rc=0 elapsed_s=.*state=connected sample_epoch=1234 recovery=not_disconnected' "$TMP/data/guard.log"
grep -q 'maintenance_start pid=.*operation=guard_fix' "$TMP/data/guard.log"
grep -q 'maintenance_end pid=.*operation=guard_fix rc=0 elapsed_s=' "$TMP/data/guard.log"
grep -q 'fixture permission denied' "$TMP/data/wake-timer.log"
test ! -d "$TMP/data/service.lock"

touch "$TMP/block-timer" "$TMP/module/module.prop"
echo 10 > "$TMP/data/wake-minutes"
: > "$TMP/samples"
: > "$TMP/timer"
: > "$TMP/data/guard.log"
: > "$TMP/data/wake-timer.log"
timeout 8 sh "$TMP/module/service.sh"
test "$(wc -l < "$TMP/samples")" -ge 3
test "$(cat "$TMP/timer")" = 10
! grep -q 'wake_timer_fired' "$TMP/data/wake-timer.log"
! kill -0 "$(cat "$TMP/alarm-pid")" 2>/dev/null
test ! -d "$TMP/data/service.lock"
echo 'PASS: timer signals GMS checks; failed or blocked timer leaves passive polling active'
# A hung monitor is bounded and its child process group is terminated.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_HANG_FIRST=1
timeout 8 sh "$TMP/module/service.sh"
unset TEST_HANG_FIRST
test "$(wc -l < "$TMP/samples")" -ge 3
grep -q "fcm_check_end rc=124" "$TMP/data/guard.log"
hung="$(cat "$TMP/hung-pid")"
! kill -0 "$hung" 2>/dev/null
test ! -d "$TMP/data/service.lock"

# A killed patrol is restarted by the independent supervisor.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_KILL_PATROL=1
timeout 8 sh "$TMP/module/service.sh"
unset TEST_KILL_PATROL
test -e "$TMP/kill.done"
test "$(grep -c patrol_supervisor_start "$TMP/data/guard.log")" -ge 2
test ! -d "$TMP/data/service.lock"
echo "PASS: independent patrol, bounded timeout, process-group cleanup and patrol restart"

# An unknown GMS state is still a successful sample; it must keep refreshing
# the sample heartbeat rather than disabling the independent patrol.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_MONITOR_UNKNOWN=1
timeout 8 sh "$TMP/module/service.sh"
unset TEST_MONITOR_UNKNOWN
test -s "$TMP/data/patrol.sample.heartbeat"
grep -q 'fcm_check_end rc=0 .*state=unknown' "$TMP/data/guard.log"
! grep -q 'patrol_watchdog_stale reason=monitor_sample' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: unknown GMS state does not stop successful patrol sampling'
