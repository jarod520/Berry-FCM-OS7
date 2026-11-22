#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
grep -q 'MODULE_HOT_INSTALL_REQUEST=true' "$ROOT/module/customize.sh"
grep -q 'MODULE_HOT_RUN_SCRIPT=hotinstall.sh' "$ROOT/module/customize.sh"
test -f "$ROOT/module/hotinstall.sh"
grep -q 'sh "$DIR/service.sh" </dev/null >/dev/null 2>&1 &' "$ROOT/module/hotinstall.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/data" "$TMP/module/bin" "$TMP/bin"
export TEST_DIR="$TMP"
export PATH="$TMP/bin:$PATH"
sed 's|^DATA=/data/adb/berry_fcm_ksu$|DATA="$TEST_DIR/data"|' "$ROOT/module/service.sh" > "$TMP/module/service.sh"
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
    echo '{"fcm_state":"connected","fcm_sample_time":1234,"fcm_recovery_decision":"not_disconnected"}'
else
    echo "$1" >> "$TEST_DIR/samples"
fi
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
