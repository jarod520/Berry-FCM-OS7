#!/system/bin/sh
MODDIR="${0%/*}/.."
MODDIR="$(cd "$MODDIR" 2>/dev/null && pwd)" || exit 1
DATA=/data/adb/berry_fcm_ksu
MAINTENANCE_LOCK="$DATA/maintenance.lock"
TOYBOX_BIN="${BERRY_TOYBOX_BIN:-/system/bin/toybox}"
KSU_BUSYBOX="${BERRY_KSU_BUSYBOX:-/data/adb/ksu/bin/busybox}"
MONITOR_TIMEOUT="${BERRY_MONITOR_TIMEOUT_SECONDS:-25}"
MONITOR_KILL_GRACE="${BERRY_MONITOR_KILL_GRACE:-3}"
case "$MONITOR_TIMEOUT" in ""|*[!0-9]*) MONITOR_TIMEOUT=25;; esac
[ "$MONITOR_TIMEOUT" -gt 0 ] || MONITOR_TIMEOUT=25
case "$MONITOR_KILL_GRACE" in ""|*[!0-9]*) MONITOR_KILL_GRACE=3;; esac
[ "$(id -u)" = 0 ] || exit 10
SERVICE_PID="$(cat "$DATA/service.lock/pid" 2>/dev/null)"
SERVICE_STAMP="$(cat "$DATA/service.lock/starttime" 2>/dev/null)"
service_pid="$SERVICE_PID"
proc_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $20}'
}
parent_alive() {
    case "$SERVICE_PID" in ""|*[!0-9]*) return 1;; esac
    kill -0 "$SERVICE_PID" 2>/dev/null || return 1
    [ -n "$SERVICE_STAMP" ] && [ "$(proc_start_time "$SERVICE_PID")" = "$SERVICE_STAMP" ]
}
run_bounded() {
    seconds="$1"; shift
    if [ -x "$TOYBOX_BIN" ] && "$TOYBOX_BIN" --list 2>/dev/null | grep -qx timeout; then
        "$TOYBOX_BIN" timeout -k "$MONITOR_KILL_GRACE" "$seconds" "$@"
    elif [ -x "$KSU_BUSYBOX" ] &&
         "$KSU_BUSYBOX" --list 2>/dev/null | grep -qx timeout; then
        "$KSU_BUSYBOX" timeout -k "$MONITOR_KILL_GRACE" "$seconds" "$@"
    elif command -v timeout >/dev/null 2>&1; then
        timeout -k "$MONITOR_KILL_GRACE" "$seconds" "$@"
    else
        return 125
    fi
}
wait_pid=
wake_count=0
wake_seen=0
mode_changed=0
last_fix=0
stop_wait() { [ -z "$wait_pid" ] || kill "$wait_pid" 2>/dev/null || :; }
on_wake() { wake_count=$((wake_count + 1)); stop_wait; }
on_mode() { mode_changed=1; stop_wait; }
trap stop_wait EXIT
trap 'exit 0' HUP INT TERM
trap on_wake USR2
trap on_mode USR1
printf '[%s] patrol_started pid=%s service_pid=%s\n' "$(date '+%F %T')" "$$" "$SERVICE_PID" >> "$DATA/guard.log"
while [ -e "$MODDIR/module.prop" ] && [ ! -e "$MODDIR/disable" ] && parent_alive; do
    now="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
    case "$now" in ""|*[!0-9]*) now=0;; esac
    printf '%s\n' "$now" > "$DATA/patrol.heartbeat.tmp" && mv -f "$DATA/patrol.heartbeat.tmp" "$DATA/patrol.heartbeat"
    wake_event=0
    pending="$wake_count"
    if [ "$pending" != "$wake_seen" ]; then wake_event=1; wake_seen="$pending"; fi
    if [ "$(cat "$DATA/enabled" 2>/dev/null)" = 1 ]; then
        now="$(awk '{print int($1)}' /proc/uptime)"
        case "$now" in ''|*[!0-9]*) now=0 ;; esac
        # Read the native GMS state; TCP sockets are auxiliary evidence.
        # It never restarts/kills GMS and never changes DNS/VPN/proxy/routing.
        if [ "$wake_event" = 1 ]; then
            printf '[%s] 定时器触发，检查 GMS 原生状态\n' "$(date '+%F %T')" >> "$DATA/guard.log"
        fi
        check_started_epoch="$(date +%s 2>/dev/null)"
        case "$check_started_epoch" in ''|*[!0-9]*) check_started_epoch=0;; esac
        check_wake_mode="$(cat "$DATA/wake-mode" 2>/dev/null || echo passive)"
        printf '[%s] fcm_check_start pid=%s uptime=%s wake=%s mode=%s\n' \
            "$(date '+%F %T')" "$$" "$now" "$wake_event" "$check_wake_mode" >> "$DATA/guard.log"
        result="$(run_bounded "$MONITOR_TIMEOUT" sh "$MODDIR/bin/fcm-monitor.sh" monitor 2>&1)"
        monitor_rc=$?
        if [ "$monitor_rc" -eq 0 ]; then
            sample_now="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
            case "$sample_now" in ""|*[!0-9]*) sample_now=0;; esac
            if [ "$sample_now" -gt 0 ]; then
                printf '%s\n' "$sample_now" > "$DATA/patrol.sample.heartbeat.tmp" &&
                    mv -f "$DATA/patrol.sample.heartbeat.tmp" "$DATA/patrol.sample.heartbeat"
            fi
        fi
        sample="$(run_bounded 5 sh "$MODDIR/bin/fcm-monitor.sh" snapshot 2>/dev/null)"

        summary="$(printf '%s\n' "$sample" | sed -n 's/.*"fcm_state":"\([a-z_]*\)".*"fcm_sample_time":\([0-9]*\).*"fcm_recovery_decision":"\([a-z_]*\)".*/state=\1 sample_epoch=\2 recovery=\3/p')"
        if [ "$wake_event" = 1 ]; then
            printf '[%s] wake_gms_check_finished rc=%s %s\n' "$(date '+%F %T')" "$monitor_rc" "${summary:-snapshot=unavailable}" >> "$DATA/guard.log"
        fi
        check_finished_epoch="$(date +%s 2>/dev/null)"
        case "$check_finished_epoch" in ''|*[!0-9]*) check_finished_epoch=0;; esac
        check_elapsed=unknown
        if [ "$check_started_epoch" -gt 0 ] && [ "$check_finished_epoch" -ge "$check_started_epoch" ]; then
            check_elapsed=$((check_finished_epoch-check_started_epoch))
        fi
        printf '[%s] fcm_check_end rc=%s elapsed_s=%s %s\n' \
            "$(date '+%F %T')" "$monitor_rc" "$check_elapsed" "${summary:-snapshot=unavailable}" >> "$DATA/guard.log"
        [ -z "$result" ] || printf '[%s] %s\n' "$(date '+%F %T')" "$result" >> "$DATA/guard.log"
        if [ "$last_fix" = 0 ] || [ "$now" -lt "$last_fix" ] || [ $((now - last_fix)) -ge 300 ]; then
            if [ -d "$MAINTENANCE_LOCK" ]; then
                old="$(cat "$MAINTENANCE_LOCK/pid" 2>/dev/null)"
                case "$old" in ''|*[!0-9]*) old=0;; esac
                if [ "$old" -gt 1 ] && kill -0 "$old" 2>/dev/null; then
                    printf '[%s] maintenance_skip pid=%s reason=already_running\n' "$(date '+%F %T')" "$old" >> "$DATA/guard.log"
                else
                    rm -rf "$MAINTENANCE_LOCK"
                fi
            fi
            if [ ! -d "$MAINTENANCE_LOCK" ] && mkdir "$MAINTENANCE_LOCK" 2>/dev/null; then
                (
                    trap 'rm -rf "$MAINTENANCE_LOCK"' EXIT
                    fix_started_epoch="$(date +%s 2>/dev/null)"
                    case "$fix_started_epoch" in ''|*[!0-9]*) fix_started_epoch=0;; esac
                    printf '[%s] maintenance_start pid=%s uptime=%s operation=guard_fix\n' \
                        "$(date '+%F %T')" "$service_pid" "$now" >> "$DATA/guard.log"
                    HEARTBEAT_MODE=auto sh "$MODDIR/bin/ctl.sh" fix >> "$DATA/guard.log" 2>&1
                    fix_rc=$?
                    fix_finished_epoch="$(date +%s 2>/dev/null)"
                    case "$fix_finished_epoch" in ''|*[!0-9]*) fix_finished_epoch=0;; esac
                    fix_elapsed=unknown
                    if [ "$fix_started_epoch" -gt 0 ] && [ "$fix_finished_epoch" -ge "$fix_started_epoch" ]; then
                        fix_elapsed=$((fix_finished_epoch-fix_started_epoch))
                    fi
                    printf '[%s] maintenance_end pid=%s operation=guard_fix rc=%s elapsed_s=%s\n' \
                        "$(date '+%F %T')" "$service_pid" "$fix_rc" "$fix_elapsed" >> "$DATA/guard.log"
                    exit "$fix_rc"
                ) &
                maintenance_pid=$!
                printf '%s\n' "$maintenance_pid" > "$MAINTENANCE_LOCK/pid"
            fi
            last_fix="$now"
        fi
        bytes="$(wc -c < "$DATA/guard.log" 2>/dev/null)"
        case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
        if [ "$bytes" -gt 131072 ]; then
            tail -n 160 "$DATA/guard.log" > "$DATA/guard.log.tmp" && mv -f "$DATA/guard.log.tmp" "$DATA/guard.log"
        fi
    fi
    if [ "$mode_changed" = 1 ] || [ "$wake_count" != "$wake_seen" ]; then mode_changed=0; continue; fi
    sleep 20 &
    wait_pid=$!
    if [ "$mode_changed" = 1 ] || [ "$wake_count" != "$wake_seen" ]; then stop_wait; fi
    wait "$wait_pid" 2>/dev/null || :
    wait_pid=
done
printf '[%s] patrol_exited pid=%s\n' "$(date '+%F %T')" "$$" >> "$DATA/guard.log"
exit 0
