#!/system/bin/sh
DIR="$(cd "${0%/*}" && pwd)" || exit 1
[ "$(cat /data/adb/berry_fcm_ksu/enabled 2>/dev/null)" = 1 ] || exit 0
LOCK=/data/adb/berry_fcm_ksu/service.lock
old="$(cat "$LOCK/pid" 2>/dev/null)"
old_stamp="$(cat "$LOCK/starttime" 2>/dev/null)"
case "$old" in ''|*[!0-9]*) old=0 ;; esac
proc_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $20}'
}
is_guardian() {
    [ "$old" -gt 1 ] && [ -n "$old_stamp" ] &&
        kill -0 "$old" 2>/dev/null &&
        [ "$(proc_start_time "$old")" = "$old_stamp" ] &&
        [ -r "/proc/$old/cmdline" ] &&
        tr '\000' ' ' < "/proc/$old/cmdline" | grep -q 'service.sh'
}
if is_guardian; then
    kill -TERM "$old" 2>/dev/null || :
    n=0
    while is_guardian && [ "$n" -lt 6 ]; do
        sleep 1
        n=$((n + 1))
    done
    if is_guardian; then kill -KILL "$old" 2>/dev/null || :; fi
fi
sh "$DIR/service.sh" </dev/null >/dev/null 2>&1 &
