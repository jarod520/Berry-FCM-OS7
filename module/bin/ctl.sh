#!/system/bin/sh
# Berry-FCM KSU backend. Root-only, no Shizuku, no system partitions touched.
set -u
MODDIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA=/data/adb/berry_fcm_ksu
. "$MODDIR/bin/diagnostic-logs.sh" || exit 11
TARGETS="$DATA/targets.txt"
ENABLED="$DATA/enabled"
GMS=com.google.android.gms
[ "$(id -u)" = 0 ] || { echo 'ERROR: KernelSU Root 未授权 (uid != 0)' >&2; exit 10; }
mkdir -p "$DATA" || exit 11
[ -f "$TARGETS" ] || printf '%s\n' "$GMS" > "$TARGETS"
[ -f "$ENABLED" ] || echo 0 > "$ENABLED"

valid_pkg() { printf '%s\n' "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'; }
target_list() {
    printf '%s\n' "$GMS"
    while IFS= read -r p || [ -n "$p" ]; do
        [ "$p" = "$GMS" ] && continue
        valid_pkg "$p" && printf '%s\n' "$p"
    done < "$TARGETS"
}
installed() {
    cmd package path --user 0 "$1" 2>/dev/null | grep -q '^package:' && return 0
    pm path --user 0 "$1" 2>/dev/null | grep -q '^package:' && return 0
    return 1
}
# 1=stopped, 0=not stopped, -1=no reliable data
stopped() {
    line="$(dumpsys -t 3 package "$1" 2>/dev/null | grep -E '^[[:space:]]*User 0:[[:space:]]+.*installed=' | head -n 1)"
    [ -n "$line" ] || { echo -1; return; }
    case " $line " in
        *' stopped=true '*) echo 1 ;;
        *' stopped=false '*) echo 0 ;;
        *) echo -1 ;;
    esac
}
persistent() {
    # Modern GMS builds may run MCS inside com.google.android.gms, without a
    # separate .persistent process. Do not mislabel that as a missing process.
    pidof "$GMS" >/dev/null 2>&1 && { echo 1; return; }
    echo 0
}
wake_mode() {
    if [ "$(cat "$DATA/wake-mode" 2>/dev/null)" = timed ]; then echo timed; else echo passive; fi
}
proc_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $20}'
}
refresh_guard() {
    pid="$(cat "$DATA/service.lock/wake-pid" 2>/dev/null)"
    stamp="$(cat "$DATA/service.lock/starttime" 2>/dev/null)"
    case "$pid:$stamp" in *[!0-9:]*|:*|*:) pid=0;; esac
    if [ "$pid" -gt 1 ] && [ "$stamp" -gt 0 ] &&
        [ "$(cat "$DATA/service.lock/pid" 2>/dev/null)" = "$pid" ] &&
        [ "$(proc_start_time "$pid")" = "$stamp" ] &&
        tr "\000" " " < "/proc/$pid/cmdline" 2>/dev/null | grep -q "/berry_fcm_ksu/service.sh"; then
        kill -USR1 "$pid" 2>/dev/null && return 0
    fi
    if [ "$(cat "$ENABLED" 2>/dev/null)" = 1 ]; then
        sh "$MODDIR/service.sh" </dev/null >/dev/null 2>&1 &
    fi
}
# Extended checks inspired by fcmfix-coloros17. Pure Android public shell commands;
# vendor-specific ColorOS hooks are NOT present or implied.
gms_uid() {
    # Use cmd/pm package UID APIs only. A failed lookup remains unavailable.
    uid="$(cmd package list packages -U "$GMS" 2>/dev/null | awk -v pkg="$GMS" '$1=="package:"pkg && $2~/^uid:[0-9]+/ {sub(/^uid:/,"",$2); split($2,ids,","); if (ids[1]~/^[0-9]+$/) {print ids[1]; exit}}')"
    if [ -z "$uid" ]; then
        uid="$(pm list packages -U "$GMS" 2>/dev/null | awk -v pkg="$GMS" '$1=="package:"pkg && $2~/^uid:[0-9]+/ {sub(/^uid:/,"",$2); split($2,ids,","); if (ids[1]~/^[0-9]+$/) {print ids[1]; exit}}')"
    fi
    case "$uid" in ''|*[!0-9]*) return 1;; *) printf '%s\n' "$uid" ;; esac
}
dozeraw() { cmd deviceidle whitelist 2>/dev/null; }
doze_state() {
    o="$(dozeraw)" || { echo -1; return; }
    [ -n "$o" ] || { echo -1; return; }
    printf '%s\n' "$o" | grep -qE '^(system|user),com\.google\.android\.gms(,|$)' && echo 1 || echo 0
}
net_list() { cmd netpolicy list restrict-background-whitelist 2>/dev/null; }
net_state() {
    uid="$(gms_uid)"
    case "$uid" in ''|*[!0-9]*) echo -1; return ;; esac
    o="$(net_list)" || { echo -1; return; }
    [ -n "$o" ] || { echo -1; return; }
    printf '%s\n' "$o" | grep -Eq "(^|[^0-9])${uid}([^0-9]|$)" && echo 1 || echo 0
}
net_saver() {
    o="$(cmd netpolicy get restrict-background 2>/dev/null)" || { echo -1; return; }
    case "$o" in *enabled*) echo 1;; *disabled*) echo 0;; *) echo -1;; esac
}
notification_state() {
    o="$(cmd appops get "$GMS" POST_NOTIFICATION 2>/dev/null)" || { echo -1; return; }
    case "$o" in
       *POST_NOTIFICATION*allow*) echo 1;;
       *POST_NOTIFICATION*ignore*|*POST_NOTIFICATION*deny*|*POST_NOTIFICATION*errored*) echo 0;;
       *) echo -1;;
    esac
}
# Return -1 for unknown, 1 if flagged, 0 if explicitly false.
user_flag() {
    l="$(dumpsys -t 3 package "$1" 2>/dev/null | grep -E '^[[:space:]]*User 0:[[:space:]]+.*installed=' | head -n 1)"
    [ -n "$l" ] || { echo -1; return; }
    case " $l " in *" $2=true "*) echo 1;; *" $2=false "*) echo 0;; *) echo -1;; esac
}
policy() {
    kind="${1:-}"; op="${2:-}"
    case "$kind/$op" in
      doze/add)
        [ "$(doze_state)" = 1 ] && { echo 'GMS 已在 Doze 白名单，无需修改'; return 0; }
        cmd deviceidle whitelist "+$GMS" || return 1
        [ "$(doze_state)" = 1 ] || { echo '加入失败：复检未通过' >&2; return 1; }
        : > "$DATA/doze_added"; echo '已加入 GMS Doze 白名单（仅标准 Android Doze）'
        ;;
      doze/undo)
        [ -f "$DATA/doze_added" ] || { echo '不是模块添加的白名单，拒绝撤销' >&2; return 2; }
        cmd deviceidle whitelist "-$GMS" || return 1
        [ "$(doze_state)" = 0 ] || { echo '撤销失败：复检未通过' >&2; return 1; }
        rm -f "$DATA/doze_added"; echo '已撤销模块添加的 Doze 白名单'
        ;;
      net/add)
        uid="$(gms_uid)"
        case "$uid" in ''|*[!0-9]*) echo '无法取得 GMS UID' >&2; return 2;; esac
        [ "$(net_state)" = 1 ] && { echo 'GMS 已被允许使用后台计量网络，无需修改'; return 0; }
        cmd netpolicy add restrict-background-whitelist "$uid" || return 1
        [ "$(net_state)" = 1 ] || { echo '加入失败：复检未通过' >&2; return 1; }
        printf '%s\n' "$uid" > "$DATA/net_added_uid"
        echo "已放行 GMS UID $uid（仅 Android 数据节省模式）"
        ;;
      net/undo)
        uid="$(gms_uid)"; saved="$(cat "$DATA/net_added_uid" 2>/dev/null)"
        [ -n "$uid" ] && [ "$uid" = "$saved" ] || { echo 'UID 不一致或非本模块添加，拒绝撤销' >&2; return 2; }
        cmd netpolicy remove restrict-background-whitelist "$uid" || return 1
        [ "$(net_state)" = 0 ] || { echo '撤销失败：复检未通过' >&2; return 1; }
        rm -f "$DATA/net_added_uid"; echo '已撤销模块添加的后台数据放行'
        ;;
      *) echo 'policy doze|net add|undo' >&2; return 2;;
    esac
}
check() {
    g=0; installed "$GMS" && g=1
    s=-1; [ "$g" = 1 ] && s="$(stopped "$GMS")"
    probe=0; [ "$s" != -1 ] && probe=1
    proc="$(persistent)"
    dz="$(doze_state)"; ns="$(net_saver)"; na="$(net_state)"; nt="$(notification_state)"
    dz_owned=0; [ -f "$DATA/doze_added" ] && dz_owned=1
    na_owned=0; [ -f "$DATA/net_added_uid" ] && [ "$(cat "$DATA/net_added_uid")" = "$(gms_uid)" ] && na_owned=1
    recv="$(dumpsys -t 2 activity broadcasts 2>/dev/null | grep -c 'ReceiverList{.*com\.google\.android\.gms/' || true)"
    case "$recv" in ''|*[!0-9]*) recv=0 ;; esac
    items=''; comma=''
    for pkg in $(target_list); do
        [ "$pkg" = "$GMS" ] && continue
        ins=0; st=-1
        suspended=-1; hidden=-1
        if installed "$pkg"; then
            ins=1; st="$(stopped "$pkg")"
            suspended="$(user_flag "$pkg" suspended)"
            hidden="$(user_flag "$pkg" hidden)"
        fi
        items="${items}${comma}{\"pkg\":\"${pkg}\",\"installed\":${ins},\"stopped\":${st},\"suspended\":${suspended},\"hidden\":${hidden}}"
        comma=','
    done
    auto="$(cat "$ENABLED" 2>/dev/null)"; [ "$auto" = 1 ] || auto=0
    native="$(sh "$MODDIR/bin/fcm-monitor.sh" status)"
    monitor_rc=$?
    if [ "$monitor_rc" -eq 13 ]; then
        native="$(sh "$MODDIR/bin/fcm-monitor.sh" snapshot)"
    fi
    if [ -z "$native" ] || { [ "$monitor_rc" -ne 0 ] && [ "$monitor_rc" -ne 13 ]; }; then
        native='{"fcm_state":"unknown","fcm_source":"unavailable","fcm_native_reason":"backend_failed"}'
    fi
    case "$native" in
      *'{"fcm_state":"connected",'*) mc=1;;
      *'{"fcm_state":"disconnected",'*|*'{"fcm_state":"connecting",'*) mc=0;;
      *) mc=-1;;
    esac
    wake_status="$(cat "$DATA/wake-status" 2>/dev/null)"
    case "$wake_status" in timed|fallback|passive|cgroup_failed) :;; *) wake_status=passive;; esac
    wake_minutes="$(cat "$DATA/wake-minutes" 2>/dev/null)"
    case "$wake_minutes" in [1-9]|10) :;; *) wake_minutes=3;; esac
    printf '{"probe":%s,"gms_installed":%s,"gms_stopped":%s,"gcm_persistent":%s,"mcs":%s,"receivers":%s,"guard":%s,"doze":%s,"doze_owned":%s,"data_saver":%s,"net_allowed":%s,"net_owned":%s,"notification":%s,"fcm_check_exit":%s,"wake_mode":"%s","wake_status":"%s","wake_minutes":%s,"targets":[%s],%s\n' "$probe" "$g" "$s" "$proc" "$mc" "$recv" "$auto" "$dz" "$dz_owned" "$ns" "$na" "$na_owned" "$nt" "$monitor_rc" "$(wake_mode)" "$wake_status" "$wake_minutes" "$items" "${native#\{}"
}
heartbeat() {
    out="$(am broadcast --user 0 -a com.google.android.intent.action.MCS_HEARTBEAT -p "$GMS" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'Broadcast completed: result=0' &&
        ! printf '%s\n' "$out" | grep -qiE 'Permission Denial|SecurityException|not allowed'; then
        echo '已请求 GMS 心跳'
    else
        echo "GMS 心跳请求未确认：$out"
        return 1
    fi
}
fix() {
    changed=0; failed=0
    for pkg in $(target_list); do
        installed "$pkg" || { echo "$pkg 未安装，跳过"; continue; }
        # Package-state diagnostics must not decide whether to issue unstop.
        # The package command itself is the operation result; a failed diagnostic
        # must never prevent the independent MCS heartbeat below.
        if cmd package unstop --user 0 "$pkg" >/dev/null 2>&1; then
            echo "$pkg 已提交 unstop 命令"
            changed=$((changed + 1))
        else
            echo "$pkg unstop 命令失败 (可能权限/系统限制)"
            failed=$((failed + 1))
        fi
    done
    if installed "$GMS"; then
        heartbeat || echo '部分心跳未确认，并不代表推送必然失败'
    fi
    echo "本轮 unstop 命令成功: $changed, 失败: $failed"
    [ "$failed" = 0 ]
}
watch() {
    # 90-second window, every 15 seconds including both endpoints.
    n=0
    while [ "$n" -lt 7 ]; do
        echo "巡检 $((n + 1))/7: $(date '+%H:%M:%S')"
        HEARTBEAT_MODE=auto fix
        n=$((n + 1))
        [ "$n" -lt 7 ] && sleep 15
    done
}
# Read-only socket reachability. A success only proves the device's CURRENT
# system route can connect; VPN, TUN and upstream transparent proxies may apply.
network_test() {
    echo '== FCM TCP 连通性（只读） =='
    echo '注意：测试进程为 Root UID 0，与 GMS 的 VPN/路由规则可能不同；TCP 成功不能代表 GMS 已直连。'
    echo '验证无代理：关闭手机 VPN，并确认 Wi-Fi 路由器未代理后再测；移动网络另测。'
    if ! /system/bin/toybox nc --help 2>&1 | grep -q -- '-z'; then
        echo '系统 toybox nc 不支持 -z 扫描，无法进行 TCP 测试。'
        return 2
    fi
    failures=0
    for port in 5228 5229 5230 443; do
        if /system/bin/toybox nc -4 -z -w 3 mtalk.google.com "$port" </dev/null >/dev/null 2>&1; then
            echo "mtalk.google.com:$port  TCP 可建立"
        else
            echo "mtalk.google.com:$port  未能建立（可能 DNS、路由、拦截或超时）"
            failures=$((failures+1))
        fi
    done
    if /system/bin/toybox nc -4 -z -w 3 alt1-mtalk.google.com 5228 </dev/null >/dev/null 2>&1; then
        echo 'alt1-mtalk.google.com:5228  TCP 可建立'
    else
        echo 'alt1-mtalk.google.com:5228  未能建立（可能 DNS、路由、拦截或超时）'
        failures=$((failures+1))
    fi
    echo '仅测试 TCP 握手；并不等于 GMS 已认证、FCM 已注册或消息可送达。'
    echo "未建立项: $failures/5（未建立不等于永久不可达）"
}
link() {
    case "${1:-}" in
      autostart)
        am start -n com.vivo.permissionmanager/.activity.BgStartUpManagerActivity >/dev/null 2>&1 || \
        am start -a com.iqoo.secure.BGSTARTUPMANAGER
        ;;
      gmsnotif)
        am start -a android.settings.APP_NOTIFICATION_SETTINGS --es android.provider.extra.APP_PACKAGE "$GMS"
        ;;
      gcmdiag)
        # Google Play services' internal diagnostics Activity. Availability depends on GMS build.
        am start -n com.google.android.gms/.gcm.GcmDiagnostics
        ;;
      appdetails)
        p="${2:-}"; valid_pkg "$p" || { echo '应用包名不合法' >&2; return 2; }
        am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d "package:$p"
        ;;
      *) echo 'invalid link'; return 1 ;;
    esac
}
start_webui_job() (
    if ! flock -n 8; then
        echo running
        exit 0
    fi
    rm -f "$DATA/$1.result" || exit 1
    /system/bin/toybox setsid sh "$MODDIR/bin/ctl.sh" "$1-worker" </dev/null >/dev/null 2>&1 &
    echo running
) 8>"$DATA/$1.lock"

webui_job_worker() {
    flock -n 8 || return 1
    case "$1" in
        reconnect) result=$(/system/bin/toybox timeout -k 3 95 sh "$MODDIR/bin/fcm-monitor.sh" reconnect 8>&- 2>&1);;
        netdiag) result=$(/system/bin/toybox timeout -k 3 35 sh "$MODDIR/bin/ctl.sh" netdiag 8>&- 2>&1);;
    esac
    job_rc=$?
    case "$job_rc" in
        124|137|143) result="操作超时，请稍后重试。
$result";;
    esac
    if [ -z "$result" ]; then result="操作已结束，返回码 $job_rc。"; fi
    printf 'done\n%s\n' "$result" > "$DATA/$1.tmp" &&
        mv -f "$DATA/$1.tmp" "$DATA/$1.result"
}

webui_job_status() (
    if ! flock -n 8; then
        echo running
    elif [ -s "$DATA/$1.result" ]; then
        cat "$DATA/$1.result"
    else
        echo idle
    fi
) 8>"$DATA/$1.lock"

case "${1:-}" in
    check) check ;;
    netdiag) network_test ;;
    fcm-monitor) sh "$MODDIR/bin/fcm-monitor.sh" monitor ;;
    reconnect) sh "$MODDIR/bin/fcm-monitor.sh" reconnect ;;
    reconnect-start|netdiag-start) start_webui_job "${1%-start}" ;;
    reconnect-status|netdiag-status) webui_job_status "${1%-status}" ;;
    reconnect-worker|netdiag-worker) webui_job_worker "${1%-worker}" ;;
    fix) fix ;;
    watch) watch ;;
    targets)
        case "${2:-}" in
            list) target_list ;;
            add)
                p="${3:-}"; valid_pkg "$p" || { echo '包名不合法'; exit 2; }
                if ! target_list | grep -qxF "$p"; then printf '%s\n' "$p" >> "$TARGETS"; fi
                target_list ;;
            remove)
                p="${3:-}"; valid_pkg "$p" && [ "$p" != "$GMS" ] || { echo '不可移除 GMS / 包名错误'; exit 2; }
                tmp="$TARGETS.tmp.$$"; grep -vxF "$p" "$TARGETS" > "$tmp" || true
                mv -f "$tmp" "$TARGETS"; target_list ;;
            reset) printf '%s\n' "$GMS" > "$TARGETS"; target_list ;;
            *) echo 'targets list|add|remove|reset' >&2; exit 2 ;;
        esac
        ;;
    wake-minutes)
        case "${2:-}" in
            [1-9]|10)
                printf '%s\n' "$2" > "$DATA/wake-minutes.$$" &&
                    mv -f "$DATA/wake-minutes.$$" "$DATA/wake-minutes" || exit 1
                refresh_guard ;;
            *) echo 'wake-minutes 1–10' >&2; exit 2 ;;
        esac
        ;;
    wake-mode)
        case "${2:-}" in
            passive|timed)
                printf '%s\n' "$2" > "$DATA/wake-mode.$$" &&
                    mv -f "$DATA/wake-mode.$$" "$DATA/wake-mode" || exit 1
                refresh_guard ;;
            *) echo 'wake-mode passive|timed' >&2; exit 2 ;;
        esac
        ;;
    guard)
        case "${2:-}" in
            on)
                echo 1 > "$ENABLED"
                # Service may be absent until next boot; launch after a user enables guard.
                refresh_guard
                echo '自动守护已开启'
                ;;
            off) echo 0 > "$ENABLED"; refresh_guard; echo '自动守护已关闭' ;;
            status) cat "$ENABLED" ;;
            *) echo 'guard on|off|status' >&2; exit 2 ;;
        esac
        ;;
    policy) policy "${2:-}" "${3:-}" ;;
    links) link "${2:-}" "${3:-}" ;;
    log)
        echo '== 定时器记录（UTC） =='
        if [ "${2:-}" = all ]; then read_diagnostic_log "$DATA/wake-timer.log"
        else read_diagnostic_log "$DATA/wake-timer.log" | tail -n 45; fi
        echo '== GMS 巡检记录（本地时间） =='
        if [ "${2:-}" = all ]; then read_diagnostic_log "$DATA/guard.log"
        else read_diagnostic_log "$DATA/guard.log" | tail -n 100; fi
        ;;
    *) echo 'check|netdiag|fcm-monitor|reconnect|fix|watch|targets|guard|wake-mode|wake-minutes|policy|links|log' >&2; exit 2 ;;
esac
