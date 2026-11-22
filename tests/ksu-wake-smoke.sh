#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
grep -q 'MODULE_HOT_INSTALL_REQUEST=true' "$ROOT/module/customize.sh"
grep -q 'MODULE_HOT_RUN_SCRIPT=hotinstall.sh' "$ROOT/module/customize.sh"
test -f "$ROOT/module/hotinstall.sh"
test -x "$ROOT/module/uninstall.sh"
grep -q 'sh "$DIR/service.sh" </dev/null >/dev/null 2>&1 &' "$ROOT/module/hotinstall.sh"
grep -q 'kill -TERM "$pid"' "$ROOT/module/uninstall.sh"
grep -Fq '[ "$n" -lt 45 ]' "$ROOT/module/hotinstall.sh"
grep -Fq 'current_stamp="$(proc_start_time "$old")"' "$ROOT/module/hotinstall.sh"
grep -Fq 'case "$old_stamp" in ""|0|*[!0-9]*) old_stamp=;; esac' "$ROOT/module/hotinstall.sh"
grep -Fq 'old_stamp="$current_stamp"' "$ROOT/module/hotinstall.sh"
grep -Fq '[ "$current_stamp" = "$old_stamp" ] || return 1' "$ROOT/module/hotinstall.sh"
grep -Fq 'current_stamp="$(proc_start_time "$pid")"' "$ROOT/module/uninstall.sh"
grep -Fq 'case "$stamp" in ""|0|*[!0-9]*) stamp=;; esac' "$ROOT/module/uninstall.sh"
grep -Fq 'stamp="$current_stamp"' "$ROOT/module/uninstall.sh"
grep -Fq '[ "$current_stamp" = "$stamp" ] || return 1' "$ROOT/module/uninstall.sh"
grep -Fq 'case "$pid:$stamp" in *[!0-9:]*|:*|*:) pid=0;; esac' "$ROOT/module/bin/ctl.sh"
grep -Fq '[ "$n" -lt 45 ]' "$ROOT/module/uninstall.sh"
grep -Fq 'if [ -d "$LOCK" ]; then' "$ROOT/module/uninstall.sh"
grep -Fq '后台 worker 清理未确认' "$ROOT/module/uninstall.sh"
grep -Fq '旧 BerryFCM 守护进程仍未退出' "$ROOT/module/hotinstall.sh"
grep -Fq 'while [ -e "$MODDIR/module.prop" ] && [ ! -e "$MODDIR/disable" ]; do' "$ROOT/module/service.sh"
grep -Fq 'while [ -e "$MODDIR/module.prop" ] && [ ! -e "$MODDIR/disable" ] && parent_alive; do' "$ROOT/module/bin/patrol.sh"
grep -Fq 'MONITOR_TIMEOUT="${BERRY_MONITOR_TIMEOUT_SECONDS:-25}"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'MONITOR_TIMEOUT=25;; esac' "$ROOT/module/bin/patrol.sh"
grep -Fq 'MONITOR_KILL_GRACE="${BERRY_MONITOR_KILL_GRACE:-3}"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'has_setsid()' "$ROOT/module/bin/patrol.sh"
grep -Fq '&& has_setsid; then' "$ROOT/module/bin/patrol.sh"
grep -Fq 'result="$(run_bounded "$MONITOR_TIMEOUT" sh "$MODDIR/bin/fcm-monitor.sh" monitor 2>&1)"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'bounded_process_identity_alive()' "$ROOT/module/bin/patrol.sh"
grep -Fq '[ "$(proc_state "$bounded_pid" 2>/dev/null)" != Z ]' "$ROOT/module/bin/patrol.sh"
grep -Fq 'bounded_group_identity_alive()' "$ROOT/module/bin/patrol.sh"
grep -Fq 'bounded_descendants_snapshot()' "$ROOT/module/bin/patrol.sh"
grep -Fq 'path_count=split(FILENAME,path_parts,"/")' "$ROOT/module/bin/patrol.sh"
grep -Fq 'pid=path_parts[path_count-1]' "$ROOT/module/bin/patrol.sh"
grep -Fq 'signal_bounded_descendants TERM "$descendants_file"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'signal_bounded_descendants KILL "$descendants_file"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'proc_start_time "$child_pid" 2>/dev/null' "$ROOT/module/bin/patrol.sh"
grep -Fq 'bounded_watchdog_group_identity_unverified_before_term' "$ROOT/module/bin/patrol.sh"
grep -Fq 'bounded_watchdog_group_identity_unverified_before_kill' "$ROOT/module/bin/patrol.sh"
grep -Fq 'bounded_watchdog_process_identity_unverified_before_kill' "$ROOT/module/bin/patrol.sh"
grep -Fq 'falling back to direct child signal' "$ROOT/module/bin/patrol.sh"
grep -Fq 'bounded_watchdog_group_identity_unverified_before_kill; refusing signal' "$ROOT/module/bin/patrol.sh"
grep -Fq 'sleep 20 &' "$ROOT/module/bin/patrol.sh"
grep -Fq "awk '{print \$20}'" "$ROOT/module/service.sh"
grep -Fq 'case "$pid:$stamp" in *[!0-9:]*|:*|*:) return 1;; esac' "$ROOT/module/service.sh"
grep -Fq 'service_process_matches "$old"' "$ROOT/module/service.sh"
grep -Fq 'service_lock_identity_unverified' "$ROOT/module/service.sh"
grep -Fq 'case "$stale_patrol_pid:$stale_patrol_stamp" in *[!0-9:]*|:*|*:) return 1;; esac' "$ROOT/module/service.sh"
grep -Fq 'case "$monitor_pid:$monitor_stamp" in *[!0-9:]*|:*|*:) return 1;; esac' "$ROOT/module/service.sh"
grep -Fq 'patrol_identity_alive()' "$ROOT/module/service.sh"
grep -Fq 'proc_state()' "$ROOT/module/service.sh"
grep -Fq 'patrol_stop_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'timer_stop_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'stop_timer || return 1' "$ROOT/module/service.sh"
grep -Fq 'while patrol_identity_alive' "$ROOT/module/service.sh"
grep -Fq 'rm -f "$DATA/patrol.heartbeat"' "$ROOT/module/service.sh"
grep -Fq 'elif [ "$hb" -eq 0 ]' "$ROOT/module/service.sh"
grep -Fq 'patrol.sample.heartbeat' "$ROOT/module/bin/patrol.sh"
grep -Fq 'sample_heartbeat_not_refreshed rc=%s sample_epoch=%s sample_uptime=%s previous_sample_uptime=%s previous_snapshot_valid=%s check_started_uptime=%s' "$ROOT/module/bin/patrol.sh"
grep -Fq '[ "$previous_sample_snapshot_valid" = 1 ]' "$ROOT/module/bin/patrol.sh"
grep -Fq 'observed_sample_epoch' "$ROOT/module/bin/patrol.sh"
grep -Fq 'observed_sample_uptime' "$ROOT/module/bin/patrol.sh"
grep -Fq 'previous_sample_uptime' "$ROOT/module/bin/patrol.sh"
grep -Fq '[ "$observed_sample_state" != stale ]' "$ROOT/module/bin/patrol.sh"
grep -Fq '[ "$observed_sample_uptime" -ge "$check_started_uptime" ]' "$ROOT/module/bin/patrol.sh"
grep -Fq '[ "$observed_sample_uptime" -gt "$previous_sample_uptime" ]' "$ROOT/module/bin/patrol.sh"
grep -Fq 'sample_mono=0' "$ROOT/module/bin/fcm-monitor.sh"
grep -Fq '"fcm_sample_uptime":%s' "$ROOT/module/bin/fcm-monitor.sh"
grep -Fq 'monitor_rc" -ne 10' "$ROOT/module/bin/patrol.sh"
grep -Fq 'monitor_rc" -ne 11' "$ROOT/module/bin/patrol.sh"
grep -Fq 'monitor_rc" -ne 12' "$ROOT/module/bin/patrol.sh"
grep -Fq 'monitor_rc" -ne 14' "$ROOT/module/bin/patrol.sh"
grep -Fq 'check_started_uptime=%s' "$ROOT/module/bin/patrol.sh"
! grep -Fq '13|124) :;;' "$ROOT/module/bin/patrol.sh"
grep -Fq 'sample_stale=1' "$ROOT/module/service.sh"
grep -Fq 'reason=monitor_sample' "$ROOT/module/service.sh"
grep -Fq 'BERRY_FCM_ISOLATED_GROUP=1 "$TOYBOX_BIN" timeout' "$ROOT/module/bin/patrol.sh"
grep -Fq 'BERRY_FCM_ISOLATED_GROUP=1 "$TOYBOX_BIN" setsid "$KSU_BUSYBOX" timeout' "$ROOT/module/bin/patrol.sh"
grep -Fq 'BERRY_FCM_ISOLATED_GROUP=1 "$KSU_BUSYBOX" setsid "$KSU_BUSYBOX" timeout' "$ROOT/module/bin/patrol.sh"
grep -Fq 'BERRY_FCM_ISOLATED_GROUP=1 "$TOYBOX_BIN" setsid timeout' "$ROOT/module/bin/patrol.sh"
grep -Fq 'BERRY_FCM_ISOLATED_GROUP=1 "$KSU_BUSYBOX" setsid timeout' "$ROOT/module/bin/patrol.sh"
! grep -Fq 'BERRY_FCM_ISOLATED_GROUP=0 "$KSU_BUSYBOX" timeout' "$ROOT/module/bin/patrol.sh"
! grep -Fq 'BERRY_FCM_ISOLATED_GROUP=0 timeout' "$ROOT/module/bin/patrol.sh"
! grep -Fq 'BERRY_FCM_ISOLATED_GROUP=1 "$KSU_BUSYBOX" timeout' "$ROOT/module/bin/patrol.sh"
! grep -Fq 'BERRY_FCM_ISOLATED_GROUP=1 timeout' "$ROOT/module/bin/patrol.sh"
grep -Fq 'BERRY_FCM_ISOLATED_GROUP=1 "$TOYBOX_BIN" setsid "$@" &' "$ROOT/module/bin/patrol.sh"
grep -Fq 'BERRY_FCM_ISOLATED_GROUP=0 "$@" &' "$ROOT/module/bin/patrol.sh"
grep -Fq 'monitor_group_stop_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'monitor_legacy_group_inferred' "$ROOT/module/service.sh"
grep -Fq 'proc_group_id()' "$ROOT/module/bin/fcm-monitor.sh"
grep -Fq 'printf "%s %s %s %s %s\n"' "$ROOT/module/bin/fcm-monitor.sh"
grep -Fq 'monitor_owner_alive()' "$ROOT/module/service.sh"
grep -Fq 'monitor_group_tool()' "$ROOT/module/service.sh"
grep -Fq 'lock_owner_group_stamp="$(proc_start_time "$lock_owner_pgid")"' "$ROOT/module/bin/fcm-monitor.sh"

grep -Fq 'read -r monitor_pid monitor_stamp monitor_pgid monitor_isolated monitor_group_stamp' "$ROOT/module/service.sh"
grep -Fq 'proc_start_time "$monitor_pgid")" = "$monitor_group_stamp"' "$ROOT/module/service.sh"
grep -Fq 'process_group_alive "$monitor_pgid"' "$ROOT/module/service.sh"
grep -Fq 'monitor_group_identity_alive()' "$ROOT/module/service.sh"
[ "$(grep -cF 'monitor_group_identity_alive || {' "$ROOT/module/service.sh")" = 2 ]
grep -Fq 'monitor_group_identity_unverified_before_kill' "$ROOT/module/service.sh"
grep -Fq 'stop_monitor_owner()' "$ROOT/module/service.sh"
grep -Fq 'prepare_patrol_start()' "$ROOT/module/service.sh"
grep -Fq 'monitor_process_exists()' "$ROOT/module/service.sh"
grep -Fq 'case "$monitor_cmdline_text" in *fcm-monitor.sh*) return 0;; esac' "$ROOT/module/service.sh"
! grep -Fq 'grep -Fq "fcm-monitor.sh"' "$ROOT/module/service.sh"
grep -Fq 'stale_monitor_owner_record_cleared reason=no_monitor_process' "$ROOT/module/service.sh"
grep -Fq 'if [ -s "$DATA/mcs-monitor.lock.owner" ] && ! stop_monitor_owner; then' "$ROOT/module/service.sh"
grep -Fq 'if prepare_patrol_start; then' "$ROOT/module/service.sh"
grep -Fq 'patrol_restart_blocked reason=monitor_owner_cleanup_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'service_start_aborted reason=monitor_owner_cleanup_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'rmdir "$LOCK" 2>/dev/null || :; exit 0' "$ROOT/module/service.sh"
grep -Fq '[ "$service_pid" -gt 1 ]' "$ROOT/module/service.sh"
grep -Fq 'current_lock_stamp" = "$service_start_stamp"' "$ROOT/module/service.sh"
startup_abort_line="$(grep -nF 'service_start_aborted reason=monitor_owner_cleanup_unconfirmed' "$ROOT/module/service.sh" | head -n 1 | cut -d: -f1)"
startup_trap_line="$(grep -nF 'trap service_cleanup EXIT' "$ROOT/module/service.sh" | head -n 1 | cut -d: -f1)"
[ "$startup_abort_line" -lt "$startup_trap_line" ]
grep -Fq "IFS=' ' read -r service_pid _ < /proc/self/stat" "$ROOT/module/service.sh"
! grep -Fq "$(printf '\044\044')" "$ROOT/module/service.sh"
! grep -Fq 'echo $ > "$LOCK/pid"' "$ROOT/module/service.sh"
monitor_cleanup_line="$(grep -n 'stop_monitor_owner || exit 0' "$ROOT/module/service.sh" | head -n 1 | cut -d: -f1)"
service_pid_write_line="$(grep -nF 'echo "$service_pid" > "$LOCK/pid"' "$ROOT/module/service.sh" | head -n 1 | cut -d: -f1)"
[ "$service_pid_write_line" -lt "$monitor_cleanup_line" ]
grep -Fq 'mcs-monitor.lock.owner' "$ROOT/module/service.sh"
grep -Fq 'stop_stale_patrol()' "$ROOT/module/service.sh"
grep -Fq 'stop_stale_patrol || exit 0' "$ROOT/module/service.sh"
grep -Fq 'stop_timer || cleanup_ok=0' "$ROOT/module/service.sh"
grep -Fq 'stop_monitor_owner || cleanup_ok=0' "$ROOT/module/service.sh"
grep -Fq 'if stop_patrol; then' "$ROOT/module/service.sh"
grep -Fq 'service_cleanup_blocked reason=patrol_stop_unconfirmed; preserving owner locks' "$ROOT/module/service.sh"
grep -Fq 'service_cleanup_incomplete; preserving lock' "$ROOT/module/service.sh"
service_stop_patrol_line="$(grep -nF '    if stop_patrol; then' "$ROOT/module/service.sh" | head -n 1 | cut -d: -f1)"
service_stop_monitor_line="$(grep -n 'stop_monitor_owner || cleanup_ok=0' "$ROOT/module/service.sh" | head -n 1 | cut -d: -f1)"
[ -n "$service_stop_patrol_line" ] && [ -n "$service_stop_monitor_line" ]
[ "$service_stop_patrol_line" -lt "$service_stop_monitor_line" ]
watchdog_stop_patrol_line="$(grep -nF '            stop_patrol || {' "$ROOT/module/service.sh" | head -n 1 | cut -d: -f1)"
watchdog_stop_monitor_line="$(grep -nF '                stop_monitor_owner || {' "$ROOT/module/service.sh" | head -n 1 | cut -d: -f1)"
[ -n "$watchdog_stop_patrol_line" ] && [ -n "$watchdog_stop_monitor_line" ]
[ "$watchdog_stop_patrol_line" -lt "$watchdog_stop_monitor_line" ]
grep -Fq 'watchdog_cleanup_ok=1' "$ROOT/module/service.sh"
grep -Fq 'watchdog_cleanup_reason=patrol_stop_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'watchdog_cleanup_reason=monitor_owner_stop_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'patrol_watchdog_cleanup_blocked reason=%s; preserving stale heartbeat for retry' "$ROOT/module/service.sh"
grep -Fq 'maintenance_owner_alive()' "$ROOT/module/bin/patrol.sh"
grep -Fq 'proc_start_time "$maintenance_pid"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'maintenance_stop_child()' "$ROOT/module/bin/patrol.sh"
grep -Fq 'trap stop_patrol_children EXIT' "$ROOT/module/bin/patrol.sh"
grep -Fq 'reap_maintenance_worker()' "$ROOT/module/bin/patrol.sh"
grep -Fq 'trap maintenance_cleanup EXIT' "$ROOT/module/bin/patrol.sh"
grep -Fq 'maintenance_child_group_identity_alive()' "$ROOT/module/bin/patrol.sh"
grep -Fq 'maintenance_child_group_identity_unverified_before_kill' "$ROOT/module/bin/patrol.sh"
grep -Fq 'maintenance_child_group_stop_unconfirmed; preserving child owner record' "$ROOT/module/bin/patrol.sh"
grep -Fq 'maintenance_stop_child || return 1' "$ROOT/module/bin/patrol.sh"
grep -Fq 'maintenance_child_group_identity_alive()' "$ROOT/module/service.sh"
grep -Fq 'maintenance_child_group_identity_unverified_before_kill' "$ROOT/module/service.sh"
grep -Fq 'proc_group_id()' "$ROOT/module/bin/patrol.sh"
grep -Fq '"$TOYBOX_BIN" setsid sh "$MODDIR/bin/ctl.sh" fix' "$ROOT/module/bin/patrol.sh"
grep -Fq 'maintenance_child_pgid="$(proc_group_id "$maintenance_child_pid")"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'if process_group_alive "$bounded_pgid"; then' "$ROOT/module/bin/patrol.sh"
grep -Fq 'elif bounded_process_identity_alive; then' "$ROOT/module/bin/patrol.sh"
grep -Fq 'bounded_stamp="$(proc_start_time "$bounded_pid")"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'bounded_pgid="$(proc_group_id "$bounded_pid")"' "$ROOT/module/bin/patrol.sh"
maintenance_stop_block="$(sed -n '/^                    maintenance_stop_child() {/,/^                    }$/p' "$ROOT/module/bin/patrol.sh")"
maintenance_term_line="$(printf '%s\n' "$maintenance_stop_block" | grep -nF 'kill -TERM "-$maintenance_child_pgid"' | cut -d: -f1)"
maintenance_kill_guard_line="$(printf '%s\n' "$maintenance_stop_block" | grep -nF 'if process_group_alive "$maintenance_child_pgid"; then' | cut -d: -f1)"
maintenance_kill_line="$(printf '%s\n' "$maintenance_stop_block" | grep -nF 'kill -KILL "-$maintenance_child_pgid"' | cut -d: -f1)"
[ -n "$maintenance_term_line" ] && [ -n "$maintenance_kill_guard_line" ] && [ -n "$maintenance_kill_line" ]
[ "$maintenance_term_line" -lt "$maintenance_kill_guard_line" ] && [ "$maintenance_kill_guard_line" -lt "$maintenance_kill_line" ]
grep -Fq 'maintenance_group_tool" kill -KILL' "$ROOT/module/bin/patrol.sh"
grep -Fq 'maintenance_skipped reason=no_setsid_or_kill_applet' "$ROOT/module/bin/patrol.sh"
grep -Fq 'proc_group_id()' "$ROOT/module/service.sh"
grep -Fq 'process_group_alive()' "$ROOT/module/service.sh"
grep -Fq 'maintenance_child_group_alive()' "$ROOT/module/service.sh"
grep -Fq 'maintenance_child_alive()' "$ROOT/module/bin/patrol.sh"
grep -Fq 'stop_maintenance_child()' "$ROOT/module/service.sh"
grep -Fq 'maintenance_skip reason=child_identity_invalid' "$ROOT/module/bin/patrol.sh"
grep -Fq 'stop_maintenance_child || return 1' "$ROOT/module/service.sh"
grep -Fq 'maintenance_child_stop_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'mv -f "$MAINTENANCE_LOCK/child.tmp.$maintenance_owner_pid" "$MAINTENANCE_LOCK/child"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'stop_maintenance_owner()' "$ROOT/module/service.sh"
grep -Fq 'stop_maintenance_owner || cleanup_ok=0' "$ROOT/module/service.sh"
grep -Fq 'stop_maintenance_owner || exit 0' "$ROOT/module/service.sh"
grep -Fq 'maintenance_owner_stop_unconfirmed' "$ROOT/module/service.sh"
grep -Fq 'proc_state "$maintenance_pid")" != Z' "$ROOT/module/bin/patrol.sh"
grep -Fq 'read -r maintenance_owner_pid _ < /proc/self/stat' "$ROOT/module/bin/patrol.sh"
grep -Fq 'current_stamp" = "$maintenance_owner_stamp"' "$ROOT/module/bin/patrol.sh"
grep -Fq 'register_patrol_identity || exit 1' "$ROOT/module/bin/patrol.sh"
grep -Fq 'mv -f "$DATA/service.lock/patrol.tmp.$patrol_self_pid" "$DATA/service.lock/patrol"' "$ROOT/module/bin/patrol.sh"
! grep -Fq '\\n' "$ROOT/module/bin/patrol.sh"
! grep -Eq '\\\\$' "$ROOT/module/bin/patrol.sh"
hot_enabled_line="$(grep -n 'berry_fcm_ksu/enabled' "$ROOT/module/hotinstall.sh" | head -n 1 | cut -d: -f1)"
hot_stop_line="$(grep -n '^if is_guardian' "$ROOT/module/hotinstall.sh" | head -n 1 | cut -d: -f1)"
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
if [ "${TEST_NO_TIMEOUT:-0}" = 1 ]; then
    case "$1" in 1|2|3) /bin/sleep "$1";; *) /bin/sleep 0.15;; esac
else
    /bin/sleep 0.15
fi
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
    if [ "${TEST_SNAPSHOT_FAIL_FIRST:-0}" = 1 ] && [ ! -e "$TEST_DIR/snapshot-failed" ]; then
        touch "$TEST_DIR/snapshot-failed"
        exit 1
    fi
    sample_epoch="$(cat "$TEST_DIR/sample-epoch" 2>/dev/null || echo 0)"
    sample_uptime="$(cat "$TEST_DIR/sample-uptime" 2>/dev/null || echo 0)"
    if [ "${TEST_MONITOR_STALE:-0}" = 1 ]; then
        echo "{\"fcm_state\":\"stale\",\"fcm_sample_time\":$sample_epoch,\"fcm_sample_uptime\":$sample_uptime,\"fcm_recovery_decision\":\"sample_unavailable\"}"
    elif [ "${TEST_MONITOR_UNKNOWN:-0}" = 1 ]; then
        echo "{\"fcm_state\":\"unknown\",\"fcm_sample_time\":$sample_epoch,\"fcm_sample_uptime\":$sample_uptime,\"fcm_recovery_decision\":\"sample_unavailable\"}"
    else
        echo "{\"fcm_state\":\"connected\",\"fcm_sample_time\":$sample_epoch,\"fcm_sample_uptime\":$sample_uptime,\"fcm_recovery_decision\":\"not_disconnected\"}"
    fi
else
    before="$(wc -l < "$TEST_DIR/samples")"
    echo "$1" >> "$TEST_DIR/samples"
    if [ -n "${TEST_MONITOR_PRE_SAMPLE_RC:-}" ]; then exit "$TEST_MONITOR_PRE_SAMPLE_RC"; fi
    if [ -n "${TEST_MONITOR_NO_SAMPLE_RC:-}" ]; then exit "$TEST_MONITOR_NO_SAMPLE_RC"; fi
    sample_epoch="$(date +%s)"
    previous_sample_epoch="$(cat "$TEST_DIR/sample-epoch" 2>/dev/null || echo 0)"
    case "$sample_epoch" in ""|*[!0-9]*) sample_epoch=0;; esac
    case "$previous_sample_epoch" in ""|*[!0-9]*) previous_sample_epoch=0;; esac
    if [ "$sample_epoch" -le "$previous_sample_epoch" ]; then
        sample_epoch=$((previous_sample_epoch + 1))
    fi
    if [ -n "${TEST_SAMPLE_EPOCH_OVERRIDE:-}" ]; then
        sample_epoch="$TEST_SAMPLE_EPOCH_OVERRIDE"
    fi
    printf '%s\n' "$sample_epoch" > "$TEST_DIR/sample-epoch"
    sample_uptime="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
    previous_sample_uptime="$(cat "$TEST_DIR/sample-uptime" 2>/dev/null || echo 0)"
    case "$sample_uptime" in ""|*[!0-9]*) sample_uptime=0;; esac
    case "$previous_sample_uptime" in ""|*[!0-9]*) previous_sample_uptime=0;; esac
    if [ "$sample_uptime" -le "$previous_sample_uptime" ]; then
        sample_uptime=$((previous_sample_uptime + 1))
    fi
    printf '%s\n' "$sample_uptime" > "$TEST_DIR/sample-uptime"
    if [ -n "${TEST_MONITOR_RC:-}" ]; then exit "$TEST_MONITOR_RC"; fi
    if [ "${TEST_HANG_FIRST:-0}" = 1 ] && [ "$before" = 0 ]; then
        /bin/sleep 30 &
        echo "$!" > "$TEST_DIR/hung-pid"
        wait
    fi
    if [ "${TEST_HANG_CHILD:-0}" = 1 ] && [ "$before" = 0 ]; then
        /bin/sleep 30 &
        echo "$!" > "$TEST_DIR/hung-child-pid"
        wait
    fi
fi
MOCK
cat > "$TMP/bin/toybox" <<'MOCK'
#!/bin/sh
if [ "$1" = --list ]; then
    if [ "${TEST_NO_TIMEOUT:-0}" = 1 ] && [ "${TEST_NO_SETSID:-0}" = 1 ]; then
        printf '%s\n' kill
    elif [ "${TEST_NO_TIMEOUT:-0}" = 1 ]; then
        printf '%s\n' setsid kill
    else
        printf '%s\n' timeout setsid kill
    fi
    exit 0
fi
case "$1" in
    setsid) shift; exec /usr/bin/setsid "$@";;
    kill) shift; exec /bin/kill "$@";;
    timeout) shift;;
    *) exit 2;;
esac
grace=5
if [ "$1" = -k ]; then grace="$2"; shift 2; fi
duration="$1"; shift
exec /usr/bin/timeout -k "$grace" "$duration" "$@"
MOCK
cat > "$TMP/module/bin/ctl.sh" <<'MOCK'
#!/bin/sh
if [ "${TEST_BLOCK_FIX:-0}" = 1 ]; then
    /bin/sleep 30 &
    echo "$!" > "$TEST_DIR/fix-child-pid"
    wait
elif [ ! -e "$TEST_DIR/fix.done" ]; then
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
grep -q 'wake_gms_check_finished rc=0 state=connected sample_epoch=[0-9][0-9]* recovery=not_disconnected' "$TMP/data/guard.log"
grep -q 'service_started pid=.*wake_mode=timed enabled=1 cgroup_ready=1' "$TMP/data/guard.log"
grep -q 'fcm_check_start pid=.*wake=1 mode=timed' "$TMP/data/guard.log"
grep -q 'fcm_check_end rc=0 elapsed_s=.*state=connected sample_epoch=[0-9][0-9]* recovery=not_disconnected' "$TMP/data/guard.log"
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
hung_state="$(awk '{print $3}' "/proc/$hung/stat" 2>/dev/null || :)"
[ -z "$hung_state" ] || [ "$hung_state" = Z ]
test ! -d "$TMP/data/service.lock"

# The timeout must kill descendants in the monitor's process group too.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_HANG_CHILD=1
timeout 8 sh "$TMP/module/service.sh"
unset TEST_HANG_CHILD
child_pid="$(cat "$TMP/hung-child-pid")"
child_state="$(awk '{print $3}' "/proc/$child_pid/stat" 2>/dev/null || :)"
[ -z "$child_state" ] || [ "$child_state" = Z ]
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

# A completed monitor attempt with a nonzero result is not a stalled patrol.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_MONITOR_RC=42
timeout 8 sh "$TMP/module/service.sh"
unset TEST_MONITOR_RC
test -s "$TMP/data/patrol.sample.heartbeat"
grep -q "fcm_check_end rc=42" "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo "PASS: nonzero monitor result after a committed sample refreshes patrol heartbeat"

# A monitor error before observe() produces a fresh sample must not refresh
# the sample heartbeat; the supervisor must retain stale-sample evidence.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
rm -f "$TMP/data/patrol.sample.heartbeat" "$TMP/sample-epoch"
export TEST_MONITOR_PRE_SAMPLE_RC=12
timeout 8 sh "$TMP/module/service.sh"
unset TEST_MONITOR_PRE_SAMPLE_RC
test ! -s "$TMP/data/patrol.sample.heartbeat"
grep -q 'sample_heartbeat_not_refreshed rc=12' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo "PASS: failed observe does not refresh sample heartbeat"

# A non-excluded post-attempt error with an unchanged sample uptime must be
# rejected even if that old sample timestamp is newer than check start.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
echo 1700000000 > "$TMP/sample-epoch"
sample_uptime_now="$(awk '{print int($1)}' /proc/uptime)"
old_sample_uptime=$((sample_uptime_now + 10))
echo "$old_sample_uptime" > "$TMP/sample-uptime"
export TEST_MONITOR_NO_SAMPLE_RC=42
timeout 8 sh "$TMP/module/service.sh"
unset TEST_MONITOR_NO_SAMPLE_RC
test ! -s "$TMP/data/patrol.sample.heartbeat"
grep -q "sample_heartbeat_not_refreshed rc=42 .*sample_uptime=$old_sample_uptime previous_sample_uptime=$old_sample_uptime check_started_uptime=" "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: unchanged sample uptime cannot refresh patrol heartbeat'

# If the pre-check snapshot cannot be read, a same/future old sample must not
# be treated as new merely because the post-check snapshot is readable.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
echo 1900000000 > "$TMP/sample-epoch"
sample_uptime_now="$(awk '{print int($1)}' /proc/uptime)"
old_sample_uptime=$((sample_uptime_now + 10))
echo "$old_sample_uptime" > "$TMP/sample-uptime"
export TEST_SNAPSHOT_FAIL_FIRST=1 TEST_MONITOR_NO_SAMPLE_RC=42
timeout 8 sh "$TMP/module/service.sh"
unset TEST_SNAPSHOT_FAIL_FIRST TEST_MONITOR_NO_SAMPLE_RC
test ! -s "$TMP/data/patrol.sample.heartbeat"
grep -q "sample_heartbeat_not_refreshed rc=42 .*sample_uptime=$old_sample_uptime previous_sample_uptime=$old_sample_uptime previous_snapshot_valid=0" "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: unreadable pre-check snapshot cannot refresh heartbeat from old sample'

# A fresh monotonic sample remains fresh even when wall-clock time moves back.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
echo 1900000000 > "$TMP/sample-epoch"
sample_uptime_now="$(awk '{print int($1)}' /proc/uptime)"
old_sample_uptime=$((sample_uptime_now - 1))
[ "$old_sample_uptime" -ge 0 ] || old_sample_uptime=0
echo "$old_sample_uptime" > "$TMP/sample-uptime"
export TEST_SAMPLE_EPOCH_OVERRIDE=1600000000
timeout 8 sh "$TMP/module/service.sh"
unset TEST_SAMPLE_EPOCH_OVERRIDE
test -s "$TMP/data/patrol.sample.heartbeat"
grep -q 'fcm_check_end rc=0 .*sample_epoch=1600000000' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: wall-clock rollback does not block patrol sample heartbeat'

# A pre-observe owner-registration failure must not reuse an unchanged
# monotonic sample even when its timestamp is otherwise recent.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
rm -f "$TMP/data/patrol.sample.heartbeat"
date +%s > "$TMP/sample-epoch"
sample_uptime_now="$(awk '{print int($1)}' /proc/uptime)"
echo "$((sample_uptime_now + 10))" > "$TMP/sample-uptime"
export TEST_MONITOR_PRE_SAMPLE_RC=14
timeout 8 sh "$TMP/module/service.sh"
unset TEST_MONITOR_PRE_SAMPLE_RC
test ! -s "$TMP/data/patrol.sample.heartbeat"
grep -q 'sample_heartbeat_not_refreshed rc=14 .*previous_sample_uptime=' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: pre-observe owner failure cannot refresh heartbeat from a same-second old sample'

# A newly written sample is still not sufficient when snapshot marks its
# persisted state stale.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
rm -f "$TMP/data/patrol.sample.heartbeat"
date +%s > "$TMP/sample-epoch"
sample_uptime_now="$(awk '{print int($1)}' /proc/uptime)"
echo "$((sample_uptime_now + 10))" > "$TMP/sample-uptime"
/bin/sleep 1
export TEST_MONITOR_RC=42 TEST_MONITOR_STALE=1
timeout 8 sh "$TMP/module/service.sh"
unset TEST_MONITOR_RC TEST_MONITOR_STALE
test ! -s "$TMP/data/patrol.sample.heartbeat"
grep -q 'sample_heartbeat_not_refreshed rc=42' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: stale snapshot state cannot refresh sample heartbeat'

touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_MONITOR_RC=13
timeout 8 sh "$TMP/module/service.sh"
unset TEST_MONITOR_RC
test ! -s "$TMP/data/patrol.sample.heartbeat"
grep -q "fcm_check_end rc=13" "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo "PASS: monitor lock contention does not mask stale-sample watchdog"

# A dead service lock must not be reclaimed while its recorded patrol worker
# is still alive; terminate that verified orphan before starting a new service.
cat > "$TMP/orphan-patrol.sh" <<'MOCK'
#!/bin/sh
trap 'exit 0' TERM
while :; do /bin/sleep 0.1; done
MOCK
chmod +x "$TMP/orphan-patrol.sh"
"$TMP/orphan-patrol.sh" &
orphan_pid=$!
orphan_stamp="$(tr -d '\n' < "/proc/$orphan_pid/stat" | sed 's/^.*) //' | awk '{print $20}')"
mkdir -p "$TMP/data/service.lock"
echo 999999 > "$TMP/data/service.lock/pid"
echo 1 > "$TMP/data/service.lock/starttime"
printf '%s %s\n' "$orphan_pid" "$orphan_stamp" > "$TMP/data/service.lock/patrol"
echo 1 > "$TMP/data/enabled"
touch "$TMP/module/module.prop"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
timeout 8 sh "$TMP/module/service.sh"
wait "$orphan_pid" 2>/dev/null || :
! kill -0 "$orphan_pid" 2>/dev/null
grep -q 'stale_patrol_stopped pid=' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: stale service lock cannot spawn a duplicate patrol'

# A stale maintenance owner must not hide a still-running tracked child.
cat > "$TMP/orphan-maintenance-child.sh" <<'MOCK'
#!/bin/sh
exec /bin/sleep 30
MOCK
chmod +x "$TMP/orphan-maintenance-child.sh"
"$TMP/bin/toybox" setsid "$TMP/orphan-maintenance-child.sh" &
orphan_child_pid=$!
orphan_child_stamp="$(tr -d '\n' < "/proc/$orphan_child_pid/stat" | sed 's/^.*) //' | awk '{print $20}')"
mkdir -p "$TMP/data/service.lock" "$TMP/data/maintenance.lock"
echo 999999 > "$TMP/data/service.lock/pid"
echo 1 > "$TMP/data/service.lock/starttime"
echo '999998 1' > "$TMP/data/maintenance.lock/owner"
printf '%s %s %s %s\n' "$orphan_child_pid" "$orphan_child_stamp" "$orphan_child_pid" "$TMP/bin/toybox" > "$TMP/data/maintenance.lock/child"
echo 1 > "$TMP/data/enabled"
touch "$TMP/module/module.prop"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
timeout 8 sh "$TMP/module/service.sh"
wait "$orphan_child_pid" 2>/dev/null || :
! kill -0 "$orphan_child_pid" 2>/dev/null
grep -q 'service_started pid=' "$TMP/data/guard.log"
test ! -d "$TMP/data/maintenance.lock"
test ! -d "$TMP/data/service.lock"
echo 'PASS: stale maintenance owner cleanup also terminates its tracked child'

# Service cleanup must terminate an isolated fcm-monitor process group, not just its shell PID.
echo passive > "$TMP/data/wake-mode"
echo 0 > "$TMP/data/enabled"
touch "$TMP/module/module.prop"
: > "$TMP/data/guard.log"
sh "$TMP/module/service.sh" &
service_pid=$!
n=0
while ! grep -q 'service_started pid=' "$TMP/data/guard.log" 2>/dev/null && [ "$n" -lt 60 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
grep -q 'service_started pid=' "$TMP/data/guard.log"
cat > "$TMP/fcm-monitor.sh" <<'MOCK'
#!/bin/sh
/bin/sleep 30 &
echo "$!" > "$TEST_DIR/monitor-child-pid"
wait
MOCK
chmod +x "$TMP/fcm-monitor.sh"
"$TMP/bin/toybox" setsid sh "$TMP/fcm-monitor.sh" &
monitor_pid=$!
monitor_stamp="$(tr -d '\n' < "/proc/$monitor_pid/stat" | sed 's/^.*) //' | awk '{print $20}')"
monitor_pgid="$(tr -d '\n' < "/proc/$monitor_pid/stat" | sed 's/^.*) //' | awk '{print $3}')"
[ "$monitor_pid" = "$monitor_pgid" ]
n=0
while [ ! -s "$TMP/monitor-child-pid" ] && [ "$n" -lt 60 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
test -s "$TMP/monitor-child-pid"
monitor_child="$(cat "$TMP/monitor-child-pid")"
printf '%s %s %s 1\n' "$monitor_pid" "$monitor_stamp" "$monitor_pgid" > "$TMP/data/mcs-monitor.lock.owner"
kill -TERM "$service_pid"
wait "$service_pid" 2>/dev/null || :
wait "$monitor_pid" 2>/dev/null || :
child_state="$(awk '{print $3}' "/proc/$monitor_child/stat" 2>/dev/null || :)"
[ -z "$child_state" ] || [ "$child_state" = Z ]
test ! -e "$TMP/data/mcs-monitor.lock.owner"
test ! -d "$TMP/data/service.lock"
echo 'PASS: service cleanup terminates isolated monitor process groups'

# timeout owns a separate process group: monitor PID differs from PGID.
# Cleanup must validate the group leader identity and kill the whole group.
echo passive > "$TMP/data/wake-mode"
echo 0 > "$TMP/data/enabled"
touch "$TMP/module/module.prop"
: > "$TMP/data/guard.log"
sh "$TMP/module/service.sh" &
service_pid=$!
n=0
while ! grep -q 'service_started pid=' "$TMP/data/guard.log" 2>/dev/null && [ "$n" -lt 60 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
grep -q 'service_started pid=' "$TMP/data/guard.log"
cat > "$TMP/test-fcm-monitor.sh" <<'MOCK'
#!/bin/sh
IFS=' ' read -r monitor_pid _ < /proc/self/stat
monitor_stamp="$(tr -d '\n' < "/proc/$monitor_pid/stat" | sed 's/^.*) //' | awk '{print $20}')"
monitor_pgid="$(tr -d '\n' < "/proc/$monitor_pid/stat" | sed 's/^.*) //' | awk '{print $3}')"
group_stamp="$(tr -d '\n' < "/proc/$monitor_pgid/stat" | sed 's/^.*) //' | awk '{print $20}')"
printf '%s %s %s 1 %s\n' "$monitor_pid" "$monitor_stamp" "$monitor_pgid" "$group_stamp" > "$TEST_DIR/data/mcs-monitor.lock.owner"
 /bin/sleep 30 &
echo "$!" > "$TEST_DIR/timeout-monitor-child-pid"
wait
MOCK
chmod +x "$TMP/test-fcm-monitor.sh"
cat > "$TMP/timeout-wrapper.sh" <<'MOCK'
#!/bin/sh
sh "$1" &
monitor_child=$!
wait "$monitor_child"
MOCK
chmod +x "$TMP/timeout-wrapper.sh"
# Model a timeout implementation whose wrapper owns the private process group.
"$TMP/bin/toybox" setsid sh "$TMP/timeout-wrapper.sh" "$TMP/test-fcm-monitor.sh" &
timeout_pid=$!
n=0
while [ ! -s "$TMP/data/mcs-monitor.lock.owner" ] && [ "$n" -lt 60 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
test -s "$TMP/data/mcs-monitor.lock.owner"
read -r timeout_monitor_pid timeout_monitor_stamp timeout_monitor_pgid timeout_isolated timeout_group_stamp < "$TMP/data/mcs-monitor.lock.owner"
[ "$timeout_isolated" = 1 ]
[ "$timeout_monitor_pid" != "$timeout_monitor_pgid" ]
[ "$timeout_monitor_pgid" = "$timeout_pid" ]
timeout_monitor_child="$(cat "$TMP/timeout-monitor-child-pid")"
kill -TERM "$service_pid"
wait "$service_pid" 2>/dev/null || :
wait "$timeout_pid" 2>/dev/null || :
child_state="$(awk '{print $3}' "/proc/$timeout_monitor_child/stat" 2>/dev/null || :)"
[ -z "$child_state" ] || [ "$child_state" = Z ]
test ! -e "$TMP/data/mcs-monitor.lock.owner"
test ! -d "$TMP/data/service.lock"
echo 'PASS: service cleanup terminates timeout-owned monitor groups when monitor PID differs from PGID'

# BusyBox timeout does not create a process group; setsid must isolate it first.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/data/guard.log"
cat > "$TMP/bin/busybox" <<'MOCK'
#!/bin/sh
if [ "$1" = --list ]; then echo timeout; exit 0; fi
[ "$1" = timeout ] || exit 2
shift
if [ "$1" = -k ]; then shift 2; fi
shift
exec "$@"
MOCK
chmod +x "$TMP/bin/busybox"
cat > "$TMP/module/bin/fcm-monitor.sh" <<'MOCK'
#!/bin/sh
if [ "$1" = snapshot ]; then
    echo '{"fcm_state":"unknown","fcm_sample_time":0,"fcm_recovery_decision":"sample_unavailable"}'
    exit 0
fi
IFS=' ' read -r monitor_pid _ < /proc/self/stat
monitor_stamp="$(tr -d '\n' < "/proc/$monitor_pid/stat" | sed 's/^.*) //' | awk '{print $20}')"
monitor_pgid="$(tr -d '\n' < "/proc/$monitor_pid/stat" | sed 's/^.*) //' | awk '{print $3}')"
group_stamp="$(tr -d '\n' < "/proc/$monitor_pgid/stat" | sed 's/^.*) //' | awk '{print $20}')"
printf '%s %s %s 1 %s\n' "$monitor_pid" "$monitor_stamp" "$monitor_pgid" "$group_stamp" > "$TEST_DIR/data/mcs-monitor.lock.owner"
 /bin/sleep 30 &
echo "$!" > "$TEST_DIR/busybox-monitor-child-pid"
wait
MOCK
chmod +x "$TMP/module/bin/fcm-monitor.sh"
TEST_NO_TIMEOUT=1 BERRY_KSU_BUSYBOX="$TMP/bin/busybox" sh "$TMP/module/service.sh" &
service_pid=$!
n=0
while [ ! -s "$TMP/data/mcs-monitor.lock.owner" ] && [ "$n" -lt 80 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
test -s "$TMP/data/mcs-monitor.lock.owner"
read -r busybox_monitor_pid busybox_monitor_stamp busybox_monitor_pgid busybox_isolated busybox_group_stamp < "$TMP/data/mcs-monitor.lock.owner"
[ "$busybox_isolated" = 1 ]
[ "$busybox_monitor_pid" = "$busybox_monitor_pgid" ]
busybox_monitor_child="$(cat "$TMP/busybox-monitor-child-pid")"
kill -TERM "$service_pid"
wait "$service_pid" 2>/dev/null || :
busybox_child_state="$(awk '{print $3}' "/proc/$busybox_monitor_child/stat" 2>/dev/null || :)"
[ -z "$busybox_child_state" ] || [ "$busybox_child_state" = Z ]
test ! -e "$TMP/data/mcs-monitor.lock.owner"
test ! -d "$TMP/data/service.lock"
echo 'PASS: BusyBox timeout is isolated by setsid before process-group cleanup'

# A new supervisor must clean an orphaned isolated monitor group before publishing its service lock.
echo passive > "$TMP/data/wake-mode"
echo 0 > "$TMP/data/enabled"
touch "$TMP/module/module.prop"
: > "$TMP/data/guard.log"
cat > "$TMP/fcm-monitor.sh" <<'MOCK'
#!/bin/sh
/bin/sleep 30 &
echo "$!" > "$TEST_DIR/startup-monitor-child-pid"
wait
MOCK
chmod +x "$TMP/fcm-monitor.sh"
"$TMP/bin/toybox" setsid sh "$TMP/fcm-monitor.sh" &
startup_monitor_pid=$!
startup_monitor_stamp="$(tr -d '\n' < "/proc/$startup_monitor_pid/stat" | sed 's/^.*) //' | awk '{print $20}')"
startup_monitor_pgid="$(tr -d '\n' < "/proc/$startup_monitor_pid/stat" | sed 's/^.*) //' | awk '{print $3}')"
[ "$startup_monitor_pid" = "$startup_monitor_pgid" ]
n=0
while [ ! -s "$TMP/startup-monitor-child-pid" ] && [ "$n" -lt 60 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
test -s "$TMP/startup-monitor-child-pid"
startup_monitor_child="$(cat "$TMP/startup-monitor-child-pid")"
printf '%s %s\n' "$startup_monitor_pid" "$startup_monitor_stamp" > "$TMP/data/mcs-monitor.lock.owner"
sh "$TMP/module/service.sh" &
service_pid=$!
n=0
while ! grep -q 'service_started pid=' "$TMP/data/guard.log" 2>/dev/null && [ "$n" -lt 60 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
grep -q 'service_started pid=' "$TMP/data/guard.log"
locked_service_pid="$(cat "$TMP/data/service.lock/pid")"
[ "$locked_service_pid" = "$service_pid" ]
locked_service_stamp="$(cat "$TMP/data/service.lock/starttime")"
actual_service_stamp="$(tr -d '\n' < "/proc/$service_pid/stat" | sed 's/^.*) //' | awk '{print $20}')"
[ "$locked_service_stamp" = "$actual_service_stamp" ]
wait "$startup_monitor_pid" 2>/dev/null || :
startup_child_state="$(awk '{print $3}' "/proc/$startup_monitor_child/stat" 2>/dev/null || :)"
[ -z "$startup_child_state" ] || [ "$startup_child_state" = Z ]
test ! -e "$TMP/data/mcs-monitor.lock.owner"
kill -TERM "$service_pid"
wait "$service_pid" 2>/dev/null || :
test ! -d "$TMP/data/service.lock"
echo 'PASS: startup cleans legacy monitor group before patrol start'

# If timeout is missing from Toybox, KernelSU BusyBox and PATH, the watchdog
# fallback must still execute and bound the monitor rather than skip sampling.
mkdir -p "$TMP/no-timeout-bin"
for bin in awk cat date grep head id mkdir mv rm rmdir sed sh sleep tail touch tr wc; do
    ln -sf "$(command -v "$bin")" "$TMP/no-timeout-bin/$bin"
done
ln -sf "$TMP/bin/id" "$TMP/no-timeout-bin/id"
ln -sf "$TMP/bin/getprop" "$TMP/no-timeout-bin/getprop"
ln -sf "$TMP/bin/sleep" "$TMP/no-timeout-bin/sleep"
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_NO_TIMEOUT=1 TEST_HANG_CHILD=1
timeout 8 env PATH="$TMP/no-timeout-bin" BERRY_TOYBOX_BIN="$TMP/bin/toybox" \
    BERRY_KSU_BUSYBOX="$TMP/missing-busybox" sh "$TMP/module/service.sh"
unset TEST_NO_TIMEOUT TEST_HANG_CHILD
child_pid="$(cat "$TMP/hung-child-pid")"
child_state="$(awk '{print $3}' "/proc/$child_pid/stat" 2>/dev/null || :)"
[ -z "$child_state" ] || [ "$child_state" = Z ]
test "$(wc -l < "$TMP/samples")" -ge 2
grep -q 'fcm_check_end rc=124' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: watchdog fallback keeps bounded patrol active without timeout applets'

# If both timeout and setsid are unavailable, snapshot and reap the monitor
# process tree by PID/starttime so child probes cannot hold the monitor flock.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_NO_TIMEOUT=1 TEST_NO_SETSID=1 TEST_HANG_CHILD=1
timeout 8 env PATH="$TMP/no-timeout-bin" BERRY_TOYBOX_BIN="$TMP/bin/toybox" \
    BERRY_KSU_BUSYBOX="$TMP/missing-busybox" sh "$TMP/module/service.sh"
unset TEST_NO_TIMEOUT TEST_NO_SETSID TEST_HANG_CHILD
child_pid="$(cat "$TMP/hung-child-pid")"
child_state="$(awk '{print $3}' "/proc/$child_pid/stat" 2>/dev/null || :)"
[ -z "$child_state" ] || [ "$child_state" = Z ]
test "$(wc -l < "$TMP/samples")" -ge 2
grep -q 'fcm_check_end rc=124' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: process-tree watchdog cleans child probes without timeout or setsid'

# A BusyBox timeout with -k but without setsid is not safe for descendants;
# it must fall back to the /proc process-tree watchdog rather than kill only
# the monitor shell and leave its child probe running.
cat > "$TMP/bin/busybox-timeout-no-setsid" <<'MOCK'
#!/bin/sh
if [ "$1" = --list ]; then
    printf '%s\n' timeout kill
    exit 0
fi
if [ "$1" = timeout ]; then
    echo called > "$TEST_DIR/busybox-timeout-called"
    shift
    if [ "$1" = -k ]; then shift 2; fi
    duration="$1"; shift
    exec /usr/bin/timeout -k 1 "$duration" "$@"
fi
if [ "$1" = kill ]; then shift; exec /bin/kill "$@"; fi
exit 2
MOCK
chmod +x "$TMP/bin/busybox-timeout-no-setsid"
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
rm -f "$TMP/busybox-timeout-called"
export TEST_NO_TIMEOUT=1 TEST_NO_SETSID=1 TEST_HANG_CHILD=1
timeout 8 env PATH="$TMP/no-timeout-bin" BERRY_TOYBOX_BIN="$TMP/bin/toybox" \
    BERRY_KSU_BUSYBOX="$TMP/bin/busybox-timeout-no-setsid" sh "$TMP/module/service.sh"
unset TEST_NO_TIMEOUT TEST_NO_SETSID TEST_HANG_CHILD
test ! -e "$TMP/busybox-timeout-called"
child_pid="$(cat "$TMP/hung-child-pid")"
child_state="$(awk '{print $3}' "/proc/$child_pid/stat" 2>/dev/null || :)"
[ -z "$child_state" ] || [ "$child_state" = Z ]
test "$(wc -l < "$TMP/samples")" -ge 2
grep -q 'fcm_check_end rc=124' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: BusyBox timeout without setsid falls back to process-tree watchdog'

# A BusyBox timeout applet without -k must not be selected just because
# --list reports it. Fall back to the bounded process-group watchdog.
cat > "$TMP/bin/busybox-no-k" <<'MOCK'
#!/bin/sh
if [ "$1" = --list ]; then
    printf '%s\n' timeout
    exit 0
fi
if [ "$1" = timeout ]; then
    echo 'timeout: unrecognized option -k' >&2
    exit 2
fi
exit 2
MOCK
chmod +x "$TMP/bin/busybox-no-k"
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_NO_TIMEOUT=1 TEST_HANG_CHILD=1
timeout 8 env PATH="$TMP/no-timeout-bin" BERRY_TOYBOX_BIN="$TMP/bin/toybox" \
    BERRY_KSU_BUSYBOX="$TMP/bin/busybox-no-k" sh "$TMP/module/service.sh"
unset TEST_NO_TIMEOUT TEST_HANG_CHILD
child_pid="$(cat "$TMP/hung-child-pid")"
child_state="$(awk '{print $3}' "/proc/$child_pid/stat" 2>/dev/null || :)"
[ -z "$child_state" ] || [ "$child_state" = Z ]
test "$(wc -l < "$TMP/samples")" -ge 2
grep -q 'fcm_check_end rc=124' "$TMP/data/guard.log"
test ! -d "$TMP/data/service.lock"
echo 'PASS: BusyBox timeout without -k falls back to bounded watchdog'

# Service shutdown must stop an in-flight maintenance wrapper and its ctl child.
touch "$TMP/module/module.prop"
echo 1 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
export TEST_BLOCK_FIX=1
sh "$TMP/module/service.sh" &
service_pid=$!
n=0
while ! grep -q 'maintenance_start .*operation=guard_fix' "$TMP/data/guard.log" 2>/dev/null && [ "$n" -lt 60 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
grep -q 'maintenance_start .*operation=guard_fix' "$TMP/data/guard.log"
n=0
while [ ! -s "$TMP/fix-child-pid" ] && [ "$n" -lt 60 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
test -s "$TMP/fix-child-pid"
fix_child="$(cat "$TMP/fix-child-pid")"
kill -TERM "$service_pid"
wait "$service_pid" 2>/dev/null || :
unset TEST_BLOCK_FIX
child_state="$(awk '{print $3}' "/proc/$fix_child/stat" 2>/dev/null || :)"
[ -z "$child_state" ] || [ "$child_state" = Z ]
test ! -d "$TMP/data/maintenance.lock"
test ! -d "$TMP/data/service.lock"
echo 'PASS: service shutdown reaps the maintenance owner and its ctl child'


# A replacement patrol must not start while a recorded monitor process
# cannot be identity-verified; after that process exits, the stale record is
# cleared and the supervisor resumes patrol automatically.
touch "$TMP/module/module.prop"
echo 0 > "$TMP/data/enabled"
echo passive > "$TMP/data/wake-mode"
: > "$TMP/samples"
: > "$TMP/data/guard.log"
rm -f "$TMP/data/mcs-monitor.lock.owner"
sh "$TMP/module/service.sh" &
service_pid=$!
n=0
while [ "$(grep -c 'patrol_supervisor_start' "$TMP/data/guard.log" 2>/dev/null || true)" -lt 1 ] && [ "$n" -lt 80 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
[ "$(grep -c 'patrol_supervisor_start' "$TMP/data/guard.log")" -eq 1 ]
patrol_pid="$(awk '{print $1}' "$TMP/data/service.lock/patrol")"
[ "$patrol_pid" -gt 1 ]
cat > "$TMP/fcm-monitor.sh" <<'MOCK'
#!/bin/sh
while :; do :; done
MOCK
chmod +x "$TMP/fcm-monitor.sh"
sh "$TMP/fcm-monitor.sh" &
dummy_monitor_pid=$!
/bin/sleep 0.1
kill -0 "$dummy_monitor_pid"
printf 'not-a-pid not-a-starttime\n' > "$TMP/data/mcs-monitor.lock.owner"
kill -KILL "$patrol_pid"
n=0
while ! grep -q 'patrol_restart_blocked reason=monitor_owner_cleanup_unconfirmed' "$TMP/data/guard.log" 2>/dev/null && [ "$n" -lt 80 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
grep -q 'patrol_restart_blocked reason=monitor_owner_cleanup_unconfirmed' "$TMP/data/guard.log"
[ "$(grep -c 'patrol_supervisor_start' "$TMP/data/guard.log")" -eq 1 ]
kill -TERM "$dummy_monitor_pid"
wait "$dummy_monitor_pid" 2>/dev/null || :
n=0
while [ "$(grep -c 'patrol_supervisor_start' "$TMP/data/guard.log" 2>/dev/null || true)" -lt 2 ] && [ "$n" -lt 80 ]; do
    /bin/sleep 0.1
    n=$((n + 1))
done
[ "$(grep -c 'patrol_supervisor_start' "$TMP/data/guard.log")" -ge 2 ]
grep -q 'stale_monitor_owner_record_cleared reason=no_monitor_process' "$TMP/data/guard.log"
kill -TERM "$service_pid"
wait "$service_pid" 2>/dev/null || :
test ! -d "$TMP/data/service.lock"
echo 'PASS: supervisor waits for monitor exit, then clears stale owner and resumes patrol'
