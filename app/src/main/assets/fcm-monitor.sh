#!/system/bin/sh
# BerryFCM APK: kernel GMS-UID socket evidence drives state and recovery; dumps are never runtime inputs.
# Only observes GMS-owned TCP sockets and requests targeted recovery broadcasts; it never
# changes DNS, VPN, proxy, routing, or kills/restarts Google Play services.
set -u

GMS=com.google.android.gms
DATA="${BERRY_FCM_DATA:-/data/adb/berry_fcm_apk}"
STATE="$DATA/mcs-monitor.state"
EVENTS="$DATA/mcs-monitor-events.log"
NATIVE_EVENTS="$DATA/mcs-native-events.log"
EVIDENCE="$DATA/mcs-evidence"
DNS_IPS="$DATA/mtalk-dns-ips.txt"
LEARNED_IPS="$DATA/mtalk-learned-ips.txt"
DNS_TIME="$DATA/mtalk-dns-time"
SS_BIN="${BERRY_SS_BIN:-ss}"
CMD_BIN="${BERRY_CMD_BIN:-cmd}"
PM_BIN="${BERRY_PM_BIN:-pm}"
AM_BIN="${BERRY_AM_BIN:-am}"
UPTIME_FILE="${BERRY_UPTIME_FILE:-/proc/uptime}"
BOOT_ID_FILE="${BERRY_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"

if [ "${BERRY_FCM_TEST_MODE:-0}" != 1 ] && [ "${BERRY_FCM_ADB_SHELL:-0}" != 1 ]; then
    [ "$(id -u)" = 0 ] || { echo 'ERROR: 需要 Root / ADB shell 权限' >&2; exit 10; }
fi
mkdir -p "$DATA" || exit 11

is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
num() { is_uint "${1:-}" && printf '%s\n' "$1" || printf '0\n'; }
now_epoch() { date +%s 2>/dev/null | awk '/^[0-9]+$/ {print; found=1} END {if (!found) print 0}'; }
monotime() { awk '{printf "%d\n", $1}' "$UPTIME_FILE" 2>/dev/null | head -n 1; }
boot_id() { cat "$BOOT_ID_FILE" 2>/dev/null; }

# Persisted fields use a fixed pipe-delimited schema. Never source the file.
load_state() {
    b="$(boot_id)"
    state=never_seen; conn_key=; conn_since=0; conn_since_mono=0; last_seen=0
    missing_since=0; missing_epoch=0; last_try_mono=0; last_try_epoch=0
    attempts=0; last_result=none; last_restore=0; outages=0
    transport=; remote=; sample_epoch=0; last_try_reason=none
    reconnects=0; last_down=0
    down_observed=0; retry_streak=0; outage_hint_mono=0
    prev_b=
    if [ -f "$STATE" ]; then
        IFS='|' read -r prev_b state conn_key conn_since conn_since_mono last_seen missing_since missing_epoch last_try_mono last_try_epoch attempts last_result last_restore outages transport remote sample_epoch last_try_reason reconnects last_down down_observed retry_streak outage_hint_mono < "$STATE" || :
    fi
    conn_since="$(num "$conn_since")"; conn_since_mono="$(num "$conn_since_mono")"; last_seen="$(num "$last_seen")"
    missing_since="$(num "$missing_since")"; missing_epoch="$(num "$missing_epoch")"
    last_try_mono="$(num "$last_try_mono")"; last_try_epoch="$(num "$last_try_epoch")"
    attempts="$(num "$attempts")"; last_restore="$(num "$last_restore")"
    outages="$(num "$outages")"; sample_epoch="$(num "$sample_epoch")"
    reconnects="$(num "$reconnects")"; last_down="$(num "$last_down")"
    down_observed="$(num "${down_observed:-0}")"; retry_streak="$(num "${retry_streak:-0}")"
    outage_hint_mono="$(num "${outage_hint_mono:-0}")"
    case "$state" in connected|connecting|disconnected|unknown|never_seen) : ;; *) state=unknown;; esac
    case "$last_result" in none|requested|failed|restored) : ;; *) last_result=none;; esac
    case "$last_try_reason" in none|auto|manual|rescue) : ;; *) last_try_reason=none;; esac
    if [ -n "$prev_b" ] && [ "$prev_b" != "$b" ]; then
        state=never_seen; conn_key=; conn_since=0; conn_since_mono=0; missing_since=0; missing_epoch=0
        last_try_mono=0; transport=; remote=; sample_epoch=0; down_observed=0; retry_streak=0; outage_hint_mono=0
        : > "$LEARNED_IPS"
        record_event reboot '设备重启：清除上一启动周期的连接计时，保留历史事件'
    fi
}

save_state() {
    tmp="$STATE.$"
    if ! printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$b" "$state" "$conn_key" "$conn_since" "$conn_since_mono" "$last_seen" "$missing_since" "$missing_epoch" \
      "$last_try_mono" "$last_try_epoch" "$attempts" "$last_result" "$last_restore" "$outages" \
      "$transport" "$remote" "$sample_epoch" "$last_try_reason" "$reconnects" "$last_down" "$down_observed" "$retry_streak" "$outage_hint_mono" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if ! mv -f "$tmp" "$STATE"; then
        rm -f "$tmp"
        return 1
    fi
}

record_event() {
    e="${1:-event}"; msg="${2:-}"
    msg="$(printf '%s' "$msg" | tr '\r\n|' '   ' | cut -c1-220)"
    printf '%s|%s|%s\n' "$(now_epoch)" "$e" "$msg" >> "$EVENTS"
    lines="$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ')"; lines="$(num "$lines")"
    if [ "$lines" -gt 120 ]; then tail -n 120 "$EVENTS" > "$EVENTS.tmp" && mv -f "$EVENTS.tmp" "$EVENTS"; fi
}

# Resolve Google's documented mtalk hostnames. These addresses are candidates
# only for GMS UID-owned :443 sockets; arbitrary GMS HTTPS sockets never count.
resolve_host() {
    host="$1"
    if command -v nslookup >/dev/null 2>&1; then
        nslookup "$host" 2>/dev/null | awk '
          /^Name:/ {answer=1; next}
          answer && /Address/ {ip=$NF; if (ip ~ /^[0-9A-Fa-f:.]+$/) print tolower(ip)}'
    elif command -v getent >/dev/null 2>&1; then
        getent ahosts "$host" 2>/dev/null | awk '$1 ~ /^[0-9A-Fa-f:.]+$/ {print tolower($1)}'
    else
        ping -c 1 -W 2 "$host" 2>&1 | sed -n 's/.*(\([0-9A-Fa-f:.]*\)).*/\1/p' | tr 'A-F' 'a-f'
    fi
}

resolve_mtalk() {
    now="$(now_epoch)"; old="$(cat "$DNS_TIME" 2>/dev/null)"; old="$(num "$old")"
    [ -s "$DNS_IPS" ] && [ "$old" -gt 0 ] && [ "$now" -ge "$old" ] && [ $((now-old)) -lt 600 ] && return 0
    tmp="$DNS_IPS.$$"; : > "$tmp"
    for host in mtalk.google.com mtalk4.google.com mtalk-staging.google.com mtalk-dev.google.com \
      alt1-mtalk.google.com alt2-mtalk.google.com alt3-mtalk.google.com alt4-mtalk.google.com \
      alt5-mtalk.google.com alt6-mtalk.google.com alt7-mtalk.google.com alt8-mtalk.google.com; do
        resolve_host "$host" >> "$tmp" 2>/dev/null || :
    done
    if [ -s "$tmp" ]; then sort -u "$tmp" > "$DNS_IPS.new" && mv -f "$DNS_IPS.new" "$DNS_IPS"; fi
    rm -f "$tmp"
    echo "$now" > "$DNS_TIME"
}

normalize_ip() {
    printf '%s' "$1" | tr 'A-F' 'a-f' | sed 's/^\[//;s/\]$//;s/^::ffff://' 
}

gms_uid() {
    uid="$("$CMD_BIN" package list packages -U "$GMS" 2>/dev/null | awk -v p="$GMS" '$1=="package:"p && $2~/^uid:[0-9]+/ {sub(/^uid:/,"",$2); split($2,a,","); if(a[1]~/^[0-9]+$/){print a[1];exit}}')"
    [ -n "$uid" ] || uid="$("$PM_BIN" list packages -U "$GMS" 2>/dev/null | awk -v p="$GMS" '$1=="package:"p && $2~/^uid:[0-9]+/ {sub(/^uid:/,"",$2); split($2,a,","); if(a[1]~/^[0-9]+$/){print a[1];exit}}')"
    is_uint "$uid" || return 1
    printf '%s\n' "$uid"
}

scan_sockets() {
    uid="$(gms_uid 2>/dev/null)" || { printf 'unknown||||gms_uid_unavailable\n'; return; }
    command -v "$SS_BIN" >/dev/null 2>&1 || { printf 'unknown||||ss_unavailable\n'; return; }
    raw="$("$SS_BIN" -tnpe 2>/dev/null)" || { printf 'unknown||||ss_failed\n'; return; }

    # Some ADB shells receive redacted ss output with no UID ownership.
    # Never classify that as absence of GMS/FCM: ownership is unobservable.
    if ! printf '%s\n' "$raw" | grep -Eq 'uid:[0-9]+'; then
        printf 'unknown||||ss_uid_metadata_unavailable\n'
        return
    fi

    # Learn peer IPs observed on the dedicated MCS ports during this boot.
    printf '%s\n' "$raw" | awk -v u="$uid" '
      ($1=="ESTAB" || $1=="ESTABLISHED") {
        if (!match($0,/uid:[0-9]+/)) next
        owner=substr($0,RSTART+4,RLENGTH-4)+0; if(owner!=u+0) next
        peer=$5; port=peer; sub(/^.*:/,"",port)
        if(port==5228 || port==5229 || port==5230){ip=peer;sub(/:[0-9]+$/,"",ip);gsub(/^\[|\]$/,"",ip);sub(/^::ffff:/,"",ip);print tolower(ip)}
      }' >> "$LEARNED_IPS"
    [ -s "$LEARNED_IPS" ] && sort -u "$LEARNED_IPS" > "$LEARNED_IPS.tmp" && mv -f "$LEARNED_IPS.tmp" "$LEARNED_IPS"
    ips="$(cat "$DNS_IPS" "$LEARNED_IPS" 2>/dev/null | awk 'NF && !seen[$0]++ {printf "%s%s",sep,$0;sep="|"}')"
    ip_count="$(printf '%s' "$ips" | awk -F'|' '{print NF}')"
    [ -n "$ips" ] || ip_count=0
    printf '%s\n' "$raw" | awk -v u="$uid" -v ips="|$ips|" -v ip_count="$ip_count" '
      function normip(v){sub(/:[0-9]+$/, "", v);gsub(/^\[|\]$/, "", v);sub(/^::ffff:/, "", v);return tolower(v)}
      function known(v){return index(ips,"|" normip(v) "|")>0}
      ($1=="ESTAB" || $1=="ESTABLISHED" || $1=="SYN-SENT" || $1=="SYN_SENT") {
        if (!match($0,/uid:[0-9]+/)) next
        owner=substr($0,RSTART+4,RLENGTH-4)+0; if(owner!=u+0) next
        peer=$5; port=peer; sub(/^.*:/,"",port); ip=normip(peer); local=$4
        inode=""; if(match($0,/ino:[0-9]+/)) inode=substr($0,RSTART+4,RLENGTH-4)
        key=local ">" peer "#" inode
        established=($1=="ESTAB" || $1=="ESTABLISHED")
        if(established && (port==5228 || port==5229 || port==5230)){
          if(rank<3){rank=3;kind="connected";transport="tcp" port;remote=ip ":" port;bestkey=key}
        } else if(established && port==443 && known(peer)){
          if(rank<2){rank=2;kind="connected";transport="tcp443";remote=ip ":443";bestkey=key}
        } else if(!established && ((port==5228 || port==5229 || port==5230) || (port==443 && known(peer)))){
          if(rank<1){rank=1;kind="connecting";transport="tcp" port;remote=ip ":" port;bestkey=key}
        } else if(established && port==443 && ip_count==0){untrusted=1}
      }
      END {
        if(rank>0) printf "%s|%s|%s|%s|\n",kind,transport,remote,bestkey
        else if(untrusted) print "unknown||||unverified_443_no_mtalk_dns"
        else print "absent||||no_fcm_socket_observed"
      }'
}

# Current state and recovery decisions come exclusively from GMS-UID kernel Socket evidence.
auto_enabled() {
    case "${BERRY_FCM_AUTO:-}" in 0) return 1;; 1) return 0;; esac
    [ "$(cat "$DATA/enabled" 2>/dev/null)" = 1 ]
}

retry_interval() {
    # Fresh outages retain only a short global anti-flap floor; ongoing outages back off.
    case "$retry_streak" in 0) echo 30;; 1) echo 60;; 2) echo 120;; *) echo 180;; esac
}

request_reconnect() {
    reason="$1"; nowm="$(num "$(monotime)")"; nowe="$(num "$(now_epoch)")"
    case "$state" in connecting|disconnected) :;; *) decision=not_disconnected; return 0;; esac
    interval="$(retry_interval)"
    [ "$reason" = manual ] && interval=60
    if [ "$last_try_mono" -gt 0 ] && [ "$nowm" -ge "$last_try_mono" ] && [ $((nowm-last_try_mono)) -lt "$interval" ]; then
        decision=cooldown
        if [ "$reason" = manual ]; then
            record_event reconnect_skipped "手动恢复未发送：距上次请求不足60秒，剩余 $((interval-nowm+last_try_mono)) 秒"
        fi
        return 0
    fi
    last_try_mono="$nowm"; last_try_epoch="$nowe"; attempts=$((attempts+1))
    retry_streak=$((retry_streak+1)); last_try_reason="$reason"; last_result=failed
    if ! save_state; then
        decision=state_save_failed
        last_result=failed
        record_event reconnect_aborted "恢复请求前无法持久化退避状态；为避免重复广播，本轮不发送"
        return 0
    fi
    # OriginOS 7 real-device evidence: GCM_RECONNECT is NOT exported.
    # UID 2000 can deliver MCS_HEARTBEAT and ACTION_HEARTBEAT_NOW to GMS.
    # Delivery is not proof of reconnection; only observe() can report restored.
    sender_uid="$(id -u 2>/dev/null || echo unknown)"
    case "$sender_uid" in
      0) action=com.google.android.intent.action.GCM_RECONNECT;;
      2000)
        if [ $((retry_streak % 2)) -eq 1 ]; then
            action=com.google.android.intent.action.MCS_HEARTBEAT
        else
            action=com.google.android.gms.gcm.ACTION_HEARTBEAT_NOW
        fi;;
      *) decision=request_failed; record_event reconnect_failed "执行身份 UID=$sender_uid 不是已验证的 Root/ADB Shell"; save_state; return 0;;
    esac
    reply="$("$AM_BIN" broadcast --user 0 -a "$action" -p "$GMS" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ] && printf '%s\n' "$reply" | grep -q 'Broadcast completed:' &&
        ! printf '%s\n' "$reply" | grep -qiE 'Permission Denial|SecurityException|not allowed|Error:|result=-[0-9]'; then
        last_result=requested; decision=requested
        completion="$(printf '%s\n' "$reply" | grep 'Broadcast completed:' | tail -n 1)"
        record_event reconnect_requested "$reason UID=$sender_uid ${action##*.} exit=$rc $completion；命令返回不代表投递或恢复（第 $attempts 次）"
    else
        last_result=failed; decision=request_failed
        record_event reconnect_failed "$reason UID=$sender_uid ${action##*.} exit=$rc：$reply"
    fi
    if ! save_state; then
        decision=state_save_failed
        record_event reconnect_state_commit_failed "广播已提交但恢复结果状态写入失败；保留请求前已提交的退避锚点"
    fi
}

observe() {
    load_state
    nowm="$(num "$(monotime)")"; nowe="$(num "$(now_epoch)")"
    [ "$nowm" -gt 0 ] && [ "$nowe" -gt 0 ] || return 12
    # Discard pre-migration states whose authority was the legacy native parser.
    legacy_source=
    if [ -f "$EVIDENCE" ]; then IFS='|' read -r legacy_source _ < "$EVIDENCE" || :; fi
    case "$legacy_source" in
      gms_socket|gms_socket_absence|gms_socket_absence_pending) :;;
      *)
        if [ "$state" != unknown ] || [ "$outage_hint_mono" -gt 0 ] || [ "$down_observed" -gt 0 ]; then
            record_event legacy_dump_state_discarded "旧版状态来源不是内核 MCS Socket；清除旧连接/断联计时，重新建立内核证据"
        fi
        state=unknown; conn_key=; conn_since=0; conn_since_mono=0
        missing_since=0; missing_epoch=0; down_observed=0; outage_hint_mono=0
        last_try_mono=0; retry_streak=0
        ;;
    esac
    previous_down_state="$state"; previous_missing_epoch="$missing_epoch"
    previous_down_observed="$(num "${outage_hint_mono:-0}")"
    [ "$previous_down_observed" -gt 0 ] || previous_down_observed="$(num "${down_observed:-0}")"
    if [ "$previous_down_observed" -gt "$nowm" ] ||
       { [ "$sample_epoch" -gt 0 ] && [ "$nowe" -gt "$sample_epoch" ] && [ $((nowe-sample_epoch)) -gt 90 ]; }; then
        previous_down_observed=0
        if [ "$sample_epoch" -gt 0 ] && [ "$nowe" -gt "$sample_epoch" ] && [ $((nowe-sample_epoch)) -gt 90 ]; then
            record_event sample_gap "距离上次有效内核 Socket 采样 $((nowe-sample_epoch)) 秒；重置连续性计时并重新采样"
            state=unknown; missing_since=0; missing_epoch=0; conn_since=0; down_observed=0
        fi
    fi
    outage_hint_mono="$previous_down_observed"
    decision=not_evaluated
    socket="$(scan_sockets)"
    IFS='|' read -r socket_state socket_transport socket_remote socket_key socket_reason <<EOF_SOCKET
$socket
EOF_SOCKET
    observed=unknown; source=unavailable; new_transport=; new_remote=
    duration=-1; close_code=; native_reason=not_used; parse_detail="$socket_reason"
    tcp_hint="$socket_state"
    [ "$tcp_hint" = connected ] && tcp_hint=established
    socket_now="$nowm"
    case "$socket_state" in
      connected)
        observed=connected; source=gms_socket
        new_transport="$socket_transport"; new_remote="$socket_remote"
        previous_down_observed=0; outage_hint_mono=0
        [ "$previous_down_state" = connected ] ||
            record_event socket_connected "内核 Socket 证据观察到 GMS UID 的 MCS TCP 已建立；只证明传输层连接"
        ;;
      connecting)
        observed=connecting; source=gms_socket
        new_transport="$socket_transport"; new_remote="$socket_remote"
        if [ "$previous_down_state" != connecting ] || [ "$outage_hint_mono" -le 0 ] || [ "$socket_now" -lt "$outage_hint_mono" ]; then
            down_observed="$socket_now"; outage_hint_mono="$socket_now"
            record_event socket_connecting "内核 Socket 证据观察到 GMS MCS TCP 正在建立连接"
        fi
        previous_down_observed="$outage_hint_mono"
        ;;
      absent)
        if [ "$(id -u 2>/dev/null)" = 0 ]; then
            source=gms_socket_absence_pending
            if [ "$outage_hint_mono" -le 0 ] || [ "$socket_now" -lt "$outage_hint_mono" ] ||
               [ $((socket_now-outage_hint_mono)) -gt 900 ]; then
                outage_hint_mono="$socket_now"
                record_event tcp_absence_started "Root 已读取 GMS UID Socket 表但未发现 MCS TCP；开始连续缺失计时"
            fi
            socket_down_age=$((socket_now-outage_hint_mono))
            previous_down_observed="$outage_hint_mono"; tcp_hint=absent
            if [ "$socket_down_age" -ge 60 ] && [ "$socket_down_age" -le 900 ]; then
                observed=disconnected; source=gms_socket_absence
                [ "$previous_down_state" = disconnected ] ||
                    record_event tcp_absence_confirmed "GMS MCS TCP 连续缺失 $socket_down_age 秒，达到断联证据阈值"
            fi
        else
            tcp_hint=unknown
            source=unavailable
            record_event socket_absence_untrusted "当前权限不能证明 GMS Socket 表完整；不把缺失样本判为断联"
        fi
        ;;
      *)
        observed=unknown; source=unavailable; tcp_hint=unknown
        [ "$previous_down_state" = unknown ] ||
            record_event socket_evidence_unavailable "内核 Socket 证据不可用：${socket_reason:-no_detail}；巡检继续且不触发伪断联"
        ;;
    esac
    case "$observed" in
      connected)
        case "$previous_down_state" in
          connecting|disconnected)
            last_restore="$nowe"
            if [ "$last_result" = requested ] && [ "$last_try_epoch" -ge "$previous_missing_epoch" ] && [ "$last_try_epoch" -gt 0 ]; then last_result=restored; fi
            record_event connection_restored "内核 Socket 证据再次观察到 GMS MCS TCP 建立"
            ;;
          unknown)
            [ "$previous_down_observed" -le 0 ] ||
                record_event connection_observed_after_unknown "未知样本后重新观察到 GMS MCS TCP；不推断未知期间恢复时刻"
            ;;
        esac
        current_key="$socket_remote"
        if [ "$state" != connected ] || [ "$conn_key" != "$current_key" ] ||
           [ "$conn_since_mono" -le 0 ] || [ "$nowm" -lt "$conn_since_mono" ] ||
           [ "$sample_epoch" -le 0 ] || [ "$nowe" -lt "$sample_epoch" ] ||
           [ $((nowe-sample_epoch)) -gt 45 ]; then conn_since_mono="$nowm"; fi
        conn_key="$current_key"; state=connected; last_seen="$nowe"; missing_since=0; missing_epoch=0
        down_observed=0; outage_hint_mono=0; last_try_mono=0; retry_streak=0; conn_since=0
        ;;
      connecting|disconnected)
        if [ "$state" != connecting ] && [ "$state" != disconnected ]; then
            missing_since="$nowm"; missing_epoch="$nowe"; down_observed="$nowm"
            [ "$previous_down_state" = connected ] && outages=$((outages+1))
        fi
        [ "$down_observed" -gt 0 ] && [ "$down_observed" -le "$nowm" ] || down_observed="$nowm"
        [ "$outage_hint_mono" -gt 0 ] || outage_hint_mono="$nowm"
        state="$observed"; last_down="$nowe"; conn_key=; conn_since=0; conn_since_mono=0
        ;;
      *)
        state=unknown; conn_key=; missing_since=0; missing_epoch=0; conn_since=0; conn_since_mono=0
        down_observed=0
        [ "$outage_hint_mono" -le 0 ] || missing_epoch="$previous_missing_epoch"
        new_transport=; new_remote=
        ;;
    esac
    transport="$new_transport"; remote="$new_remote"; sample_epoch="$nowe"
    save_state || return $?
    write_evidence || return $?
}

write_evidence() {
    if ! printf '%s|%s|%s|%s|%s|%s\n' "$source" "$duration" "$close_code" "$tcp_hint" "$native_reason" "$decision" > "$EVIDENCE.tmp"; then
        rm -f "$EVIDENCE.tmp"
        return 1
    fi
    if ! mv -f "$EVIDENCE.tmp" "$EVIDENCE"; then
        rm -f "$EVIDENCE.tmp"
        return 1
    fi
}

auto_recovery() {
    decision=not_disconnected
    auto_enabled || { decision=disabled; return 0; }
    case "$state" in connecting|disconnected) :;; *) return 0;; esac
    nowm="$(num "$(monotime)")"
    interval="$(retry_interval)"
    if [ "$last_try_mono" -gt 0 ] && [ "$nowm" -ge "$last_try_mono" ] && [ $((nowm-last_try_mono)) -lt "$interval" ]; then
        decision=cooldown; return 0
    fi
    required=60
    [ "$state" = disconnected ] && required=15
    observed_age=0
    [ "$down_observed" -gt 0 ] && [ "$nowm" -ge "$down_observed" ] && observed_age=$((nowm-down_observed))
    if [ "$observed_age" -lt "$required" ]; then decision=waiting_duration; return 0; fi
    first_state="$state"; first_tcp_hint="$tcp_hint"
    [ "${BERRY_FCM_TEST_MODE:-0}" = 1 ] || sleep 2
    observe || return $?
    if [ "$state" = connected ]; then
        decision=confirmation_recovered
        record_event recovery_confirmation_recovered "二次内核 Socket 采样已观察到 MCS TCP 建立；取消恢复"
    elif { [ "$state" = connecting ] || [ "$state" = disconnected ]; } && [ "$state" = "$first_state" ]; then
        record_event recovery_confirmed "两次内核 Socket 采样均确认 $state，进入恢复请求"
        request_reconnect auto
    else
        decision=confirmation_changed
        record_event recovery_confirmation_changed "二次采样状态改变或不可用；不将未知判为断联，不发送本轮恢复"
    fi
}
status_json() {
    load_state
    nowe="$(num "$(now_epoch)")"; age=-1
    [ "$sample_epoch" -gt 0 ] && [ "$nowe" -ge "$sample_epoch" ] && age=$((nowe-sample_epoch))
    source=unavailable; duration=-1; close_code=; tcp_hint=none; native_reason=not_used; decision=not_evaluated
    if [ -f "$EVIDENCE" ]; then IFS='|' read -r source duration close_code tcp_hint native_reason decision < "$EVIDENCE" || :; fi
    case "$source" in
      gms_socket|gms_socket_absence|gms_socket_absence_pending) :;;
      *) state=unknown; source=unavailable; duration=-1; close_code=; tcp_hint=unknown; native_reason=not_used; decision=sample_unavailable;;
    esac
    case "${decision:-}" in not_evaluated|not_disconnected|sample_unavailable|disabled|network_gate|cooldown|requested|request_failed|waiting_duration|confirmation_changed|confirmation_recovered) :;; *) decision=not_evaluated;; esac
    case "$native_reason" in not_used) :;; *) native_reason=not_used;; esac
    case "$duration" in -1) :;; *) is_uint "$duration" || duration=-1;; esac
    [ "$age" -ge 0 ] && [ "$age" -le 90 ] || state=stale
    # Never present stale duration as live and never extrapolate past the sample.
    connected=0; missing=0
    [ "$state" = connected ] && [ "$duration" -ge 0 ] && connected="$duration"
    { [ "$state" = connecting ] || [ "$state" = disconnected ]; } && [ "$duration" -ge 0 ] && missing="$duration"
    closes=0; successes=0
    if [ -f "$NATIVE_EVENTS" ]; then
        closes="$(awk -F'|' '$2=="gms_close"{n++} END{print n+0}' "$NATIVE_EVENTS")"
        successes="$(awk -F'|' '$2=="gms_connected"{n++} END{print n+0}' "$NATIVE_EVENTS")"
    fi
    auto=0; auto_enabled && auto=1
    gate="${BERRY_AUTO_GATE:-ready}"
    case "$gate" in ready|settling|offline|unavailable) :;; *) gate=unavailable;; esac
    interval="$(retry_interval)"
    nowm="$(num "$(monotime)")"; retry_in=0
    if [ "$last_try_mono" -gt 0 ] && [ "$nowm" -ge "$last_try_mono" ] && [ $((nowm-last_try_mono)) -lt "$interval" ]; then retry_in=$((interval-nowm+last_try_mono)); fi
    observed_up=-1
    if [ "$state" = connected ] && [ -n "$conn_key" ] &&
       [ "$conn_since_mono" -gt 0 ] && [ "$nowm" -ge "$conn_since_mono" ] &&
       [ "$age" -ge 0 ]; then
        observed_up=$((nowm-conn_since_mono-age))
        [ "$observed_up" -ge 0 ] || observed_up=0
    fi
    observed_seconds=-1
    if { [ "$state" = connecting ] || [ "$state" = disconnected ]; } && [ "$down_observed" -gt 0 ] && [ "$nowm" -ge "$down_observed" ] && [ "$age" -ge 0 ]; then
        observed_seconds=$((nowm-down_observed-age))
        [ "$observed_seconds" -ge 0 ] || observed_seconds=0
    fi
    printf '{"fcm_state":"%s","fcm_source":"%s","fcm_transport":"%s","fcm_remote":"%s","fcm_connection_since":%s,"fcm_connected_seconds":%s,"fcm_disconnect_since":%s,"fcm_missing_seconds":%s,"fcm_native_duration":%s,"fcm_observed_up_seconds":%s,"fcm_native_close_events":%s,"fcm_native_connected_events":%s,"fcm_last_close_code":"%s","fcm_tcp_hint":"%s","fcm_last_seen":%s,"fcm_last_restore":%s,"fcm_last_try":%s,"fcm_last_result":"%s","fcm_attempts":%s,"fcm_sample_time":%s,"fcm_sample_age_seconds":%s,"fcm_native_reason":"%s","fcm_auto":%s,"fcm_auto_gate":"%s","fcm_retry_in":%s,"fcm_retry_streak":%s,"fcm_observed_down_seconds":%s,"fcm_recovery_decision":"%s"}\n' \
      "$state" "$source" "$transport" "$remote" "$conn_since" "$connected" "$last_down" "$missing" "$duration" "$observed_up" "$closes" "$successes" "$close_code" "$tcp_hint" "$last_seen" "$last_restore" "$last_try_epoch" "$last_result" "$attempts" "$sample_epoch" "$age" "$native_reason" "$auto" "$gate" "$retry_in" "$retry_streak" "$observed_seconds" "$decision"
}

case "${1:-status}" in
    status)
        observe || exit $?
        status_json
        ;;
    snapshot)
        status_json
        ;;
    monitor)
        prior_decision=
        if [ -f "$EVIDENCE" ]; then
            IFS='|' read -r old_source old_duration old_close old_tcp old_reason prior_decision < "$EVIDENCE" || :
        fi
        observe || exit $?
        auto_recovery || exit $?
        write_evidence
        case "$state" in
          unknown|connecting|disconnected)
            if [ "$decision" != "$prior_decision" ]; then
                record_event recovery_decision "decision=$decision state=$state native_s=$duration gate=${BERRY_AUTO_GATE:-ready} retry_streak=$retry_streak"
            fi;;
        esac
        ;;
    rescue)
        # Not a watchdog action and not the ordinary auto_recovery policy.
        observe || exit $?
        if ! auto_enabled; then
            decision=disabled
        elif [ "${BERRY_AUTO_GATE:-ready}" != ready ]; then
            decision=network_gate
        elif [ "$state" = unknown ]; then
            auto_recovery
        elif [ "$source" != gms_socket ] && [ "$source" != gms_socket_absence ]; then
            decision=not_disconnected
        elif [ "$state" = connecting ] || [ "$state" = disconnected ]; then
            [ "${BERRY_FCM_TEST_MODE:-0}" = 1 ] || sleep 2
            observe || exit $?
            if { [ "$source" = gms_socket ] || [ "$source" = gms_socket_absence ]; } &&
               { [ "$state" = connecting ] || [ "$state" = disconnected ]; }; then
                record_event rescue_confirmed '两次采样仍未观察到 MCS 连接，准备请求恢复'
                request_reconnect rescue
            else
                decision=confirmation_changed
            fi
        else
            decision=not_disconnected
        fi
        write_evidence
        ;;
    reconnect)
        observe || exit $?
        if [ "${BERRY_AUTO_GATE:-ready}" = offline ]; then
            decision=network_gate
            record_event reconnect_skipped '当前应用无活动网络；未发送手动重连'
        elif [ "$state" = connecting ] || [ "$state" = disconnected ]; then
            request_reconnect manual
        else
            decision=not_disconnected
            record_event reconnect_skipped 'GMS 已连接或状态不可确认；未发送手动重连'
        fi
        write_evidence
        ;;
    events)
        [ -f "$NATIVE_EVENTS" ] && tail -n 80 "$NATIVE_EVENTS" || :
        ;;
    recovery-events)
        [ -f "$EVENTS" ] && tail -n 80 "$EVENTS" || :
        ;;
    reset-history)
        : > "$EVENTS"; : > "$NATIVE_EVENTS"; echo 'FCM 事件历史已清空（连接状态未更改）'
        ;;
    *) echo 'status|snapshot|monitor|rescue|reconnect|events|recovery-events|reset-history' >&2; exit 2;;
esac
