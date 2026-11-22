#!/system/bin/sh
# Stop the live supervisor before KernelSU removes the module directory.
DATA=/data/adb/berry_fcm_ksu
LOCK="$DATA/service.lock"
pid="$(cat "$LOCK/pid" 2>/dev/null)"
stamp="$(cat "$LOCK/starttime" 2>/dev/null)"
proc_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d '\n' < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $20}'
}
is_guardian() {
    case "$pid" in ""|*[!0-9]*) return 1;; esac
    [ "$pid" -gt 1 ] && kill -0 "$pid" 2>/dev/null || return 1
    cmdline="$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
    case "$cmdline" in *"/berry_fcm_ksu/service.sh"*) :;; *) return 1;; esac
    [ -z "$stamp" ] || [ "$(proc_start_time "$pid")" = "$stamp" ]
}
if is_guardian; then
    kill -TERM "$pid" 2>/dev/null || :
    n=0
    while is_guardian && [ "$n" -lt 8 ]; do
        sleep 1
        n=$((n + 1))
    done
    if is_guardian; then kill -KILL "$pid" 2>/dev/null || :; fi
fi
exit 0
