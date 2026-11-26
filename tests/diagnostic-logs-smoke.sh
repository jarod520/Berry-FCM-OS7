#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cmp "$ROOT/module/bin/diagnostic-logs.sh" "$ROOT/app/src/main/assets/diagnostic-logs.sh"
. "$ROOT/module/bin/diagnostic-logs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
log="$TMP/guard.log"
first_day=$((20000 * 86400))
rollover=$((first_day + 86400))
printf '%s\n' '升级前日志' > "$log"
rotate_diagnostic_log "$log" "$first_day"
[ -f "$log" ]
exec 3>> "$log"
rotate_diagnostic_log "$log" "$rollover"
printf '%s\n' '跨日后旧描述符仍能写入' >&3
exec 3>&-
printf '%s\n' '新一天日志' >> "$log"
[ "$(read_diagnostic_log "$log")" = '升级前日志
跨日后旧描述符仍能写入
新一天日志' ]
TZ=UTC touch -t 202410010000 "$log.$rollover"
rotate_diagnostic_log "$log" "$((rollover + 172799))"
[ -f "$log.$rollover" ]
rotate_diagnostic_log "$log" "$((rollover + 172800))"
[ ! -e "$log.$rollover" ]
printf '%s\n' '过期归档仍有最近写入' > "$log.$((rollover - 1))"
TZ=UTC touch -t 202411010000 "$log.$((rollover - 1))"
rotate_diagnostic_log "$log" "$((rollover + 259200))"
[ -f "$log.$((rollover - 1))" ]
printf '%s\n' 'PASS: 双端日志跨日轮转、旧写入描述符与 48 小时归档边界'
