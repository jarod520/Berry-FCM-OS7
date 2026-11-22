#!/system/bin/sh
# BerryFCM KernelSU (UID 0): kernel-visible GMS UID MCS sockets are the sole connection-state evidence.
# Only observes GMS-owned TCP sockets and requests targeted recovery broadcasts; it never
# changes DNS, VPN, proxy, routing, or force-stops Google Play services.
set -u

GMS=com.google.android.gms
DATA="${BERRY_FCM_DATA:-/data/adb/berry_fcm_ksu}"
STATE="$DATA/mcs-monitor.state"
EVENTS="$DATA/mcs-monitor-events.log"
NATIVE_EVENTS="$DATA/mcs-native-events.log" # legacy history only; never read for decisions
EVIDENCE="$DATA/mcs-evidence"
DNS_IPS="$DATA/mcs-mtalk-dns-ips.txt"
LEARNED_IPS="$DATA/mcs-mtalk-learned-ips.txt"
DNS_TIME="$DATA/mcs-mtalk-dns-time"
LOCK_OWNER="$DATA/mcs-monitor.lock.owner"
lock_owner_stamp=
SS_BIN="${BERRY_SS_BIN:-ss}"
TOYBOX_BIN="${BERRY_TOYBOX_BIN:-/system/bin/toybox}"
PROC_NET_DIR="${BERRY_PROC_NET_DIR:-/proc/net}"
CMD_BIN="${BERRY_CMD_BIN:-cmd}"
PM_BIN="${BERRY_PM_BIN:-pm}"
AM_BIN="${BERRY_AM_BIN:-am}"
if [ -x /system/bin/am ] && [ -z "${BERRY_AM_BIN:-}" ]; then AM_BIN=/system/bin/am; fi
UPTIME_FILE="${BERRY_UPTIME_FILE:-/proc/uptime}"
BOOT_ID_FILE="${BERRY_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"

[ "$(id -u)" = 0 ] || { echo "ERROR: 需要 KernelSU Root (UID 0)" >&2; exit 10; }
mkdir -p "$DATA" || exit 11

is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
num() { is_uint "${1:-}" && printf '%s\n' "$1" || printf '0\n'; }
now_epoch() { date +%s 2>/dev/null | awk '/^[0-9]+$/ {print; found=1} END {if (!found) print 0}'; }
monotime() { awk '{printf "%d\n", $1}' "$UPTIME_FILE" 2>/dev/null | head -n 1; }
boot_id() { cat "$BOOT_ID_FILE" 2>/dev/null; }
proc_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $20}'
}
proc_group_id() {
    [ -r "/proc/$1/stat" ] || return 1
    tr -d "\n" < "/proc/$1/stat" 2>/dev/null | sed "s/^.*) //" | awk '{print $3}'
}
write_lock_owner() {
    lock_owner_pid=
    IFS=' ' read -r lock_owner_pid _ < /proc/self/stat 2>/dev/null || return 1
    case "$lock_owner_pid" in ''|*[!0-9]*) return 1;; esac
    lock_owner_stamp="$(proc_start_time "$lock_owner_pid")"
    lock_owner_pgid="$(proc_group_id "$lock_owner_pid")"
    [ -n "$lock_owner_stamp" ] && [ -n "$lock_owner_pgid" ] || return 1
    lock_owner_isolated=0
    lock_owner_group_stamp=
    if [ "${BERRY_FCM_ISOLATED_GROUP:-0}" = 1 ]; then
        # timeout owns the process group in timeout-backed runs, so its PGID
        # can differ from the monitor PID. Record the group leader identity.
        lock_owner_group_stamp="$(proc_start_time "$lock_owner_pgid")"
        if [ -n "$lock_owner_group_stamp" ]; then
            lock_owner_isolated=1
        fi
    fi
    owner_tmp="$LOCK_OWNER.tmp.$lock_owner_pid"
    if printf "%s %s %s %s %s\n" "$lock_owner_pid" "$lock_owner_stamp" "$lock_owner_pgid" "$lock_owner_isolated" "$lock_owner_group_stamp" > "$owner_tmp" &&
       mv -f "$owner_tmp" "$LOCK_OWNER"; then
        return 0
    fi
    rm -f "$owner_tmp"
    return 1
}
clear_lock_owner() {
    [ -n "$lock_owner_pid" ] && [ -n "$lock_owner_stamp" ] || return 0
    owner_pid=; owner_stamp=
    IFS=' ' read -r owner_pid owner_stamp < "$LOCK_OWNER" 2>/dev/null || :
    if [ "$owner_pid" = "$lock_owner_pid" ] && [ "$owner_stamp" = "$lock_owner_stamp" ]; then
        rm -f "$LOCK_OWNER"
    fi
}

# Persisted fields use a fixed pipe-delimited schema. Never source the file.
load_state() {
    b="$(boot_id)"
    state=never_seen; conn_key=; conn_since=0; conn_since_mono=0; last_seen=0
    missing_since=0; missing_epoch=0; last_try_mono=0; last_try_epoch=0
    attempts=0; last_result=none; last_restore=0; outages=0
    transport=; remote=; sample_epoch=0; sample_mono=0; last_try_reason=none
    reconnects=0; last_down=0
    down_observed=0; retry_streak=0; outage_hint_mono=0
    native_timer_duration=0; native_timer_since=0; native_timer_last_request=0; native_timer_key=
    prev_b=
    if [ -f "$STATE" ]; then
        IFS='|' read -r prev_b state conn_key conn_since conn_since_mono last_seen missing_since missing_epoch last_try_mono last_try_epoch attempts last_result last_restore outages transport remote sample_epoch last_try_reason reconnects last_down down_observed retry_streak outage_hint_mono native_timer_duration native_timer_since native_timer_last_request native_timer_key sample_mono < "$STATE" || :
    fi
    conn_since="$(num "$conn_since")"; conn_since_mono="$(num "$conn_since_mono")"; last_seen="$(num "$last_seen")"
    missing_since="$(num "$missing_since")"; missing_epoch="$(num "$missing_epoch")"
    last_try_mono="$(num "$last_try_mono")"; last_try_epoch="$(num "$last_try_epoch")"
    attempts="$(num "$attempts")"; last_restore="$(num "$last_restore")"
    outages="$(num "$outages")"; sample_epoch="$(num "$sample_epoch")"; sample_mono="$(num "$sample_mono")"
    reconnects="$(num "$reconnects")"; last_down="$(num "$last_down")"
    down_observed="$(num "${down_observed:-0}")"; retry_streak="$(num "${retry_streak:-0}")"
    outage_hint_mono="$(num "${outage_hint_mono:-0}")"
    native_timer_duration="$(num "${native_timer_duration:-0}")"
    native_timer_since="$(num "${native_timer_since:-0}")"
    native_timer_last_request="$(num "${native_timer_last_request:-0}")"
    case "$state" in connected|connecting|disconnected|unknown|never_seen) : ;; *) state=unknown;; esac
    case "$last_result" in none|requested|failed|restored) : ;; *) last_result=none;; esac
    case "$last_try_reason" in none|auto|manual|rescue) : ;; *) last_try_reason=none;; esac
    if [ -n "$prev_b" ] && [ "$prev_b" != "$b" ]; then
        state=never_seen; conn_key=; conn_since=0; conn_since_mono=0; missing_since=0; missing_epoch=0
        last_try_mono=0; transport=; remote=; sample_epoch=0; sample_mono=0; down_observed=0; retry_streak=0; outage_hint_mono=0
        native_timer_duration=0; native_timer_since=0; native_timer_last_request=0; native_timer_key=
        : > "$LEARNED_IPS"
        record_event reboot '设备重启：清除上一启动周期的连接计时，保留历史事件'
    fi
}

save_state() {
    tmp="$STATE.$$"
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$b" "$state" "$conn_key" "$conn_since" "$conn_since_mono" "$last_seen" "$missing_since" "$missing_epoch" \
      "$last_try_mono" "$last_try_epoch" "$attempts" "$last_result" "$last_restore" "$outages" \
      "$transport" "$remote" "$sample_epoch" "$last_try_reason" "$reconnects" "$last_down" "$down_observed" "$retry_streak" "$outage_hint_mono" \
      "$native_timer_duration" "$native_timer_since" "$native_timer_last_request" "$native_timer_key" "$sample_mono" > "$tmp" || { rc=$?; rm -f "$tmp"; return "$rc"; }
    mv -f "$tmp" "$STATE" || { rc=$?; rm -f "$tmp"; return "$rc"; }
    return 0
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
    [ "$old" -gt 0 ] && [ "$now" -ge "$old" ] && [ $((now-old)) -lt 600 ] && return 0
    tmp="$DNS_IPS.$$"; : > "$tmp"
    for host in mtalk.google.com alt1-mtalk.google.com; do
        if [ -x "$TOYBOX_BIN" ] && "$TOYBOX_BIN" --list 2>/dev/null | grep -qx timeout; then
            # Keep DNS probes in the monitor's own process group so service
            # shutdown can terminate them together with the monitor.
            "$TOYBOX_BIN" timeout --foreground -k 1 3 nslookup "$host" 2>/dev/null
        elif command -v timeout >/dev/null 2>&1; then
            timeout_help="$(timeout --help 2>&1 || :)"
            case "$timeout_help" in
                *--foreground*) timeout --foreground 3 nslookup "$host" 2>/dev/null;;
                *"Run PROG."*) timeout 3 nslookup "$host" 2>/dev/null;;
                *) :;;
            esac
        else
            :
        fi | awk '/Address/ {ip=$NF; if(ip ~ /^[0-9A-Fa-f:.]+$/) print tolower(ip)}' >> "$tmp"
    done
    if [ -s "$tmp" ]; then
        sort -u "$tmp" > "$DNS_IPS.new" && mv -f "$DNS_IPS.new" "$DNS_IPS"
    else
        # Expired DNS answers must not keep classifying unrelated GMS :443
        # sockets as MCS after a failed refresh.
        : > "$DNS_IPS"
    fi
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

# Keep only recently observed GMS MCS peer addresses. A learned address
# is weak evidence for a GMS-owned :443 socket, never a replacement for the
# native GMS state or an exact :5228-5230 socket.
refresh_learned_ips() {
    learned_now="$(num "$(now_epoch)")"
    [ "$learned_now" -gt 0 ] || { : > "$LEARNED_IPS"; return 0; }
    learned_tmp="$LEARNED_IPS.tmp"
    {
        [ ! -f "$LEARNED_IPS" ] || cat "$LEARNED_IPS"
        printf '%s\n' "$1" | awk -v u="$2" -v now="$learned_now" '
          ($1=="ESTAB" || $1=="ESTABLISHED") {
            if (!match($0,/uid:[0-9]+/)) next
            owner=substr($0,RSTART+4,RLENGTH-4)+0; if(owner!=u+0) next
            peer=$5; port=peer; sub(/^.*:/,"",port)
            if(port==5228 || port==5229 || port==5230){
              ip=peer; sub(/:[0-9]+$/, "", ip); gsub(/^\[|\]$/, "", ip)
              sub(/^::ffff:/, "", ip); print tolower(ip) "|" now
            }
          }'
    } | awk -F'|' -v now="$learned_now" -v ttl=120 '
      function valid_ip(ip, a,n,i) {
        if(length(ip)<3 || length(ip)>45 || ip !~ /^[0-9a-f:.]+$/) return 0
        if(index(ip,":")) return 1
        if(index(ip,".")) {
          n=split(ip,a,".")
          if(n!=4) return 0
          for(i=1;i<=4;i++) if(a[i]!~/^[0-9]+$/ || a[i]+0>255) return 0
          return 1
        }
        return 0
      }
      NF==2 && $2~/^[0-9]+$/ {
        ip=tolower($1); stamp=$2+0
        if(!valid_ip(ip) || stamp>now || now-stamp>ttl) next
        if(!(ip in newest) || stamp>newest[ip]) newest[ip]=stamp
      }
      END {for(ip in newest) print ip "|" newest[ip]}
    ' > "$learned_tmp" && mv -f "$learned_tmp" "$LEARNED_IPS"
}

scan_sockets() {
    uid="$(gms_uid 2>/dev/null)" || { printf 'unknown||||gms_uid_unavailable\n'; return; }
    resolve_mtalk >/dev/null 2>&1 || :
    raw=
    if command -v "$SS_BIN" >/dev/null 2>&1; then
        raw="$("$SS_BIN" -tnpe 2>/dev/null)" || raw=
    fi

    # Fall back when ss does not expose the GMS UID specifically. Other UID
    # annotations in ss output do not prove that GMS ownership was observable.
    if [ -z "$raw" ] || ! printf '%s\n' "$raw" | grep -Eq "uid:${uid}([^0-9]|$)"; then
        for table in "$PROC_NET_DIR/tcp" "$PROC_NET_DIR/tcp6"; do
            [ -r "$table" ] || continue
            awk -v u="$uid" '
              NR > 1 && $8 == u {
                split($3,a,":"); port=toupper(a[2]); st=$4
                if (port=="146C" || port=="146D" || port=="146E") {
                  p=(port=="146C"?5228:(port=="146D"?5229:5230))
                  if (st=="01" && rank<3) {rank=3; kind="connected"; transport="tcp" p; key=$2 ">" $3 "#" $10}
                  else if (st=="02" && rank<1) {rank=1; kind="connecting"; transport="tcp" p; key=$2 ">" $3 "#" $10}
                } else if (port=="01BB" && st=="01") {unverified443=1}
              }
              END {
                if (rank>0) printf "%s|%s||%s|\n",kind,transport,key
                else if (unverified443) print "unknown||||proc_net_443_unverified"
                else print "absent||||proc_net_no_mcs_socket"
              }' "$table"
        done | awk -F'|' '
          $1=="connected" {connected=$0}
          $1=="connecting" && !connecting {connecting=$0}
          $1=="unknown" && !unknown {unknown=$0}
          $1=="absent" {absent=$0}
          END {if(connected) print connected; else if(connecting) print connecting; else if(unknown) print unknown; else if(absent) print absent; else print "unknown||||proc_net_unavailable"}'
        return
    fi

    # Refresh short-lived learned IPs from exact GMS UID-owned MCS sockets.
    refresh_learned_ips "$raw" "$uid"
    learned_ips="$(awk -F'|' -v now="$(num "$(now_epoch)")" '
      function valid_ip(ip, a,n,i) {
        if(length(ip)<3 || length(ip)>45 || ip !~ /^[0-9a-f:.]+$/) return 0
        if(index(ip,":")) return 1
        if(index(ip,".")) {
          n=split(ip,a,".")
          if(n!=4) return 0
          for(i=1;i<=4;i++) if(a[i]!~/^[0-9]+$/ || a[i]+0>255) return 0
          return 1
        }
        return 0
      }
      NF==2 && now>0 && $2~/^[0-9]+$/ && $2+0<=now && now-($2+0)<=120 && valid_ip($1) {print tolower($1)}
    ' "$LEARNED_IPS" 2>/dev/null)"
    ips="$(cat "$DNS_IPS" 2>/dev/null; printf '%s\n' "$learned_ips")"
    ips="$(printf '%s\n' "$ips" | awk 'NF && !seen[$0]++ {printf "%s%s",sep,$0;sep="|"}')"
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

auto_enabled() {
    [ "$(cat "$DATA/enabled" 2>/dev/null)" = 1 ]
}

retry_interval() {
    case "$retry_streak" in 0) echo 30;; 1) echo 45;; 2) echo 60;; *) echo 90;; esac
}

# A continuous absence of a verified GMS UID-owned MCS socket is considered only
# after 45 seconds. A fresh MCS socket is positive transport evidence; one absence
# sample alone never creates an outage. Sampling gaps reset the continuity anchor.
socket_fallback_ready() {
    [ "$tcp_hint" = absent ] || return 1
    socket_down_age=0
    if is_uint "${1:-}" && [ "$1" -ge 60 ]; then
        socket_down_age="$1"
        return 0
    fi
    socket_down_anchor="$(num "${outage_hint_mono:-0}")"
    socket_down_now="$(num "$(monotime)")"
    [ "$socket_down_anchor" -gt 0 ] && [ "$socket_down_now" -ge "$socket_down_anchor" ] || return 1
    socket_down_age=$((socket_down_now-socket_down_anchor))
    [ "$socket_down_age" -ge 45 ]
}

request_reconnect() {
    reason="$1"; nowm="$(num "$(monotime)")"; nowe="$(num "$(now_epoch)")"
    case "$state" in connecting|disconnected) :;; *) decision=not_disconnected; return 0;; esac
    interval="$(retry_interval)"
    [ "$reason" != manual ] || interval=60
    if [ "$last_try_mono" -gt 0 ] && [ "$nowm" -ge "$last_try_mono" ] && [ $((nowm-last_try_mono)) -lt "$interval" ]; then
        decision=cooldown
        if [ "$reason" = manual ]; then
            record_event reconnect_skipped "手动恢复未发送：距上次请求尚未达到退避间隔，剩余 $((interval-nowm+last_try_mono)) 秒"
        fi
        return 0
    fi
    [ "$reason" != auto ] || auto_enabled || { decision=disabled; return 0; }
    last_try_mono="$nowm"; last_try_epoch="$nowe"; attempts=$((attempts+1))
    retry_streak=$((retry_streak+1)); last_try_reason="$reason"; last_result=failed
    save_state || return $?
    stage=$(((retry_streak - 1) % 4))
    case "$stage" in
      0)
        action=com.google.android.intent.action.GCM_RECONNECT
        action_label=GCM_RECONNECT
        reply="$("$AM_BIN" broadcast --user 0 -a "$action" -p "$GMS" 2>&1)"
        ;;
      1)
        action=com.google.android.intent.action.MCS_HEARTBEAT
        action_label=MCS_HEARTBEAT
        reply="$("$AM_BIN" broadcast --user 0 -a "$action" -p "$GMS" 2>&1)"
        ;;
      2)
        action=com.google.android.gms.gcm.ACTION_HEARTBEAT_NOW
        action_label=ACTION_HEARTBEAT_NOW
        reply="$("$AM_BIN" broadcast --user 0 -a "$action" -p "$GMS" 2>&1)"
        ;;
      *)
        action=com.google.android.intent.action.GTALK_HEARTBEAT
        action_label=GTALK_HEARTBEAT
        reply="$("$AM_BIN" broadcast --user 0 -a "$action" -p "$GMS" 2>&1)"
        ;;
    esac
    rc=$?
    if [ "$rc" -eq 0 ] && printf '%s\n' "$reply" | grep -q 'Broadcast completed:' &&
        ! printf '%s\n' "$reply" | grep -qiE 'Permission Denial|SecurityException|not allowed|Error:|result=-[0-9]'; then
        last_result=requested; decision=requested
        completion="$(printf '%s\n' "$reply" | grep 'Broadcast completed:' | tail -n 1)"
        record_event reconnect_requested "$reason UID=0 $action_label exit=$rc $completion；命令返回不代表投递或恢复（第 $attempts 次）"
    else
        last_result=failed; decision=request_failed
        record_event reconnect_failed "$reason UID=0 $action_label exit=$rc；请核对 KernelSU Root 和 GMS 版本"
    fi
    save_state
}

observe() {
    load_state
    decision=not_evaluated
    nowm="$(num "$(monotime)")"; nowe="$(num "$(now_epoch)")"
    [ "$nowm" -gt 0 ] && [ "$nowe" -gt 0 ] || return 12
    sample_gap_age=-1
    if [ "$sample_mono" -gt 0 ] && [ "$nowm" -ge "$sample_mono" ]; then
        sample_gap_age=$((nowm-sample_mono))
    elif [ "$sample_mono" -le 0 ] && [ "$sample_epoch" -gt 0 ] && [ "$nowe" -ge "$sample_epoch" ]; then
        sample_gap_age=$((nowe-sample_epoch))
    fi
    previous_down_state="$state"
    previous_missing_epoch="$missing_epoch"
    previous_down_observed="$(num "${outage_hint_mono:-0}")"
    [ "$previous_down_observed" -gt 0 ] || previous_down_observed="$(num "${down_observed:-0}")"
    if [ "$previous_down_observed" -gt "$nowm" ] || [ "$sample_gap_age" -gt 90 ]; then previous_down_observed=0; fi
    if [ "$sample_gap_age" -gt 90 ]; then
        record_event sample_gap "距离上次有效内核 Socket 采样 $sample_gap_age 秒；重置连续性计时并重新采样"
        state=unknown; missing_since=0; missing_epoch=0; conn_since=0; down_observed=0
        native_timer_duration=0; native_timer_since=0; native_timer_last_request=0; native_timer_key=
    fi
    outage_hint_mono="$previous_down_observed"
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
            record_event socket_connected "内核 Socket 诊断观察到 GMS UID 的 MCS TCP 已建立；只证明传输层连接，不代表 FCM 心跳或推送已验证"
        ;;
      connecting)
        observed=connecting; source=gms_socket
        new_transport="$socket_transport"; new_remote="$socket_remote"
        if [ "$previous_down_state" != connecting ] || [ "$outage_hint_mono" -le 0 ] || [ "$socket_now" -lt "$outage_hint_mono" ]; then
            down_observed="$socket_now"; outage_hint_mono="$socket_now"
            record_event socket_connecting "内核 Socket 诊断观察到 GMS MCS TCP 正在建立连接"
        fi
        previous_down_observed="$outage_hint_mono"
        ;;
      absent)
        if [ "$outage_hint_mono" -le 0 ] || [ "$socket_now" -lt "$outage_hint_mono" ]; then
            outage_hint_mono="$socket_now"
            record_event tcp_absence_started "已成功读取 GMS UID 与内核 TCP 表，但未发现 MCS TCP；开始连续缺失计时，单次缺失不触发恢复"
        fi
        socket_down_age=$((socket_now-outage_hint_mono))
        previous_down_observed="$outage_hint_mono"; tcp_hint=absent
        if [ "$socket_down_age" -ge 45 ]; then
            observed=disconnected; source=gms_socket_absence
            [ "$previous_down_state" = disconnected ] ||
                record_event tcp_absence_confirmed "GMS MCS TCP 连续缺失 ${socket_down_age} 秒，已达到内核证据阈值"
        fi
        ;;
      *)
        observed=unknown; source=unavailable; tcp_hint=unknown
        if [ "$previous_down_state" != unknown ]; then
            record_event socket_evidence_unavailable "内核 Socket 证据暂不可用：${socket_reason:-no_detail}；本轮不伪造连接状态，后台巡检继续"
        fi
        ;;
    esac
    case "$observed" in
      connected)
        case "$previous_down_state" in
          connecting|disconnected)
            last_restore="$nowe"
            if [ "$last_result" = requested ] && [ "$last_try_epoch" -ge "$previous_missing_epoch" ] && [ "$last_try_epoch" -gt 0 ]; then last_result=restored; fi
            record_event connection_restored "内核 Socket 诊断再次观察到 GMS MCS TCP 建立；FCM 应用层可用性仍需独立验证"
            ;;
          unknown)
            [ "$previous_down_observed" -le 0 ] ||
                record_event connection_observed_after_unknown "此前样本不可用，本轮重新观察到 GMS MCS TCP；不推断未知期间的恢复时刻"
            ;;
        esac
        current_key="$new_remote"
        if [ "$state" != connected ] || [ "$conn_key" != "$current_key" ] || [ "$conn_since_mono" -le 0 ] ||
           [ "$nowm" -lt "$conn_since_mono" ] || [ "$sample_mono" -le 0 ] ||
           [ "$nowm" -lt "$sample_mono" ] || [ $((nowm-sample_mono)) -gt 45 ]; then conn_since_mono="$nowm"; fi
        conn_key="$current_key"; state=connected; last_seen="$nowe"; missing_since=0; missing_epoch=0
        down_observed=0; outage_hint_mono=0; retry_streak=0; conn_since=0
        ;;
      connecting|disconnected)
        if [ "$state" != connecting ] && [ "$state" != disconnected ]; then
            [ "$previous_down_state" != connected ] || outages=$((outages+1))
            missing_since="$nowm"; missing_epoch="$nowe"; down_observed="$nowm"
            case "$source" in gms_socket_absence) :;; gms_socket) record_event connection_down "观察到 MCS TCP 正在连接，尚未建立";; esac
        fi
        [ "$down_observed" -gt 0 ] && [ "$down_observed" -le "$nowm" ] || down_observed="$nowm"
        [ "$outage_hint_mono" -gt 0 ] || outage_hint_mono="$nowm"
        state="$observed"; last_down="$nowe"; conn_key=; conn_since=0; conn_since_mono=0
        ;;
      *)
        state=unknown; conn_key=; missing_since=0; missing_epoch=0; conn_since=0; conn_since_mono=0; down_observed=0
        [ "$outage_hint_mono" -le 0 ] || missing_epoch="$previous_missing_epoch"
        new_transport=; new_remote=
        ;;
    esac
    transport="$new_transport"; remote="$new_remote"; sample_epoch="$nowe"; sample_mono="$nowm"
    native_timer_duration=0; native_timer_since=0; native_timer_last_request=0; native_timer_key=
    write_evidence || return $?
    save_state
}

write_evidence() {
    evidence_tmp="$EVIDENCE.tmp"
    if printf '%s|%s|%s|%s|%s|%s|%s\n' "$source" "$duration" "$close_code" "$tcp_hint" "$native_reason" "$decision" "$sample_mono" > "$evidence_tmp" &&
       mv -f "$evidence_tmp" "$EVIDENCE"; then
        return 0
    fi
    rm -f "$evidence_tmp"
    return 1
}

confirm_recovery() {
    first_state="$state"; first_tcp_hint="$tcp_hint"
    [ "${BERRY_FCM_TEST_MODE:-0}" = 1 ] || sleep 2
    observe || return $?
    if [ "$state" = connected ]; then
        decision=confirmation_recovered
        record_event recovery_confirmation_recovered "二次内核 Socket 采样已观察到 MCS TCP 建立；取消本轮恢复命令"
        return 0
    fi
    if [ "$tcp_hint" = absent ] && [ "$state" = disconnected ] &&
       { [ "$first_tcp_hint" = absent ] || [ "$first_state" = disconnected ] || [ "$first_state" = unknown ]; }; then
        record_event recovery_confirmed "两次独立内核 Socket 采样确认 MCS TCP 连续缺失，进入分阶段恢复"
        request_reconnect "$1"
    elif [ "$state" = connecting ] && [ "$first_state" = connecting ]; then
        record_event recovery_confirmed "两次内核 Socket 采样均观察到 MCS TCP 正在连接，进入分阶段恢复"
        request_reconnect "$1"
    else
        decision=confirmation_changed
        record_event recovery_confirmation_unavailable "二次采样没有维持明确的断联/连接中证据：first=$first_state/$first_tcp_hint second=$state/$tcp_hint；本轮不发送恢复命令"
    fi
}

auto_recovery() {
    decision=not_disconnected
    auto_enabled || { decision=disabled; return 0; }
    nowm="$(num "$(monotime)")"; interval="$(retry_interval)"
    if [ "$last_try_mono" -gt 0 ] && [ "$nowm" -ge "$last_try_mono" ] && [ $((nowm-last_try_mono)) -lt "$interval" ]; then
        decision=cooldown; return 0
    fi
    case "$state" in
      connecting|disconnected)
        required=60; [ "$state" = disconnected ] && required=15
        observed_age=0
        [ "$down_observed" -gt 0 ] && [ "$nowm" -ge "$down_observed" ] && observed_age=$((nowm-down_observed))
        if [ "$observed_age" -ge "$required" ]; then confirm_recovery auto; else decision=waiting_duration; fi
        ;;
      unknown)
        if [ "$tcp_hint" = absent ] && socket_fallback_ready -1; then confirm_recovery auto; else decision=sample_unavailable; fi
        ;;
      *) decision=not_disconnected;;
    esac
}

status_json() {
    load_state
    nowe="$(num "$(now_epoch)")"; nowm="$(num "$(monotime)")"; age=-1
    if [ "$sample_mono" -gt 0 ]; then
        [ "$nowm" -ge "$sample_mono" ] && age=$((nowm-sample_mono))
    elif [ "$sample_epoch" -gt 0 ] && [ "$nowe" -ge "$sample_epoch" ]; then
        # Backward-compatible age calculation for state files written before
        # sample_mono existed. New samples use monotonic uptime exclusively.
        age=$((nowe-sample_epoch))
    fi
    source=unavailable; duration=-1; close_code=; tcp_hint=none; native_reason=not_used; decision=not_evaluated
    evidence_sample_mono=0
    if [ -f "$EVIDENCE" ]; then
        IFS='|' read -r source duration close_code tcp_hint native_reason decision evidence_sample_mono < "$EVIDENCE" || :
    fi
    evidence_sample_mono="$(num "$evidence_sample_mono")"
    if [ "$sample_mono" -gt 0 ] || [ "$evidence_sample_mono" -gt 0 ]; then
        if [ "$evidence_sample_mono" -ne "$sample_mono" ]; then
            age=-1
            source=unavailable; duration=-1; close_code=; tcp_hint=none
            native_reason=not_used; decision=sample_unavailable
        fi
    fi
    case "${decision:-}" in not_evaluated|not_disconnected|sample_unavailable|disabled|cooldown|requested|request_failed|waiting_duration|waiting_confirmation|confirmation_changed|confirmation_recovered) :;; *) decision=not_evaluated;; esac
    case "$native_reason" in not_used) :;; *) native_reason=not_used;; esac
    case "$duration" in -1) :;; *) is_uint "$duration" || duration=-1;; esac
    [ "$age" -ge 0 ] && [ "$age" -le 90 ] || state=stale
    # Never present stale duration as live and never extrapolate past the sample.
    connected=0; missing=0
    [ "$state" = connected ] && [ "$age" -ge 0 ] && [ "$conn_since_mono" -gt 0 ] && [ "$nowm" -ge "$conn_since_mono" ] && connected=$((nowm-conn_since_mono-age))
    [ "$connected" -ge 0 ] 2>/dev/null || connected=0
    [ "$connected" -gt 0 ] && conn_since=$((nowe-connected))
    { [ "$state" = connecting ] || [ "$state" = disconnected ]; } && [ "$age" -ge 0 ] && [ "$down_observed" -gt 0 ] && [ "$nowm" -ge "$down_observed" ] && missing=$((nowm-down_observed-age))
    [ "$missing" -ge 0 ] 2>/dev/null || missing=0
    closes=0; successes=0
    if [ -f "$NATIVE_EVENTS" ]; then
        closes="$(awk -F'|' '$2=="gms_close"{n++} END{print n+0}' "$NATIVE_EVENTS")"
        successes="$(awk -F'|' '$2=="gms_connected"{n++} END{print n+0}' "$NATIVE_EVENTS")"
    fi
    auto=0; auto_enabled && auto=1
    interval="$(retry_interval)"
    retry_in=0
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
    printf '{"fcm_state":"%s","fcm_source":"%s","fcm_transport":"%s","fcm_remote":"%s","fcm_connection_since":%s,"fcm_connected_seconds":%s,"fcm_disconnect_since":%s,"fcm_missing_seconds":%s,"fcm_native_duration":%s,"fcm_observed_up_seconds":%s,"fcm_native_close_events":%s,"fcm_native_connected_events":%s,"fcm_last_close_code":"%s","fcm_tcp_hint":"%s","fcm_last_seen":%s,"fcm_last_restore":%s,"fcm_last_try":%s,"fcm_last_try_reason":"%s","fcm_last_result":"%s","fcm_attempts":%s,"fcm_outages":%s,"fcm_sample_time":%s,"fcm_sample_uptime":%s,"fcm_sample_age_seconds":%s,"fcm_native_reason":"%s","fcm_auto":%s,"fcm_retry_in":%s,"fcm_retry_streak":%s,"fcm_observed_down_seconds":%s,"fcm_recovery_decision":"%s"}\n' \
      "$state" "$source" "$transport" "$remote" "$conn_since" "$connected" "$last_down" "$missing" "$duration" "$observed_up" "$closes" "$successes" "$close_code" "$tcp_hint" "$last_seen" "$last_restore" "$last_try_epoch" "$last_try_reason" "$last_result" "$attempts" "$outages" "$sample_epoch" "$sample_mono" "$age" "$native_reason" "$auto" "$retry_in" "$retry_streak" "$observed_seconds" "$decision"
}

run_monitor_command() {
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
        prior_evidence_sample_mono=0
        prior_state_sample_mono="$(awk -F'|' 'NR==1 {print $28}' "$STATE" 2>/dev/null)"
        prior_state_sample_mono="$(num "$prior_state_sample_mono")"
        if [ -f "$EVIDENCE" ]; then
            IFS='|' read -r old_source old_duration old_close old_tcp old_reason prior_decision prior_evidence_sample_mono < "$EVIDENCE" || :
        fi
        prior_evidence_sample_mono="$(num "$prior_evidence_sample_mono")"
        if { [ "$prior_state_sample_mono" -gt 0 ] || [ "$prior_evidence_sample_mono" -gt 0 ]; } &&
           [ "$prior_state_sample_mono" -ne "$prior_evidence_sample_mono" ]; then
            prior_decision=
        fi
        observe || exit $?
        auto_recovery || exit $?
        write_evidence
        case "$state" in
          unknown|connecting|disconnected)
            if [ "$decision" != "$prior_decision" ]; then
                record_event recovery_decision "decision=$decision state=$state source=$source tcp=$tcp_hint evidence=${parse_detail:-none} retry_streak=$retry_streak"
            fi;;
          connected) :;;
        esac
        ;;
    reconnect)
        observe || exit $?
        if { { [ "$source" = gms_socket ] || [ "$source" = gms_socket_absence ]; } && { [ "$state" = connecting ] || [ "$state" = disconnected ]; }; } ||
           { [ "$state" = unknown ] && [ "$tcp_hint" = absent ] && socket_fallback_ready -1; }; then
            confirm_recovery manual || exit $?
        else
            decision=not_disconnected
            record_event reconnect_skipped "内核 Socket 证据未确认断联或持续连接中，未发送手动重连"
        fi
        write_evidence || exit $?
        case "$decision" in
          requested) echo "已请求 GMS 恢复，等待下一次连接采样确认";;
          request_failed) echo "Root 重连广播未确认，请查看恢复事件";;
          cooldown) echo "仍在重连冷却期";;
          confirmation_recovered) echo "二次内核采样已观察到 MCS TCP，取消本轮恢复";;
          *) echo "GMS 已连接或状态不可确认，未发送重连";;
        esac
        ;;
    events)
        [ -f "$EVENTS" ] && tail -n 80 "$EVENTS" || :
        ;;
    native-events)
        [ -f "$NATIVE_EVENTS" ] && tail -n 80 "$NATIVE_EVENTS" || :
        ;;
    reset-history)
        : > "$EVENTS"; : > "$NATIVE_EVENTS"; echo 'FCM 事件历史已清空（连接状态未更改）'
        ;;
    *) echo 'status|snapshot|monitor|reconnect|events|native-events|reset-history' >&2; exit 2;;
esac
}

with_flock() {
    # Keep the descriptor lock held by flock for the entire monitor command.
    # The child writes its real command status to a private result file and
    # exits zero so flock's status remains reserved for lock/launcher errors.
    lock_result_pid=
    IFS=' ' read -r lock_result_pid _ < /proc/self/stat || return 14
    case "$lock_result_pid" in ''|*[!0-9]*) return 14;; esac
    lock_result="$DATA/mcs-monitor.lock.result.$lock_result_pid"
    rm -f "$lock_result" "$lock_result.tmp."*
    "$@" -xn 9 sh "$0" "$command" --locked "$lock_result"
    flock_rc=$?
    if [ ! -s "$lock_result" ]; then
        rm -f "$lock_result" "$lock_result.tmp."*
        if [ "$flock_rc" -eq 1 ]; then
            echo "后台正在检查 GMS，请稍后重试" >&2
            return 13
        fi
        printf "无法取得 GMS 检查锁：flock 退出码 %s\n" "$flock_rc" >&2
        return 14
    fi
    monitor_rc="$(cat "$lock_result" 2>/dev/null)"
    rm -f "$lock_result"
    is_uint "$monitor_rc" || return 14
    return "$monitor_rc"
}

command="${1:-status}"
if [ "${2:-}" = --locked ]; then
    lock_result="${3:-}"
    case "$lock_result" in "$DATA"/mcs-monitor.lock.result.*) :;; *) exit 14;; esac
    if write_lock_owner; then
        trap 'clear_lock_owner' EXIT
        (run_monitor_command "$command")
        monitor_rc=$?
        clear_lock_owner
        trap - EXIT
    else
        echo "无法登记 GMS monitor 进程身份，拒绝启动未受监管的检查" >&2
        monitor_rc=14
    fi
    result_writer_pid=
    IFS=' ' read -r result_writer_pid _ < /proc/self/stat || exit 14
    case "$result_writer_pid" in ''|*[!0-9]*) exit 14;; esac
    printf '%s\n' "$monitor_rc" > "$lock_result.tmp.$result_writer_pid" &&
        mv -f "$lock_result.tmp.$result_writer_pid" "$lock_result" || exit 14
    exit 0
fi
case "$command" in
    status|monitor|reconnect|reset-history)
        busybox="${BERRY_KSU_BUSYBOX:-/data/adb/ksu/bin/busybox}"
        if [ -x /system/bin/flock ]; then
            with_flock /system/bin/flock 9>>"$DATA/mcs-monitor.lock"
        elif [ -x "$busybox" ] && "$busybox" --list 2>/dev/null | grep -qx flock; then
            with_flock "$busybox" flock 9>>"$DATA/mcs-monitor.lock"
        elif command -v flock >/dev/null 2>&1; then
            with_flock flock 9>>"$DATA/mcs-monitor.lock"
        else
            lock_boot="$(boot_id | tr -cd 'A-Za-z0-9-')"
            [ -n "$lock_boot" ] || exit 11
            lock_dir="$DATA/mcs-monitor-$lock_boot.lockdir"
            lock_owner_alive() {
                owner_pid="$1"; owner_stamp="$2"
                case "$owner_pid:$owner_stamp" in *[!0-9:]*|:*) return 1;; esac
                [ "$owner_pid" -gt 1 ] && kill -0 "$owner_pid" 2>/dev/null || return 1
                [ "$(proc_start_time "$owner_pid")" = "$owner_stamp" ] || return 1
                tr "\000" " " < "/proc/$owner_pid/cmdline" 2>/dev/null | grep -Fq "fcm-monitor.sh"
            }
            if ! mkdir "$lock_dir" 2>/dev/null; then
                owner_pid="$(cat "$lock_dir/pid" 2>/dev/null)"
                owner_stamp="$(cat "$lock_dir/starttime" 2>/dev/null)"
                if [ -z "$owner_pid" ] || [ -z "$owner_stamp" ]; then
                    sleep 1
                    owner_pid="$(cat "$lock_dir/pid" 2>/dev/null)"
                    owner_stamp="$(cat "$lock_dir/starttime" 2>/dev/null)"
                fi
                if lock_owner_alive "$owner_pid" "$owner_stamp"; then
                    echo "后台正在检查 GMS，请稍后重试" >&2
                    exit 13
                fi
                stale_lock="$lock_dir.stale.$$"
                if mv "$lock_dir" "$stale_lock" 2>/dev/null; then rm -rf "$stale_lock"; fi
                mkdir "$lock_dir" 2>/dev/null || { echo "后台正在检查 GMS，请稍后重试" >&2; exit 13; }
            fi
            lock_dir_pid=
            IFS=' ' read -r lock_dir_pid _ < /proc/self/stat 2>/dev/null || exit 11
            case "$lock_dir_pid" in ''|*[!0-9]*) exit 11;; esac
            echo "$lock_dir_pid" > "$lock_dir/pid"
            proc_start_time "$lock_dir_pid" > "$lock_dir/starttime"
            trap 'clear_lock_owner; rm -f "$lock_dir/pid" "$lock_dir/starttime"; rmdir "$lock_dir" 2>/dev/null || :' EXIT
            trap 'exit 130' HUP INT TERM
            if ! write_lock_owner; then
                echo "无法登记 GMS monitor 进程身份，拒绝启动未受监管的检查" >&2
                exit 14
            fi
            run_monitor_command "$command"
        fi
        ;;
    *) run_monitor_command "$command";;
esac
