#!/system/bin/sh
DIR="$(cd "${0%/*}" && pwd)" || exit 1
LOCK=/data/adb/berry_fcm_ksu/service.lock
old="$(cat "$LOCK/pid" 2>/dev/null)"
old_stamp="$(cat "$LOCK/starttime" 2>/dev/null)"
case "$old" in ''|*[!0-9]*) old=0 ;; esac
proc_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $20}'
}
is_guardian() {
    case "$old:$old_stamp" in *[!0-9:]*|:*|*:) return 1;; esac
    [ "$old" -gt 1 ] && [ "$old_stamp" -gt 0 ] && kill -0 "$old" 2>/dev/null || return 1
    [ "$(proc_start_time "$old")" = "$old_stamp" ] || return 1
    cmdline="$(tr "\000" " " < "/proc/$old/cmdline" 2>/dev/null)"
    case "$cmdline" in *"/berry_fcm_ksu/service.sh"*) :;; *) return 1;; esac
    return 0
}
if is_guardian; then
    kill -TERM "$old" 2>/dev/null || :
    n=0
    while is_guardian && [ "$n" -lt 24 ]; do
        sleep 1
        n=$((n + 1))
    done
    if is_guardian; then
        kill -KILL "$old" 2>/dev/null || :
        n=0
        while is_guardian && [ "$n" -lt 3 ]; do sleep 1; n=$((n + 1)); done
    fi
    is_guardian && { echo '旧 BerryFCM 守护进程仍未退出，取消热启动以避免重复实例' >&2; exit 1; }
fi
[ "$(cat /data/adb/berry_fcm_ksu/enabled 2>/dev/null)" = 1 ] || exit 0
[ ! -e "$DIR/disable" ] || exit 0
sh "$DIR/service.sh" </dev/null >/dev/null 2>&1 &
