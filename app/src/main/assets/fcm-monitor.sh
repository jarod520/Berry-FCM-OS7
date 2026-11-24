#!/system/bin/sh
# BerryFCM APK: kernel GMS-UID socket evidence drives state and recovery; dumps are never runtime inputs.
# Only observes GMS-owned TCP sockets and requests targeted recovery broadcasts; it never
# changes DNS, VPN, proxy, routing, or kills/restarts Google Play services.
set -u

GMS=com.google.android.gms
DATA="${BERRY_FCM_DATA:-/data/adb/berry_fcm_apk}"
STATE="$DATA/mcs-monitor.state"
EVENTS="$DATA/mcs-monitor-events.log"
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
PROC_NET_DIR="${BERRY_PROC_NET_DIR:-/proc/net}"

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
    transport=; remote=; sample_epoch=0; sample_mono=0; last_try_reason=none
    reconnects=0; last_down=0
    down_observed=0; retry_streak=0; outage_hint_mono=0
    unknown_since_mono=0; last_nudge_mono=0
    prev_b=; boot_changed=0
    if [ -f "$STATE" ]; then
        IFS='|' read -r prev_b state conn_key conn_since conn_since_mono last_seen missing_since missing_epoch last_try_mono last_try_epoch attempts last_result last_restore outages transport remote sample_epoch last_try_reason reconnects last_down down_observed retry_streak outage_hint_mono sample_mono unknown_since_mono last_nudge_mono < "$STATE" || :
    fi
    conn_since="$(num "$conn_since")"; conn_since_mono="$(num "$conn_since_mono")"; last_seen="$(num "$last_seen")"
    missing_since="$(num "$missing_since")"; missing_epoch="$(num "$missing_epoch")"
    last_try_mono="$(num "$last_try_mono")"; last_try_epoch="$(num "$last_try_epoch")"
    attempts="$(num "$attempts")"; last_restore="$(num "$last_restore")"
    outages="$(num "$outages")"; sample_epoch="$(num "$sample_epoch")"
    reconnects="$(num "$reconnects")"; last_down="$(num "$last_down")"
    down_observed="$(num "${down_observed:-0}")"; retry_streak="$(num "${retry_streak:-0}")"
    outage_hint_mono="$(num "${outage_hint_mono:-0}")"; sample_mono="$(num "${sample_mono:-0}")"
    unknown_since_mono="$(num "${unknown_since_mono:-0}")"; last_nudge_mono="$(num "${last_nudge_mono:-0}")"
    case "$state" in connected|connecting|disconnected|unknown|never_seen) : ;; *) state=unknown;; esac
    case "$last_result" in none|requested|failed|restored) : ;; *) last_result=none;; esac
    case "$last_try_reason" in none|auto|manual|rescue) : ;; *) last_try_reason=none;; esac
    # An unreadable boot id is not a reboot: keep the stored one.
    [ -n "$b" ] || b="$prev_b"
    if [ -n "$prev_b" ] && [ -n "$b" ] && [ "$prev_b" != "$b" ]; then
        state=never_seen; conn_key=; conn_since=0; conn_since_mono=0; missing_since=0; missing_epoch=0
        last_try_mono=0; transport=; remote=; sample_epoch=0; sample_mono=0; down_observed=0; retry_streak=0; outage_hint_mono=0
        unknown_since_mono=0; last_nudge_mono=0
        : > "$LEARNED_IPS"
        boot_changed=1
    fi
}

save_state() {
    tmp="$STATE.$$"
    if ! printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$b" "$state" "$conn_key" "$conn_since" "$conn_since_mono" "$last_seen" "$missing_since" "$missing_epoch" \
      "$last_try_mono" "$last_try_epoch" "$attempts" "$last_result" "$last_restore" "$outages" \
      "$transport" "$remote" "$sample_epoch" "$last_try_reason" "$reconnects" "$last_down" "$down_observed" "$retry_streak" "$outage_hint_mono" "$sample_mono" "$unknown_since_mono" "$last_nudge_mono" > "$tmp"; then
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

scan_ss() {
    uid="$(gms_uid 2>/dev/null)" || { printf 'unknown||||gms_uid_unavailable\n'; return; }
    command -v "$SS_BIN" >/dev/null 2>&1 || { printf 'unknown||||ss_unavailable\n'; return; }
    # -i adds TCP_INFO (unacked/retrans/lastrcv) where the ss build supports it.
    raw="$("$SS_BIN" -tinpe 2>/dev/null)" || raw=
    if [ -z "$raw" ] || ! printf '%s\n' "$raw" | grep -Eq 'uid:[0-9]+'; then
        raw="$("$SS_BIN" -tnpe 2>/dev/null)" || { printf 'unknown||||ss_failed\n'; return; }
    fi

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
    # Without Root the shell may see only part of the table. Absence of an MCS
    # socket is meaningful only when this snapshot proves ownership is visible,
    # i.e. at least one socket owned by the GMS UID is listed.
    gms_visible=0
    printf '%s\n' "$raw" | grep -Eq "uid:${uid}([^0-9]|\$)" && gms_visible=1
    # A socket is stalled when it has unacked data with >=3 retransmissions, or
    # no data was received for 30 minutes (TCP_INFO). Missing fields never fake it.
    result="$(printf '%s\n' "$raw" | awk -v u="$uid" -v ips="|$ips|" -v ip_count="$ip_count" '
      function normip(v){sub(/:[0-9]+$/, "", v);gsub(/^\[|\]$/, "", v);sub(/^::ffff:/, "", v);return tolower(v)}
      function known(v){return index(ips,"|" normip(v) "|")>0}
      function field_number(name, text, value) {
        if (match(text, name ":[0-9]+")) {
          value=substr(text,RSTART+length(name)+1,RLENGTH-length(name)-1)
          return value+0
        }
        return -1
      }
      function emit(   established, relevant, stalled) {
        if (!current || owner!=u+0) return
        established=(socket_state=="ESTAB" || socket_state=="ESTABLISHED")
        relevant=(port==5228 || port==5229 || port==5230 || (port==443 && known(peer)))
        if (established && relevant) {
          stalled=((unacked>0 && retrans>=3) || last_recv_ms>=1800000)
          if (stalled) {
            if (rank<2) {rank=2;kind="stalled";transport="tcp" port;remote=ip ":" port;bestkey=key}
          } else if (rank<4) {
            rank=4;kind="connected";transport=(port==443?"tcp443":"tcp" port);remote=ip ":" port;bestkey=key
          }
        } else if (!established && relevant && (socket_state=="SYN-SENT" || socket_state=="SYN_SENT")) {
          if (rank<3) {rank=3;kind="connecting";transport="tcp" port;remote=ip ":" port;bestkey=key}
        } else if (established && port==443 && !known(peer)) {
          untrusted=1
        }
      }
      ($1=="ESTAB" || $1=="ESTABLISHED" || $1=="SYN-SENT" || $1=="SYN_SENT") {
        emit()
        current=1; socket_state=$1
        owner=-1; if(match($0,/uid:[0-9]+/)) owner=substr($0,RSTART+4,RLENGTH-4)+0
        peer=$5; port=peer; sub(/^.*:/,"",port); port=port+0
        ip=normip(peer); local=$4
        inode=""; if(match($0,/ino:[0-9]+/)) inode=substr($0,RSTART+4,RLENGTH-4)
        key=local ">" peer "#" inode
        unacked=field_number("unacked",$0); retrans=field_number("retrans",$0); last_recv_ms=field_number("lastrcv",$0)
      }
      current && $1!~/^(ESTAB|ESTABLISHED|SYN-SENT|SYN_SENT)$/ {
        value=field_number("unacked",$0); if (value>=0) unacked=value
        value=field_number("retrans",$0); if (value>=0) retrans=value
        value=field_number("lastrcv",$0); if (value>=0) last_recv_ms=value
      }
      END {
        emit()
        if(rank==4) printf "connected|%s|%s|%s|\n",transport,remote,bestkey
        else if(rank==3) printf "connecting|%s|%s|%s|\n",transport,remote,bestkey
        else if(rank==2) printf "stalled|%s|%s|%s|tcp_info_unacked_retrans\n",transport,remote,bestkey
        else if(untrusted) print "unknown||||unverified_443_no_mtalk_dns"
        else print "absent||||no_fcm_socket_observed"
      }')"
    case "$result" in
      absent\|*)
        if [ "$(id -u 2>/dev/null)" != 0 ] && [ "$gms_visible" != 1 ]; then
            printf 'unknown||||ss_gms_socket_not_visible\n'
            return
        fi;;
    esac
    printf '%s\n' "$result"
}

# Kernel TCP tables carry the owning UID and are readable by the ADB shell on most
# builds, so they back up a redacted or empty ss. Absence is trusted only when the
# tables prove ownership is visible (at least one GMS-UID socket is listed).
scan_proc_net() {
    uid="$(gms_uid 2>/dev/null)" || { printf 'unknown||||gms_uid_unavailable\n'; return; }
    [ -r "$PROC_NET_DIR/tcp" ] || { printf 'unknown||||proc_net_tcp_unreadable\n'; return; }
    for table in "$PROC_NET_DIR/tcp" "$PROC_NET_DIR/tcp6"; do
        [ -r "$table" ] || continue
        awk -v u="$uid" '
          NR > 1 && $8 == u {
            visible=1
            split($3,a,":"); port=toupper(a[2]); st=$4; lp=toupper(substr($2,index($2,":")+1))
            if (port=="146C" || port=="146D" || port=="146E") {
              tp="tcp" (port=="146C"?5228:(port=="146D"?5229:5230))
              if (st=="01" && rank<3) {rank=3; kind="connected"; transport=tp; key=$2 ">" $3 "#" $10}
              else if (st=="02" && rank<1) {rank=1; kind="connecting"; transport=tp; key=$2 ">" $3 "#" $10}
            } else if (port=="01BB" && st=="01") {unverified443=1}
          }
          END {
            if (rank>0) printf "%s|%s||%s|\n",kind,transport,key
            else if (unverified443) print "unknown||||proc_net_443_unverified"
            else if (visible) print "absent||||proc_net_no_mcs_socket"
            else print "unknown||||proc_net_gms_socket_not_visible"
          }' "$table"
    done | awk -F'|' '
      $1=="connected" {connected=$0}
      $1=="connecting" && !connecting {connecting=$0}
      $1=="unknown" && !unknown {unknown=$0}
      $1=="absent" {absent=$0}
      END {if(connected) print connected; else if(connecting) print connecting; else if(absent) print absent; else if(unknown) print unknown; else print "unknown||||proc_net_unavailable"}'
}

scan_sockets() {
    scan_result="$(scan_ss)"
    case "$scan_result" in
      unknown\|\|\|\|ss_unavailable|unknown\|\|\|\|ss_failed|unknown\|\|\|\|ss_uid_metadata_unavailable|unknown\|\|\|\|ss_gms_socket_not_visible)
        proc_result="$(scan_proc_net)"
        case "$proc_result" in unknown\|\|\|\|proc_net_tcp_unreadable|unknown\|\|\|\|gms_uid_unavailable) :;; *) scan_result="$proc_result";; esac;;
    esac
    printf '%s\n' "$scan_result"
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

# Recovery triggers. Each stage is independent: a rejected command falls through to
# the next one at once; an accepted one is followed by a kernel-socket re-sample and
# "connected" ends the sequence. Verified-on-device triggers come first for the shell.
#   MCS_HEARTBEAT / ACTION_HEARTBEAT_NOW / GTALK_HEARTBEAT  heartbeat broadcasts
#   GCM_RECONNECT       reconnect broadcast (not exported on OriginOS 7; tried as a last resort)
#   GCM_SERVICE_START   best-effort explicit start of GMS's own GcmService (unverified)
# Never force-stops/restarts GMS and never alters DNS/VPN/proxy/routing.
recovery_actions() {
    case "$(id -u 2>/dev/null)" in
      0) echo "GCM_RECONNECT MCS_HEARTBEAT ACTION_HEARTBEAT_NOW GTALK_HEARTBEAT GTALK_RECONNECT GMS_INITIALIZE GCM_SERVICE_START";;
      2000) echo "MCS_HEARTBEAT ACTION_HEARTBEAT_NOW GTALK_HEARTBEAT GTALK_RECONNECT GMS_INITIALIZE GCM_RECONNECT GCM_SERVICE_START";;
      *) return 1;;
    esac
}

# Idempotent preparation: lift GMS out of app standby so broadcasts and its network
# are not deferred. Failures are ignored.
prepare_gms_for_recovery() {
    "$AM_BIN" set-inactive --user 0 "$GMS" false >/dev/null 2>&1 || :
    "$AM_BIN" set-standby-bucket --user 0 "$GMS" active >/dev/null 2>&1 || :
    # Shell-UID-safe hardening used by common push-fix tools: Doze whitelist and
    # background-run appops, so heartbeats and the MCS socket are not deferred.
    "$CMD_BIN" deviceidle whitelist "+$GMS" >/dev/null 2>&1 || :
    "$CMD_BIN" appops set "$GMS" RUN_IN_BACKGROUND allow >/dev/null 2>&1 || :
    "$CMD_BIN" appops set "$GMS" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1 || :
}

# Send one trigger; returns 0 when the system accepted it.
send_recovery_action() {
    trigger_label="$1"
    case "$trigger_label" in
      GCM_RECONNECT) trigger_action=com.google.android.intent.action.GCM_RECONNECT;;
      MCS_HEARTBEAT) trigger_action=com.google.android.intent.action.MCS_HEARTBEAT;;
      ACTION_HEARTBEAT_NOW) trigger_action=com.google.android.gms.gcm.ACTION_HEARTBEAT_NOW;;
      GTALK_HEARTBEAT) trigger_action=com.google.android.intent.action.GTALK_HEARTBEAT;;
      GTALK_RECONNECT) trigger_action=com.google.android.intent.action.GTALK_RECONNECT;;
      GMS_INITIALIZE) trigger_action=com.google.android.gms.INITIALIZE;;
      GCM_SERVICE_START) trigger_action=;;
      *) return 1;;
    esac
    if [ "$trigger_label" = GCM_SERVICE_START ]; then
        trigger_reply="$("$AM_BIN" startservice --user 0 -n "$GMS/.gcm.GcmService" 2>&1)"
        trigger_rc=$?
        [ "$trigger_rc" -eq 0 ] && printf '%s\n' "$trigger_reply" | grep -q 'Starting service' &&
            ! printf '%s\n' "$trigger_reply" | grep -qiE 'Error|Exception|not allowed|Permission|not found'
        return $?
    fi
    trigger_reply="$("$AM_BIN" broadcast --user 0 -a "$trigger_action" -p "$GMS" 2>&1)"
    trigger_rc=$?
    [ "$trigger_rc" -eq 0 ] && printf '%s\n' "$trigger_reply" | grep -q 'Broadcast completed:' &&
        ! printf '%s\n' "$trigger_reply" | grep -qiE 'Permission Denial|SecurityException|not allowed|Error:|result=-[0-9]'
}

# After an accepted trigger give GMS up to 5 s to rebuild MCS; return early on a
# connected socket, otherwise the caller moves on to the next trigger.
settle_wait() {
    [ "${BERRY_FCM_TEST_MODE:-0}" != 1 ] || return 0
    settle_i=0
    while [ "$settle_i" -lt 5 ]; do
        sleep 1; settle_i=$((settle_i+1))
        case "$(scan_sockets 2>/dev/null)" in connected\|*) return 0;; esac
    done
    return 0
}

request_reconnect() {
    reason="$1"; nowm="$(num "$(monotime)")"; nowe="$(num "$(now_epoch)")"
    # An explicit user request may run while kernel evidence is unavailable;
    # automatic recovery never acts on unknown evidence.
    case "$state" in
      connecting|disconnected) :;;
      unknown) [ "$reason" = manual ] || { decision=not_disconnected; return 0; };;
      *) decision=not_disconnected; return 0;;
    esac
    interval="$(retry_interval)"
    [ "$reason" = manual ] && interval=60
    if [ "$last_try_mono" -gt 0 ] && [ "$nowm" -ge "$last_try_mono" ] && [ $((nowm-last_try_mono)) -lt "$interval" ]; then
        decision=cooldown
        if [ "$reason" = manual ]; then
            record_event reconnect_skipped "手动恢复未发送：距上次请求不足60秒，剩余 $((interval-nowm+last_try_mono)) 秒"
        fi
        return 0
    fi
    sender_uid="$(id -u 2>/dev/null || echo unknown)"
    actions="$(recovery_actions)" || {
        decision=request_failed; record_event reconnect_failed "执行身份 UID=$sender_uid 不是已验证的 Root/ADB Shell"; save_state; return 0; }
    last_try_mono="$nowm"; last_try_epoch="$nowe"; attempts=$((attempts+1))
    retry_streak=$((retry_streak+1)); last_try_reason="$reason"; last_result=failed
    if ! save_state; then
        decision=state_save_failed
        last_result=failed
        record_event reconnect_aborted "恢复请求前无法持久化退避状态；为避免重复广播，本轮不发送"
        return 0
    fi
    prepare_gms_for_recovery
    sequence_requested=0; sequence_index=0; confirmation_unavailable=0; recovered=0
    for action_label in $actions; do
        sequence_index=$((sequence_index+1))
        if send_recovery_action "$action_label"; then
            sequence_requested=1; last_result=requested
            record_event reconnect_requested "$reason UID=$sender_uid $action_label 已被系统接受（第 $attempts 次，阶段 $sequence_index）；命令返回不代表投递或恢复，等待内核复采"
            if ! save_state; then
                decision=state_save_failed
                record_event reconnect_state_commit_failed "广播已提交但恢复结果状态写入失败；保留请求前已提交的退避锚点"
                return 0
            fi
            settle_wait
            if observe; then
                case "$state" in
                  connected)
                    recovered=1
                    record_event recovery_sequence_recovered "恢复序列第 $sequence_index 阶段后内核复采观察到 MCS TCP 建立；停止后续触发"
                    break
                    ;;
                  connecting|disconnected)
                    record_event recovery_sequence_still_down "恢复序列第 $sequence_index 阶段后仍为 $state；继续下一种触发"
                    ;;
                  *)
                    confirmation_unavailable=1
                    record_event recovery_sequence_unverified "恢复序列第 $sequence_index 阶段后内核证据不可用；不推断断联，继续下一种触发"
                    ;;
                esac
            else
                # observe() may have changed globals before its commit failed:
                # reload the last committed state so no failed sample leaks.
                load_state
                confirmation_unavailable=1
                record_event recovery_confirmation_unavailable "恢复命令 $action_label 后内核复采失败；已恢复最后一次提交的样本，继续下一种触发"
            fi
        else
            record_event reconnect_failed "$reason UID=$sender_uid $action_label exit=$trigger_rc：$(printf '%s' "$trigger_reply" | head -n 1 | cut -c1-80)；未被系统接受，立即尝试下一种触发"
        fi
    done
    if [ "$recovered" = 1 ]; then
        decision=confirmation_recovered
    elif [ "$sequence_requested" = 1 ]; then
        decision=recovery_exhausted
        record_event reconnect_sequence_exhausted "全部触发已执行但内核仍未确认恢复${confirmation_unavailable:+（至少一次复采不可用）}；按退避间隔再次巡检"
    else
        decision=request_failed
        record_event reconnect_sequence_failed "全部触发均未被系统接受；按退避间隔再次巡检"
    fi
    if ! save_state; then
        decision=state_save_failed
        record_event reconnect_state_commit_failed "广播已提交但恢复结果状态写入失败；保留请求前已提交的退避锚点"
    fi
}

# Evidence-unavailable keepalive (the open-source heartbeat-fixer approach). It never
# marks the connection down and never claims recovery: while the kernel socket table
# stays unreadable for 5 minutes it sends the three heartbeat broadcasts at most once
# every 15 minutes. Reconnect broadcasts and service starts stay reserved for confirmed
# outages.
keepalive_nudge() {
    nowm="$(num "$(monotime)")"
    if [ "$unknown_since_mono" -le 0 ] || [ "$nowm" -lt "$unknown_since_mono" ] || [ $((nowm-unknown_since_mono)) -lt 300 ]; then
        decision=sample_unavailable; return 0
    fi
    if [ "$last_nudge_mono" -gt 0 ] && [ "$nowm" -ge "$last_nudge_mono" ] && [ $((nowm-last_nudge_mono)) -lt 900 ]; then
        decision=sample_unavailable; return 0
    fi
    case "$(id -u 2>/dev/null)" in 0|2000) :;; *) decision=sample_unavailable; return 0;; esac
    nudge_accepted=0
    for nudge_label in MCS_HEARTBEAT ACTION_HEARTBEAT_NOW GTALK_HEARTBEAT; do
        if send_recovery_action "$nudge_label"; then nudge_accepted=$((nudge_accepted+1)); fi
    done
    last_nudge_mono="$nowm"
    decision=keepalive_nudged
    record_event keepalive_nudge "内核 Socket 证据连续 $((nowm-unknown_since_mono)) 秒不可用；未判定断联，仅发送心跳保活（被系统接受 ${nudge_accepted}/3）"
    save_state || { decision=state_save_failed; record_event keepalive_state_commit_failed "保活心跳已发送但状态写入失败"; }
}

observe() {
    load_state
    nowm="$(num "$(monotime)")"; nowe="$(num "$(now_epoch)")"
    [ "$nowm" -gt 0 ] && [ "$nowe" -gt 0 ] || return 12
    # Discard pre-migration states whose authority was the legacy native parser.
    legacy_source=
    if [ -f "$EVIDENCE" ]; then IFS='|' read -r legacy_source _ < "$EVIDENCE" || :; fi
    case "$legacy_source" in
      gms|gms_socket_fallback)
        if [ "$state" != unknown ] || [ "$outage_hint_mono" -gt 0 ] || [ "$down_observed" -gt 0 ]; then
            record_event legacy_dump_state_discarded "旧版状态来源不是内核 MCS Socket；清除旧连接/断联计时，重新建立内核证据"
        fi
        state=unknown; conn_key=; conn_since=0; conn_since_mono=0
        missing_since=0; missing_epoch=0; down_observed=0; outage_hint_mono=0
        last_try_mono=0; retry_streak=0
        ;;
      *) :;;
    esac
    previous_down_state="$state"; previous_missing_epoch="$missing_epoch"
    previous_down_observed="$(num "${outage_hint_mono:-0}")"
    [ "$previous_down_observed" -gt 0 ] || previous_down_observed="$(num "${down_observed:-0}")"
    sample_gap=0; sample_gap_age=0
    if [ "$sample_mono" -gt 0 ]; then
        if [ "$nowm" -lt "$sample_mono" ]; then
            sample_gap=1
        elif [ $((nowm-sample_mono)) -gt 90 ]; then
            sample_gap=1; sample_gap_age=$((nowm-sample_mono))
        fi
    elif [ "$sample_epoch" -gt 0 ] && [ "$nowe" -gt "$sample_epoch" ] && [ $((nowe-sample_epoch)) -gt 90 ]; then
        sample_gap=1; sample_gap_age=$((nowe-sample_epoch))
    fi
    if [ "$previous_down_observed" -gt "$nowm" ] || [ "$sample_gap" -eq 1 ]; then
        previous_down_observed=0
        if [ "$sample_gap" -eq 1 ]; then
            record_event sample_gap "距离上次有效内核 Socket 采样约 $sample_gap_age 秒；重置连续性计时并重新采样"
            state=unknown; missing_since=0; missing_epoch=0; conn_since=0; down_observed=0
            unknown_since_mono=0
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
            record_event socket_connected "GMS 已连接（MCS TCP 已建立）"
        ;;
      connecting)
        observed=connecting; source=gms_socket
        new_transport="$socket_transport"; new_remote="$socket_remote"
        if [ "$previous_down_state" != connecting ] || [ "$outage_hint_mono" -le 0 ] || [ "$socket_now" -lt "$outage_hint_mono" ]; then
            down_observed="$socket_now"; outage_hint_mono="$socket_now"
            record_event socket_connecting "GMS 正在连接（MCS TCP 建立中）"
        fi
        previous_down_observed="$outage_hint_mono"
        ;;
      stalled)
        observed=disconnected; source=gms_socket_stalled; tcp_hint=stalled
        new_transport="$socket_transport"; new_remote="$socket_remote"
        if [ "$previous_down_state" != disconnected ] || [ "$outage_hint_mono" -le 0 ]; then
            outage_hint_mono="$socket_now"
            record_event tcp_stalled "内核 TCP_INFO 显示 MCS socket 有未确认数据且连续重传，或超过 30 分钟未收到数据"
        fi
        previous_down_observed="$outage_hint_mono"
        ;;
      absent)
        # scan_sockets reports "absent" only when ownership is provable: Root
        # read the full table, or a GMS-UID-owned socket is visible to the shell.
        observed=disconnected; source=gms_socket_absence; tcp_hint=absent
        if [ "$outage_hint_mono" -le 0 ] || [ "$socket_now" -lt "$outage_hint_mono" ] ||
           [ $((socket_now-outage_hint_mono)) -gt 900 ]; then
            outage_hint_mono="$socket_now"
            record_event tcp_absence_started "GMS 未连接：已读取内核 TCP 表，未发现 MCS TCP"
        fi
        previous_down_observed="$outage_hint_mono"
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
            record_event connection_restored "GMS 连接恢复（MCS TCP 已建立）"
            ;;
          unknown)
            [ "$previous_down_observed" -le 0 ] ||
                record_event connection_observed_after_unknown "已连接：此前样本不可用，本轮重新观察到 MCS TCP"
            ;;
        esac
        current_key="$socket_remote"
        if [ "$state" != connected ] || [ "$conn_key" != "$current_key" ] ||
           [ "$conn_since_mono" -le 0 ] || [ "$nowm" -lt "$conn_since_mono" ] ||
           [ "$sample_mono" -le 0 ] || [ "$nowm" -lt "$sample_mono" ] ||
           [ $((nowm-sample_mono)) -gt 45 ]; then conn_since_mono="$nowm"; fi
        conn_key="$current_key"; state=connected; last_seen="$nowe"; missing_since=0; missing_epoch=0
        down_observed=0; outage_hint_mono=0; last_try_mono=0; retry_streak=0; conn_since=0
        unknown_since_mono=0
        ;;
      connecting|disconnected)
        if [ "$state" != connecting ] && [ "$state" != disconnected ]; then
            missing_since="$nowm"; missing_epoch="$nowe"; down_observed="$nowm"
            [ "$previous_down_state" = connected ] && outages=$((outages+1))
        fi
        [ "$down_observed" -gt 0 ] && [ "$down_observed" -le "$nowm" ] || down_observed="$nowm"
        [ "$outage_hint_mono" -gt 0 ] || outage_hint_mono="$nowm"
        state="$observed"; last_down="$nowe"; conn_key=; conn_since=0; conn_since_mono=0
        unknown_since_mono=0
        ;;
      *)
        state=unknown; conn_key=; missing_since=0; missing_epoch=0; conn_since=0; conn_since_mono=0
        down_observed=0
        [ "$unknown_since_mono" -gt 0 ] && [ "$unknown_since_mono" -le "$nowm" ] || unknown_since_mono="$nowm"
        [ "$outage_hint_mono" -le 0 ] || missing_epoch="$previous_missing_epoch"
        new_transport=; new_remote=
        ;;
    esac
    transport="$new_transport"; remote="$new_remote"; sample_epoch="$nowe"; sample_mono="$nowm"
    save_state || return $?
    write_evidence || return $?
}

write_evidence() {
    tmp="$EVIDENCE.$$"
    if ! printf '%s|%s|%s|%s|%s|%s\n' "$source" "$duration" "$close_code" "$tcp_hint" "$native_reason" "$decision" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if ! mv -f "$tmp" "$EVIDENCE"; then
        rm -f "$tmp"
        return 1
    fi
}

auto_recovery() {
    decision=not_disconnected
    auto_enabled || { decision=disabled; return 0; }
    case "$state" in
      connecting|disconnected) :;;
      unknown)
        [ "${BERRY_AUTO_GATE:-ready}" = ready ] || { decision=network_gate; return 0; }
        keepalive_nudge; return 0;;
      *) return 0;;
    esac
    nowm="$(num "$(monotime)")"
    interval="$(retry_interval)"
    if [ "$last_try_mono" -gt 0 ] && [ "$nowm" -ge "$last_try_mono" ] && [ $((nowm-last_try_mono)) -lt "$interval" ]; then
        decision=cooldown; return 0
    fi
    required=60
    [ "$state" = disconnected ] && required=15
    [ "$source" = gms_socket_absence ] && required=45
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
        record_event recovery_confirmed "两次内核 Socket 采样均确认 $state，进入分阶段恢复"
        request_reconnect auto
    else
        decision=confirmation_changed
        record_event recovery_confirmation_changed "二次采样状态改变或不可用；不将未知判为断联，不发送本轮恢复"
    fi
}
status_json() {
    load_state
    nowe="$(num "$(now_epoch)")"; nowm="$(num "$(monotime)")"; age=-1
    if [ "$sample_mono" -gt 0 ] && [ "$nowm" -ge "$sample_mono" ]; then
        age=$((nowm-sample_mono))
    elif [ "$sample_mono" -le 0 ] && [ "$sample_epoch" -gt 0 ] && [ "$nowe" -ge "$sample_epoch" ]; then
        age=$((nowe-sample_epoch))
    fi
    source=unavailable; duration=-1; close_code=; tcp_hint=none; native_reason=not_used; decision=not_evaluated
    if [ -f "$EVIDENCE" ]; then IFS='|' read -r source duration close_code tcp_hint native_reason decision < "$EVIDENCE" || :; fi
    case "$source" in
      gms_socket|gms_socket_absence|gms_socket_stalled) :;;
      *) state=unknown; source=unavailable; duration=-1; close_code=; tcp_hint=unknown; native_reason=not_used; decision=sample_unavailable;;
    esac
    case "${decision:-}" in not_evaluated|not_disconnected|sample_unavailable|disabled|network_gate|cooldown|requested|request_failed|recovery_exhausted|keepalive_nudged|waiting_duration|confirmation_changed|confirmation_recovered|state_save_failed) :;; *) decision=not_evaluated;; esac
    case "$native_reason" in not_used) :;; *) native_reason=not_used;; esac
    case "$duration" in -1) :;; *) is_uint "$duration" || duration=-1;; esac
    if [ "$source" != unavailable ]; then [ "$age" -ge 0 ] && [ "$age" -le 90 ] || state=stale; fi
    # Never present stale duration as live and never extrapolate past the sample.
    connected=0; missing=0
    [ "$state" = connected ] && [ "$duration" -ge 0 ] && connected="$duration"
    { [ "$state" = connecting ] || [ "$state" = disconnected ]; } && [ "$duration" -ge 0 ] && missing="$duration"
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
    printf '{"fcm_state":"%s","fcm_source":"%s","fcm_transport":"%s","fcm_remote":"%s","fcm_connection_since":%s,"fcm_connected_seconds":%s,"fcm_disconnect_since":%s,"fcm_missing_seconds":%s,"fcm_native_duration":%s,"fcm_observed_up_seconds":%s,"fcm_last_close_code":"%s","fcm_tcp_hint":"%s","fcm_last_seen":%s,"fcm_last_restore":%s,"fcm_last_try":%s,"fcm_last_result":"%s","fcm_attempts":%s,"fcm_sample_time":%s,"fcm_sample_age_seconds":%s,"fcm_native_reason":"%s","fcm_auto":%s,"fcm_auto_gate":"%s","fcm_retry_in":%s,"fcm_retry_streak":%s,"fcm_observed_down_seconds":%s,"fcm_recovery_decision":"%s"}\n' \
      "$state" "$source" "$transport" "$remote" "$conn_since" "$connected" "$last_down" "$missing" "$duration" "$observed_up" "$close_code" "$tcp_hint" "$last_seen" "$last_restore" "$last_try_epoch" "$last_result" "$attempts" "$sample_epoch" "$age" "$native_reason" "$auto" "$gate" "$retry_in" "$retry_streak" "$observed_seconds" "$decision"
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
        elif [ "$source" != gms_socket ] && [ "$source" != gms_socket_absence ] && [ "$source" != gms_socket_stalled ]; then
            decision=not_disconnected
        elif [ "$state" = connecting ] || [ "$state" = disconnected ]; then
            [ "${BERRY_FCM_TEST_MODE:-0}" = 1 ] || sleep 2
            observe || exit $?
            if { [ "$source" = gms_socket ] || [ "$source" = gms_socket_absence ] || [ "$source" = gms_socket_stalled ]; } &&
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
        elif [ "$state" = unknown ]; then
            record_event manual_reconnect_unverified '内核 Socket 证据不可用；按用户手动请求执行恢复序列，不推断断联'
            request_reconnect manual
        else
            decision=not_disconnected
            record_event reconnect_skipped 'MCS TCP 已建立；未发送手动重连'
        fi
        write_evidence
        ;;
    events)
        [ -f "$EVENTS" ] && tail -n 80 "$EVENTS" || :
        ;;
    reset-history)
        : > "$EVENTS"; echo 'FCM 事件历史已清空（连接状态未更改）'
        ;;
    *) echo 'status|snapshot|monitor|rescue|reconnect|events|reset-history' >&2; exit 2;;
esac
