#!/system/bin/sh
# KernelSU late_start service. Does nothing if the current boot lost temporary Root.
MODDIR="${0%/*}"
DATA=/data/adb/berry_fcm_ksu
mkdir -p "$DATA" || exit 0
[ "$(id -u)" = 0 ] || exit 0
LOCK="$DATA/service.lock"
MAINTENANCE_LOCK="$DATA/maintenance.lock"
TOYBOX_BIN="${BERRY_TOYBOX_BIN:-/system/bin/toybox}"
KSU_BUSYBOX="${BERRY_KSU_BUSYBOX:-/data/adb/ksu/bin/busybox}"
proc_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $20}'
}
proc_group_id() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $3}'
}
process_group_alive() {
    awk -v pgid="$1" '
        {
            stat=$0
            sub(/^.*[)] /, "", stat)
            split(stat, fields, " ")
            if (fields[1] != "Z" && fields[3] == pgid) found=1
        }
        END { exit !found }
    ' /proc/[0-9]*/stat 2>/dev/null
}
proc_state() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $1}'
}
service_process_matches() {
    pid="$1"
    case "$pid" in ""|*[!0-9]*) return 1;; esac
    [ "$pid" -gt 1 ] && kill -0 "$pid" 2>/dev/null || return 1
    cmdline="$(tr "\000" " " < "/proc/$pid/cmdline" 2>/dev/null)"
    case "$cmdline" in *"/berry_fcm_ksu/service.sh"*) return 0;; *) return 1;; esac
}
service_identity() {
    pid="$1"; stamp="$2"
    case "$pid:$stamp" in *[!0-9:]*|:*|*:) return 1;; esac
    [ "$pid" -gt 1 ] && [ "$stamp" -gt 0 ] && kill -0 "$pid" 2>/dev/null || return 1
    [ "$(proc_start_time "$pid")" = "$stamp" ] || return 1
    service_process_matches "$pid"
}
patrol_identity_for_lock() {
    stale_patrol_pid=; stale_patrol_stamp=
    IFS=' ' read -r stale_patrol_pid stale_patrol_stamp < "$LOCK/patrol" 2>/dev/null || return 1
    case "$stale_patrol_pid:$stale_patrol_stamp" in *[!0-9:]*|:*|*:) return 1;; esac
    [ "$stale_patrol_pid" -gt 1 ] && [ "$stale_patrol_stamp" -gt 0 ] &&
        kill -0 "$stale_patrol_pid" 2>/dev/null || return 1
    [ "$(proc_start_time "$stale_patrol_pid")" = "$stale_patrol_stamp" ] || return 1
    tr "\000" " " < "/proc/$stale_patrol_pid/cmdline" 2>/dev/null | grep -Fq "patrol.sh"
}
stop_stale_patrol() {
    patrol_identity_for_lock || return 0
    kill -TERM "$stale_patrol_pid" 2>/dev/null || :
    n=0
    while patrol_identity_for_lock && [ "$(proc_state "$stale_patrol_pid" 2>/dev/null)" != Z ] && [ "$n" -lt 4 ]; do
        sleep 1; n=$((n + 1))
    done
    if patrol_identity_for_lock && [ "$(proc_state "$stale_patrol_pid" 2>/dev/null)" != Z ]; then
        kill -KILL "$stale_patrol_pid" 2>/dev/null || :
        n=0
        while patrol_identity_for_lock && [ "$(proc_state "$stale_patrol_pid" 2>/dev/null)" != Z ] && [ "$n" -lt 3 ]; do
            sleep 1; n=$((n + 1))
        done
    fi
    if patrol_identity_for_lock && [ "$(proc_state "$stale_patrol_pid" 2>/dev/null)" != Z ]; then
        printf '[%s] stale_patrol_stop_unconfirmed pid=%s start=%s; refusing a duplicate patrol\n' \
            "$(date '+%F %T')" "$stale_patrol_pid" "$stale_patrol_stamp" >> "$DATA/guard.log"
        return 1
    fi
    printf '[%s] stale_patrol_stopped pid=%s start=%s before service restart\n' \
        "$(date '+%F %T')" "$stale_patrol_pid" "$stale_patrol_stamp" >> "$DATA/guard.log"
    return 0
}

monitor_owner_alive() {
    monitor_pid=; monitor_stamp=
    IFS=' ' read -r monitor_pid monitor_stamp < "$DATA/mcs-monitor.lock.owner" 2>/dev/null || return 1
    case "$monitor_pid:$monitor_stamp" in *[!0-9:]*|:*|*:) return 1;; esac
    [ "$monitor_pid" -gt 1 ] && [ "$monitor_stamp" -gt 0 ] &&
        kill -0 "$monitor_pid" 2>/dev/null || return 1
    [ "$(proc_start_time "$monitor_pid")" = "$monitor_stamp" ] || return 1
    tr "\000" " " 2>/dev/null < "/proc/$monitor_pid/cmdline" | grep -Fq "fcm-monitor.sh"
}
monitor_group_tool() {
    if [ -x "$TOYBOX_BIN" ] && "$TOYBOX_BIN" --list 2>/dev/null | grep -qx kill; then
        printf '%s\n' "$TOYBOX_BIN"
    elif [ -x "$KSU_BUSYBOX" ] && "$KSU_BUSYBOX" --list 2>/dev/null | grep -qx kill; then
        printf '%s\n' "$KSU_BUSYBOX"
    fi
}
stop_monitor_owner() {
    [ -s "$DATA/mcs-monitor.lock.owner" ] || { rm -f "$DATA/mcs-monitor.lock.owner"; return 0; }
    monitor_pid=; monitor_stamp=; monitor_pgid=; monitor_isolated=
    IFS=' ' read -r monitor_pid monitor_stamp monitor_pgid monitor_isolated < "$DATA/mcs-monitor.lock.owner" 2>/dev/null || :
    case "$monitor_pid:$monitor_stamp" in *[!0-9:]*|:*|*:)
        printf '[%s] monitor_owner_identity_invalid; preserving owner lock\n' "$(date '+%F %T')" >> "$DATA/guard.log"
        return 1
        ;;
    esac
    [ "$monitor_pid" -gt 1 ] && [ "$monitor_stamp" -gt 0 ] || return 1
    case "$monitor_isolated" in
        1)
            [ "$monitor_pgid" = "$monitor_pid" ] || return 1
            monitor_group_tool="$(monitor_group_tool)"
            [ -n "$monitor_group_tool" ] || {
                printf '[%s] monitor_group_tool_unavailable pid=%s; preserving owner lock\n' "$(date '+%F %T')" "$monitor_pid" >> "$DATA/guard.log"
                return 1
            }
            if kill -0 "$monitor_pid" 2>/dev/null; then
                [ "$(proc_start_time "$monitor_pid")" = "$monitor_stamp" ] &&
                    [ "$(proc_group_id "$monitor_pid")" = "$monitor_pgid" ] || {
                        printf '[%s] monitor_owner_pid_reused_or_moved pid=%s; refusing group signal\n' "$(date '+%F %T')" "$monitor_pid" >> "$DATA/guard.log"
                        return 1
                    }
                if [ "$(proc_state "$monitor_pid" 2>/dev/null)" != Z ] &&
                   ! tr -d '\000' < "/proc/$monitor_pid/cmdline" 2>/dev/null | grep -Fq 'fcm-monitor.sh'; then
                    printf '[%s] monitor_owner_cmdline_mismatch pid=%s; refusing group signal\n' "$(date '+%F %T')" "$monitor_pid" >> "$DATA/guard.log"
                    return 1
                fi
            fi
            if process_group_alive "$monitor_pgid"; then
                "$monitor_group_tool" kill -TERM "-$monitor_pgid" 2>/dev/null || :
                n=0
                while process_group_alive "$monitor_pgid" && [ "$n" -lt 3 ]; do
                    sleep 1; n=$((n + 1))
                done
                if process_group_alive "$monitor_pgid"; then
                    "$monitor_group_tool" kill -KILL "-$monitor_pgid" 2>/dev/null || :
                    n=0
                    while process_group_alive "$monitor_pgid" && [ "$n" -lt 3 ]; do
                        sleep 1; n=$((n + 1))
                    done
                fi
            fi
            if process_group_alive "$monitor_pgid"; then
                printf '[%s] monitor_group_stop_unconfirmed pid=%s start=%s pgid=%s\n' \
                    "$(date '+%F %T')" "$monitor_pid" "$monitor_stamp" "$monitor_pgid" >> "$DATA/guard.log"
                return 1
            fi
            rm -f "$DATA/mcs-monitor.lock.owner"
            return 0
            ;;
        0|'') :;;
        *) return 1;;
    esac
    monitor_owner_alive || { rm -f "$DATA/mcs-monitor.lock.owner"; return 0; }
    kill -TERM "$monitor_pid" 2>/dev/null || :
    n=0
    while monitor_owner_alive && [ "$(proc_state "$monitor_pid" 2>/dev/null)" != Z ] && [ "$n" -lt 3 ]; do
        sleep 1; n=$((n + 1))
    done
    if monitor_owner_alive && [ "$(proc_state "$monitor_pid" 2>/dev/null)" != Z ]; then
        kill -KILL "$monitor_pid" 2>/dev/null || :
        n=0
        while monitor_owner_alive && [ "$(proc_state "$monitor_pid" 2>/dev/null)" != Z ] && [ "$n" -lt 3 ]; do
            sleep 1; n=$((n + 1))
        done
    fi
    if monitor_owner_alive && [ "$(proc_state "$monitor_pid" 2>/dev/null)" != Z ]; then
        printf '[%s] monitor_owner_stop_unconfirmed pid=%s start=%s\n' \
            "$(date '+%F %T')" "$monitor_pid" "$monitor_stamp" >> "$DATA/guard.log"
        return 1
    fi
    rm -f "$DATA/mcs-monitor.lock.owner"
}

maintenance_owner_identity() {
    maintenance_pid=; maintenance_stamp=
    IFS=' ' read -r maintenance_pid maintenance_stamp < "$MAINTENANCE_LOCK/owner" 2>/dev/null || return 1
    case "$maintenance_pid:$maintenance_stamp" in *[!0-9:]*|:*|*:) return 1;; esac
    [ "$maintenance_pid" -gt 1 ] && [ "$maintenance_stamp" -gt 0 ] &&
        kill -0 "$maintenance_pid" 2>/dev/null || return 1
    [ "$(proc_start_time "$maintenance_pid")" = "$maintenance_stamp" ] || return 1
    [ "$(proc_state "$maintenance_pid")" != Z ]
}
maintenance_child_group_alive() {
    [ -n "$maintenance_child_tool" ] && [ -n "$maintenance_child_pgid" ] &&
        process_group_alive "$maintenance_child_pgid"
}
stop_maintenance_child() {
    [ -s "$MAINTENANCE_LOCK/child" ] || return 0
    child_file_pid=; child_file_stamp=; child_file_pgid=; child_file_tool=
    IFS=' ' read -r child_file_pid child_file_stamp child_file_pgid child_file_tool < "$MAINTENANCE_LOCK/child" 2>/dev/null || :
    case "$child_file_pid:$child_file_stamp:$child_file_pgid" in
        *[!0-9:]*|:*|*:)
            printf '[%s] maintenance_child_identity_invalid; refusing to clear maintenance lock\n' "$(date '+%F %T')" >> "$DATA/guard.log"
            return 1
            ;;
    esac
    [ "$child_file_pid" -gt 1 ] && [ "$child_file_stamp" -gt 0 ] &&
        [ "$child_file_pgid" = "$child_file_pid" ] || return 1
    case "$child_file_tool" in "$TOYBOX_BIN"|"$KSU_BUSYBOX") :;; *)
        printf '[%s] maintenance_child_tool_invalid; refusing to clear maintenance lock\n' "$(date '+%F %T')" >> "$DATA/guard.log"
        return 1
        ;;
    esac
    [ -x "$child_file_tool" ] &&
        "$child_file_tool" --list 2>/dev/null | grep -qx kill || return 1
    if kill -0 "$child_file_pid" 2>/dev/null; then
        [ "$(proc_start_time "$child_file_pid")" = "$child_file_stamp" ] &&
            [ "$(proc_group_id "$child_file_pid")" = "$child_file_pgid" ] || {
                printf '[%s] maintenance_child_pid_reused_or_moved pid=%s; refusing group signal\n' "$(date '+%F %T')" "$child_file_pid" >> "$DATA/guard.log"
                return 1
            }
    fi
    maintenance_child_stop_pid="$child_file_pid"
    maintenance_child_stop_stamp="$child_file_stamp"
    maintenance_child_pgid="$child_file_pgid"
    maintenance_child_tool="$child_file_tool"
    if maintenance_child_group_alive; then
        "$maintenance_child_tool" kill -TERM "-$maintenance_child_pgid" 2>/dev/null || :
        n=0
        while maintenance_child_group_alive && [ "$n" -lt 4 ]; do
            sleep 1; n=$((n + 1))
        done
        if maintenance_child_group_alive; then
            "$maintenance_child_tool" kill -KILL "-$maintenance_child_pgid" 2>/dev/null || :
            n=0
            while maintenance_child_group_alive && [ "$n" -lt 3 ]; do
                sleep 1; n=$((n + 1))
            done
        fi
    fi
    if maintenance_child_group_alive; then
        printf '[%s] maintenance_child_stop_unconfirmed pid=%s start=%s pgid=%s\n' \
            "$(date '+%F %T')" "$maintenance_child_stop_pid" "$maintenance_child_stop_stamp" "$maintenance_child_pgid" >> "$DATA/guard.log"
        return 1
    fi
    if [ "$(awk '{print $1}' "$MAINTENANCE_LOCK/child" 2>/dev/null)" = "$maintenance_child_stop_pid" ] &&
       [ "$(awk '{print $2}' "$MAINTENANCE_LOCK/child" 2>/dev/null)" = "$maintenance_child_stop_stamp" ]; then
        rm -f "$MAINTENANCE_LOCK/child"
    fi
    return 0
}
stop_maintenance_owner() {
    [ -d "$MAINTENANCE_LOCK" ] || return 0
    n=0
    while [ ! -s "$MAINTENANCE_LOCK/owner" ] && [ "$n" -lt 2 ]; do
        sleep 1; n=$((n + 1))
    done
    if [ ! -s "$MAINTENANCE_LOCK/owner" ]; then
        printf '[%s] maintenance_owner_unpublished; refusing to clear maintenance lock\n' "$(date '+%F %T')" >> "$DATA/guard.log"
        return 1
    fi
    maintenance_pid=; maintenance_stamp=
    IFS=' ' read -r maintenance_pid maintenance_stamp < "$MAINTENANCE_LOCK/owner" 2>/dev/null || :
    case "$maintenance_pid:$maintenance_stamp" in
        *[!0-9:]*|:*|*:)
            printf '[%s] maintenance_owner_identity_invalid; refusing to clear maintenance lock\n' "$(date '+%F %T')" >> "$DATA/guard.log"
            return 1
            ;;
    esac
    [ "$maintenance_pid" -gt 1 ] && [ "$maintenance_stamp" -gt 0 ] || {
        printf '[%s] maintenance_owner_identity_invalid; refusing to clear maintenance lock\n' "$(date '+%F %T')" >> "$DATA/guard.log"
        return 1
    }
    stop_maintenance_child || return 1
    if ! maintenance_owner_identity; then
        rm -rf "$MAINTENANCE_LOCK"
        return 0
    fi
    maintenance_stop_pid="$maintenance_pid"
    maintenance_stop_stamp="$maintenance_stamp"
    kill -TERM "$maintenance_stop_pid" 2>/dev/null || :
    n=0
    while maintenance_owner_identity &&
          [ "$maintenance_pid" = "$maintenance_stop_pid" ] &&
          [ "$maintenance_stamp" = "$maintenance_stop_stamp" ] && [ "$n" -lt 4 ]; do
        sleep 1; n=$((n + 1))
    done
    if maintenance_owner_identity &&
       [ "$maintenance_pid" = "$maintenance_stop_pid" ] &&
       [ "$maintenance_stamp" = "$maintenance_stop_stamp" ]; then
        kill -KILL "$maintenance_stop_pid" 2>/dev/null || :
        n=0
        while maintenance_owner_identity &&
              [ "$maintenance_pid" = "$maintenance_stop_pid" ] &&
              [ "$maintenance_stamp" = "$maintenance_stop_stamp" ] && [ "$n" -lt 3 ]; do
            sleep 1; n=$((n + 1))
        done
    fi
    if maintenance_owner_identity &&
       [ "$maintenance_pid" = "$maintenance_stop_pid" ] &&
       [ "$maintenance_stamp" = "$maintenance_stop_stamp" ]; then
        printf '[%s] maintenance_owner_stop_unconfirmed pid=%s start=%s\n' \
            "$(date '+%F %T')" "$maintenance_stop_pid" "$maintenance_stop_stamp" >> "$DATA/guard.log"
        return 1
    fi
    if [ -d "$MAINTENANCE_LOCK" ] &&
       [ "$(awk '{print $1}' "$MAINTENANCE_LOCK/owner" 2>/dev/null)" = "$maintenance_stop_pid" ] &&
       [ "$(awk '{print $2}' "$MAINTENANCE_LOCK/owner" 2>/dev/null)" = "$maintenance_stop_stamp" ]; then
        rm -rf "$MAINTENANCE_LOCK"
    fi
    printf '[%s] maintenance_owner_stopped pid=%s start=%s\n' \
        "$(date '+%F %T')" "$maintenance_stop_pid" "$maintenance_stop_stamp" >> "$DATA/guard.log"
    return 0
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
    if service_process_matches "$old"; then
        printf '[%s] service_lock_identity_unverified pid=%s start=%s; refusing duplicate supervisor\n' \
            "$(date '+%F %T')" "$old" "$stamp" >> "$DATA/guard.log"
        exit 0
    fi
    stop_stale_patrol || exit 0
    stop_maintenance_owner || exit 0
    stale="$DATA/service.lock.stale.$old.$stamp"
    if mv "$LOCK" "$stale" 2>/dev/null; then rm -rf "$stale"; fi
    mkdir "$LOCK" 2>/dev/null || exit 0
fi
stop_monitor_owner || exit 0
echo $ > "$LOCK/pid"
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
patrol_sample_started=0
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
    rm -f "$DATA/patrol.heartbeat" "$DATA/patrol.sample.heartbeat"
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
    if [ "$(cat "$DATA/enabled" 2>/dev/null)" = 1 ]; then patrol_sample_started="$patrol_started"; else patrol_sample_started=0; fi
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
service_cleanup() {
    cleanup_ok=1
    stop_timer || cleanup_ok=0
    stop_monitor_owner || cleanup_ok=0
    stop_patrol || cleanup_ok=0
    stop_maintenance_owner || cleanup_ok=0
    if [ "$cleanup_ok" = 1 ]; then
        rm -rf "$LOCK"
    else
        printf '[%s] service_cleanup_incomplete; preserving lock to block duplicate workers\n' "$(date '+%F %T')" >> "$DATA/guard.log"
    fi
}
stop_service() { stop_wait; exit 0; }
refresh_mode() {
    mode_changed=1
    stop_wait
    [ -z "$patrol_pid" ] || kill -USR1 "$patrol_pid" 2>/dev/null || :
    if [ "$(cat "$DATA/enabled" 2>/dev/null)" = 1 ]; then
        patrol_sample_started="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
        case "$patrol_sample_started" in ""|*[!0-9]*) patrol_sample_started=0;; esac
        rm -f "$DATA/patrol.sample.heartbeat"
    else
        patrol_sample_started=0
    fi
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
        sample_hb="$(cat "$DATA/patrol.sample.heartbeat" 2>/dev/null)"
        case "$sample_hb" in ""|*[!0-9]*) sample_hb=0;; esac
        sample_stale=0
        if [ "$(cat "$DATA/enabled" 2>/dev/null)" = 1 ]; then
            if [ "$sample_hb" -gt 0 ] && [ "$now_up" -ge "$sample_hb" ] && [ $((now_up - sample_hb)) -gt 90 ]; then
                sample_stale=1
            elif [ "$sample_hb" -eq 0 ] && [ "$patrol_sample_started" -gt 0 ] &&
                 [ "$now_up" -ge "$patrol_sample_started" ] && [ $((now_up - patrol_sample_started)) -gt 90 ]; then
                sample_stale=1
            fi
        fi
        if [ "$patrol_stale" = 1 ] || [ "$sample_stale" = 1 ]; then
            watchdog_reason=patrol_heartbeat
            [ "$sample_stale" = 1 ] && watchdog_reason=monitor_sample
            [ "$patrol_stale" = 1 ] && [ "$sample_stale" = 1 ] && watchdog_reason=patrol_and_monitor
            printf '[%s] patrol_watchdog_stale reason=%s pid=%s heartbeat=%s sample=%s started=%s uptime=%s\n' \
                "$(date '+%F %T')" "$watchdog_reason" "$patrol_pid" "$hb" "$sample_hb" "$patrol_started" "$now_up" >> "$DATA/guard.log"
            if [ "$sample_stale" = 1 ]; then stop_monitor_owner || :; fi
            stop_patrol || :
            rm -f "$DATA/patrol.heartbeat" "$DATA/patrol.sample.heartbeat"
            patrol_started="$now_up"
            if [ "$(cat "$DATA/enabled" 2>/dev/null)" = 1 ]; then patrol_sample_started="$now_up"; else patrol_sample_started=0; fi
        fi
    fi
    sleep 5 &
    wait_pid=$!
    wait "$wait_pid" 2>/dev/null || :
    wait_pid=
done
exit 0
