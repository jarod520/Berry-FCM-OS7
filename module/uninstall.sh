#!/system/bin/sh
# Stop the live supervisor before KernelSU removes the module directory.
DATA=/data/adb/berry_fcm_ksu
LOCK="$DATA/service.lock"
pid="$(cat "$LOCK/pid" 2>/dev/null)"
stamp="$(cat "$LOCK/starttime" 2>/dev/null)"
case "$stamp" in ""|*[!0-9]*) stamp=;; esac
proc_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d '\n' < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $20}'
}
is_guardian() {
    case "$pid" in ""|*[!0-9]*) return 1;; esac
    [ "$pid" -gt 1 ] && kill -0 "$pid" 2>/dev/null || return 1
    current_stamp="$(proc_start_time "$pid")"
    case "$current_stamp" in ""|*[!0-9]*) return 1;; esac
    cmdline="$(tr "\000" " " < "/proc/$pid/cmdline" 2>/dev/null)"
    case "$cmdline" in *"/berry_fcm_ksu/service.sh"*) :;; *) return 1;; esac
    if [ -n "$stamp" ]; then
        [ "$current_stamp" = "$stamp" ] || return 1
    else
        # RC5 did not persist starttime; pin the verified process before waiting.
        stamp="$current_stamp"
    fi
    return 0
}
if is_guardian; then
    kill -TERM "$pid" 2>/dev/null || :
    # service_cleanup may need up to about 36 seconds for all bounded workers.
    n=0
    while is_guardian && [ "$n" -lt 45 ]; do
        sleep 1
        n=$((n + 1))
    done
    if is_guardian; then
        kill -KILL "$pid" 2>/dev/null || :
        n=0
        while is_guardian && [ "$n" -lt 3 ]; do sleep 1; n=$((n + 1)); done
    fi
    is_guardian && echo '警告：BerryFCM 守护进程在卸载时仍未退出' >&2
fi
if [ -d "$LOCK" ]; then
    echo '警告：卸载时 service.lock 仍存在，后台 worker 清理未确认；请检查 guard.log 与 owner 文件' >&2
fi
exit 0
