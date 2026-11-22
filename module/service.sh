#!/system/bin/sh
# KernelSU late_start service. Does nothing if the current boot lost temporary Root.
MODDIR="${0%/*}"
DATA=/data/adb/berry_fcm_ksu
mkdir -p "$DATA" || exit 0
[ "$(id -u)" = 0 ] || exit 0
LOCK="$DATA/service.lock"
MAINTENANCE_LOCK="$DATA/maintenance.lock"
proc_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $20}'
}
proc_state() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $1}'
}
service_identity() {
    pid="$1"; stamp="$2"
    case "$pid" in ""|*[!0-9]*) return 1;; esac
    [ "$pid" -gt 1 ] && kill -0 "$pid" 2>/dev/null || return 1
    cmdline="$(tr "\000" " " < "/proc/$pid/cmdline" 2>/dev/null)"
    case "$cmdline" in *"/berry_fcm_ksu/service.sh"*) :;; *) return 1;; esac
    [ -z "$stamp" ] || [ "$(proc_start_time "$pid")" = "$stamp" ]
}
if ! mkdir "$LOCK" 2>/dev/null; then
    old="$(cat "$LOCK/pid" 2>/dev/null)"
    stamp="$(cat "$LOCK/starttime" 2>/dev/null)"
    if [ -z "$old" ] || [ -z "$stamp" ]; then
        sleep 1
        old="$(cat "$LOCK/pid" 2>/dev/null)"
        stamp="$(cat "$LOCK/starttime" 2>/dev/null)"
    fi
    service_identity "$old" "$stamp" && exit 0
    stale="$DATA/service.lock.stale.$$"
    if mv "$LOCK" "$stale" 2>/dev/null; then rm -rf "$stale"; fi
    mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK/pid"
proc_start_time "$$" > "$LOCK/starttime"
echo $$ > "$LOCK/wake-pid"
cgroup_path() {
    while IFS=: read -r hierarchy controllers group; do
        if [ "$hierarchy" = 0 ] && [ -z "$controllers" ]; then
            printf '%s\n' "$group"
            return
        fi
    done < "/proc/$$/cgroup"
}
group="$(cgroup_path)"
cgroup_ready=1
case "$group" in
    /apps/*)
        # Hot install and WebUI can inherit the Manager's app freezer group.
        # Move only this service; workers inherit the verified group.
        if { printf '%s\n' "$$" > /sys/fs/cgroup/cgroup.procs; } 2>/dev/null &&
           [ "$(cgroup_path)" = / ]; then
            printf '[%s] service_cgroup_detached pid=%s from=%s to=/\n' "$(date '+%F %T')" "$$" "$group" >> "$DATA/guard.log"
        else
            cgroup_ready=0
            printf '[%s] service_cgroup_detach_failed pid=%s group=%s\n' "$(date '+%F %T')" "$$" "$group" >> "$DATA/guard.log"
        fi
        ;;
esac
wait_pid=
timer_pid=
service_pid=$$
service_stamp="$(cat "$LOCK/starttime" 2>/dev/null)"
stop_wait() { [ -z "$wait_pid" ] || kill "$wait_pid" 2>/dev/null || :; }
stop_timer() {
    [ -n "$timer_pid" ] || return 0
    kill -TERM "$timer_pid" 2>/dev/null || :
    n=0
    while kill -0 "$timer_pid" 2>/dev/null && [ "$(proc_state "$timer_pid" 2>/dev/null)" != Z ] && [ "$n" -lt 4 ]; do
        sleep 1; n=$((n + 1))
    done
    if kill -0 "$timer_pid" 2>/dev/null && [ "$(proc_state "$timer_pid" 2>/dev/null)" != Z ]; then
        kill -KILL "$timer_pid" 2>/dev/null || :
        n=0
        while kill -0 "$timer_pid" 2>/dev/null && [ "$(proc_state "$timer_pid" 2>/dev/null)" != Z ] && [ "$n" -lt 3 ]; do
            sleep 1; n=$((n + 1))
        done
    fi
    if kill -0 "$timer_pid" 2>/dev/null && [ "$(proc_state "$timer_pid" 2>/dev/null)" != Z ]; then
        printf '[%s] timer_stop_unconfirmed pid=%s; refusing to start a duplicate timer worker\n' \
            "$(date '+%F %T')" "$timer_pid" >> "$DATA/guard.log"
        return 1
    fi
    wait "$timer_pid" 2>/dev/null || :
    timer_pid=
}
timer_worker() {
    # The parent owns the service lock. This worker only owns the native timer.
    trap - EXIT USR1 USR2
    alarm_pid=
    log="$DATA/wake-timer.log"
    printf '[%s] timer_worker_started service_pid=%s interval_min=%s\n' \
        "$(date -u '+%FT%TZ')" "$service_pid" "$1" >> "$log"
    timer_worker_cleanup() {
        worker_rc=$?
        if [ -n "$alarm_pid" ]; then
            kill "$alarm_pid" 2>/dev/null || :
            wait "$alarm_pid" 2>/dev/null || :
        fi
        printf '[%s] timer_worker_exited service_pid=%s rc=%s\n' \
            "$(date -u '+%FT%TZ')" "$service_pid" "$worker_rc" >> "$log"
    }
    trap timer_worker_cleanup EXIT
    trap 'exit 0' HUP INT TERM
    echo timed > "$DATA/wake-status"
    while [ -e "$MODDIR/module.prop" ] && [ "$(proc_start_time "$service_pid")" = "$service_stamp" ]; do
        "$MODDIR/bin/wake-timer-arm64" "$1" >> "$log" 2>&1 &
        alarm_pid=$!
        if ! wait "$alarm_pid"; then
            alarm_pid=
            echo fallback > "$DATA/wake-status"
            printf "[%s] 定时器失败，常规巡检继续\n" "$(date "+%F %T")" >> "$log"
            return 1
        fi
        alarm_pid=
        [ "$(proc_start_time "$service_pid")" = "$service_stamp" ] || return 0
        kill -USR2 "$service_pid" 2>/dev/null || return 0
        tail -n 120 "$log" > "$log.tmp" && mv -f "$log.tmp" "$log"
    done
}

sync_timer() {
    stop_timer || return 1
    if [ "$(cat "$DATA/enabled" 2>/dev/null)" = 1 ] &&
       [ "$(cat "$DATA/wake-mode" 2>/dev/null)" = timed ]; then
        if [ "$cgroup_ready" = 1 ]; then
            minutes="$(cat "$DATA/wake-minutes" 2>/dev/null)"
            case "$minutes" in [1-9]|10) :;; *) minutes=3;; esac
            timer_worker "$minutes" &
            timer_pid=$!
        else
            echo cgroup_failed > "$DATA/wake-status"
        fi
    else
        echo passive > "$DATA/wake-status"
    fi
}

# Wait for complete startup, no hard dependency on Shizuku.
n=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$n" -lt 120 ]; do
    sleep 3; n=$((n + 1))
done
printf '[%s] service_started pid=%s wake_mode=%s enabled=%s cgroup_ready=%s\n' \
    "$(date '+%F %T')" "$$" "$(cat "$DATA/wake-mode" 2>/dev/null || echo passive)" \
    "$(cat "$DATA/enabled" 2>/dev/null || echo 0)" "$cgroup_ready" >> "$DATA/guard.log"
PATROL_RESTART_DELAY="${BERRY_PATROL_RESTART_DELAY_SECONDS:-5}"
case "$PATROL_RESTART_DELAY" in ""|*[!0-9]*) PATROL_RESTART_DELAY=5;; esac
patrol_pid=
patrol_stamp=
patrol_started=0
patrol_identity_alive() {
    [ -n "$patrol_pid" ] || return 1
    kill -0 "$patrol_pid" 2>/dev/null || return 1
    [ -n "$patrol_stamp" ] && [ "$(proc_start_time "$patrol_pid")" = "$patrol_stamp" ]
}
patrol_alive() {
    patrol_identity_alive || return 1
    tr "\000" " " 2>/dev/null < "/proc/$patrol_pid/cmdline" | grep -Fq "patrol.sh"
}
start_patrol() {
    rm -f "$DATA/patrol.heartbeat"
    sh "$MODDIR/bin/patrol.sh" </dev/null >> "$DATA/patrol.log" 2>&1 &
    patrol_pid=$!
    patrol_stamp=
    n=0
    while [ -z "$patrol_stamp" ] && [ "$n" -lt 5 ]; do
        patrol_stamp="$(proc_start_time "$patrol_pid")"
        [ -n "$patrol_stamp" ] || sleep 1
        n=$((n + 1))
    done
    if [ -z "$patrol_stamp" ]; then kill "$patrol_pid" 2>/dev/null || :; wait "$patrol_pid" 2>/dev/null || :; patrol_pid=; return 1; fi
    patrol_started="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
    case "$patrol_started" in ""|*[!0-9]*) patrol_started=0;; esac
    printf "%s %s\n" "$patrol_pid" "$patrol_stamp" > "$LOCK/patrol"
    printf '[%s] patrol_supervisor_start pid=%s start=%s\n' "$(date '+%F %T')" "$patrol_pid" "$patrol_stamp" >> "$DATA/guard.log"
}
stop_patrol() {
    [ -n "$patrol_pid" ] || return 0
    if patrol_identity_alive; then
        kill -TERM "$patrol_pid" 2>/dev/null || :
        n=0
        while patrol_identity_alive && [ "$(proc_state "$patrol_pid" 2>/dev/null)" != Z ] && [ "$n" -lt 4 ]; do
            sleep 1; n=$((n + 1))
        done
        if patrol_identity_alive && [ "$(proc_state "$patrol_pid" 2>/dev/null)" != Z ]; then
            kill -KILL "$patrol_pid" 2>/dev/null || :
            n=0
            while patrol_identity_alive && [ "$(proc_state "$patrol_pid" 2>/dev/null)" != Z ] && [ "$n" -lt 3 ]; do
                sleep 1; n=$((n + 1))
            done
        fi
    fi
    if patrol_identity_alive && [ "$(proc_state "$patrol_pid" 2>/dev/null)" != Z ]; then
        printf '[%s] patrol_stop_unconfirmed pid=%s start=%s; supervisor will not spawn a duplicate\n' \
            "$(date '+%F %T')" "$patrol_pid" "$patrol_stamp" >> "$DATA/guard.log"
        return 1
    fi
    wait "$patrol_pid" 2>/dev/null || :
    patrol_pid=; patrol_stamp=
    rm -f "$LOCK/patrol"
}
service_cleanup() { stop_timer; stop_patrol; rm -rf "$LOCK"; }
stop_service() { stop_wait; exit 0; }
refresh_mode() {
    mode_changed=1
    stop_wait
    [ -z "$patrol_pid" ] || kill -USR1 "$patrol_pid" 2>/dev/null || :
}
on_timer() { [ -z "$patrol_pid" ] || kill -USR2 "$patrol_pid" 2>/dev/null || :; }
trap service_cleanup EXIT
trap stop_service HUP INT TERM
trap refresh_mode USR1
trap on_timer USR2

mode_changed=1
while [ -e "$MODDIR/module.prop" ] && [ ! -e "$MODDIR/disable" ]; do
    if [ "$mode_changed" = 1 ]; then mode_changed=0; sync_timer; fi
    if ! patrol_alive; then
        if [ -n "$patrol_pid" ]; then
            if patrol_identity_alive && [ "$(proc_state "$patrol_pid" 2>/dev/null)" != Z ]; then
                stop_patrol || :
            else
                wait "$patrol_pid" 2>/dev/null || :
                patrol_pid=; patrol_stamp=
                rm -f "$LOCK/patrol"
            fi
        fi
        now_up="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
        case "$now_up" in ""|*[!0-9]*) now_up=0;; esac
        if [ -z "$patrol_pid" ] && { [ "$patrol_started" -eq 0 ] || [ "$now_up" -ge $((patrol_started + PATROL_RESTART_DELAY)) ]; }; then start_patrol || :; fi
    else
        hb="$(cat "$DATA/patrol.heartbeat" 2>/dev/null)"
        now_up="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
        case "$hb" in ""|*[!0-9]*) hb=0;; esac
        case "$now_up" in ""|*[!0-9]*) now_up=0;; esac
        patrol_stale=0
        if [ "$hb" -gt 0 ] && [ "$now_up" -ge "$hb" ] && [ $((now_up - hb)) -gt 90 ]; then
            patrol_stale=1
        elif [ "$hb" -eq 0 ] && [ "$patrol_started" -gt 0 ] && [ "$now_up" -ge "$patrol_started" ] && [ $((now_up - patrol_started)) -gt 90 ]; then
            patrol_stale=1
        fi
        if [ "$patrol_stale" = 1 ]; then
            printf '[%s] patrol_watchdog_stale pid=%s heartbeat=%s started=%s uptime=%s\n' "$(date '+%F %T')" "$patrol_pid" "$hb" "$patrol_started" "$now_up" >> "$DATA/guard.log"
            stop_patrol || :
            patrol_started="$now_up"
        fi
    fi
    sleep 5 &
    wait_pid=$!
    wait "$wait_pid" 2>/dev/null || :
    wait_pid=
done
exit 0
