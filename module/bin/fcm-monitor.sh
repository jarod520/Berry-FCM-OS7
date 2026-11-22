#!/system/bin/sh
# BerryFCM KernelSU (UID 0): native GMS MCS state is primary; UID-owned TCP is fallback evidence.
# Only observes GMS-owned TCP sockets and requests targeted recovery broadcasts; it never
# changes DNS, VPN, proxy, routing, or force-stops Google Play services.
set -u

GMS=com.google.android.gms
DATA="${BERRY_FCM_DATA:-/data/adb/berry_fcm_ksu}"
STATE="$DATA/mcs-monitor.state"
EVENTS="$DATA/mcs-monitor-events.log"
NATIVE_EVENTS="$DATA/mcs-native-events.log"
EVIDENCE="$DATA/mcs-evidence"
DNS_IPS="$DATA/mcs-mtalk-dns-ips.txt"
LEARNED_IPS="$DATA/mcs-mtalk-learned-ips.txt"
DNS_TIME="$DATA/mcs-mtalk-dns-time"
NATIVE_HINT="$DATA/mcs-native-hint"
NATIVE_RETRY_TIME="$DATA/mcs-native-retry-time"
NATIVE_POLL_TIME="$DATA/mcs-native-poll-time"
LOCK_OWNER="$DATA/mcs-monitor.lock.owner"
lock_owner_stamp=
SS_BIN="${BERRY_SS_BIN:-ss}"
PROC_NET_DIR="${BERRY_PROC_NET_DIR:-/proc/net}"
CMD_BIN="${BERRY_CMD_BIN:-cmd}"
PM_BIN="${BERRY_PM_BIN:-pm}"
DUMPSYS_BIN="${BERRY_DUMPSYS_BIN:-dumpsys}"
AM_BIN="${BERRY_AM_BIN:-am}"
if [ -x /system/bin/dumpsys ] && [ -z "${BERRY_DUMPSYS_BIN:-}" ]; then DUMPSYS_BIN=/system/bin/dumpsys; fi
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
write_lock_owner() {
    lock_owner_pid=
    IFS=' ' read -r lock_owner_pid _ < /proc/self/stat 2>/dev/null || return 1
    case "$lock_owner_pid" in ''|*[!0-9]*) return 1;; esac
    lock_owner_stamp="$(proc_start_time "$lock_owner_pid")"
    [ -n "$lock_owner_stamp" ] || return 1
    printf "%s %s\n" "$lock_owner_pid" "$lock_owner_stamp" > "$LOCK_OWNER.tmp.$lock_owner_pid" &&
        mv -f "$LOCK_OWNER.tmp.$lock_owner_pid" "$LOCK_OWNER"
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
    transport=; remote=; sample_epoch=0; last_try_reason=none
    reconnects=0; last_down=0
    down_observed=0; retry_streak=0; outage_hint_mono=0
    native_timer_duration=0; native_timer_since=0; native_timer_last_request=0; native_timer_key=
    prev_b=
    if [ -f "$STATE" ]; then
        IFS='|' read -r prev_b state conn_key conn_since conn_since_mono last_seen missing_since missing_epoch last_try_mono last_try_epoch attempts last_result last_restore outages transport remote sample_epoch last_try_reason reconnects last_down down_observed retry_streak outage_hint_mono native_timer_duration native_timer_since native_timer_last_request native_timer_key < "$STATE" || :
    fi
    conn_since="$(num "$conn_since")"; conn_since_mono="$(num "$conn_since_mono")"; last_seen="$(num "$last_seen")"
    missing_since="$(num "$missing_since")"; missing_epoch="$(num "$missing_epoch")"
    last_try_mono="$(num "$last_try_mono")"; last_try_epoch="$(num "$last_try_epoch")"
    attempts="$(num "$attempts")"; last_restore="$(num "$last_restore")"
    outages="$(num "$outages")"; sample_epoch="$(num "$sample_epoch")"
    reconnects="$(num "$reconnects")"; last_down="$(num "$last_down")"
    down_observed="$(num "${down_observed:-0}")"; retry_streak="$(num "${retry_streak:-0}")"
    outage_hint_mono="$(num "${outage_hint_mono:-0}")"
    native_timer_duration="$(num "${native_timer_duration:-0}")"
    native_timer_since="$(num "${native_timer_since:-0}")"
    native_timer_last_request="$(num "${native_timer_last_request:-0}")"
    case "$state" in connected|connecting|disconnected|unknown|never_seen) : ;; *) state=unknown;; esac
    case "$last_result" in none|requested|failed|restored) : ;; *) last_result=none;; esac
    case "$last_try_reason" in none|auto|manual|rescue|stalled_timer) : ;; *) last_try_reason=none;; esac
    if [ -n "$prev_b" ] && [ "$prev_b" != "$b" ]; then
        state=never_seen; conn_key=; conn_since=0; conn_since_mono=0; missing_since=0; missing_epoch=0
        last_try_mono=0; transport=; remote=; sample_epoch=0; down_observed=0; retry_streak=0; outage_hint_mono=0
        native_timer_duration=0; native_timer_since=0; native_timer_last_request=0; native_timer_key=
        : > "$LEARNED_IPS"
        rm -f "$NATIVE_HINT"
        record_event reboot '设备重启：清除上一启动周期的连接计时，保留历史事件'
    fi
}

save_state() {
    tmp="$STATE.$$"
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$b" "$state" "$conn_key" "$conn_since" "$conn_since_mono" "$last_seen" "$missing_since" "$missing_epoch" \
      "$last_try_mono" "$last_try_epoch" "$attempts" "$last_result" "$last_restore" "$outages" \
      "$transport" "$remote" "$sample_epoch" "$last_try_reason" "$reconnects" "$last_down" "$down_observed" "$retry_streak" "$outage_hint_mono" \
      "$native_timer_duration" "$native_timer_since" "$native_timer_last_request" "$native_timer_key" > "$tmp" && mv -f "$tmp" "$STATE"
}

update_native_timer_tracking() {
    # Keep the last native timer anchor between 20-second socket samples.
    # The next scheduled native poll will validate or reset it.
    if [ "$source" = gms_socket ] && [ "$state" = connected ] && [ "$native_timer_since" -gt 0 ]; then
        return 0
    fi
    timer_now="$(num "$(monotime)")"
    timer_key="${remote:-$transport}"
    if [ "$source" = gms ] && [ "$state" = connected ] && is_uint "${duration:-}" &&
       [ "$duration" -gt 0 ] && [ -n "$timer_key" ]; then
        if [ "$native_timer_since" -le 0 ] || [ "$timer_now" -lt "$native_timer_since" ] ||
           [ "$native_timer_key" != "$timer_key" ] || [ "$duration" -ne "$native_timer_duration" ]; then
            native_timer_duration="$duration"
            native_timer_since="$timer_now"
            native_timer_last_request=0
            native_timer_key="$timer_key"
        fi
    else
        native_timer_duration=0
        native_timer_since=0
        native_timer_last_request=0
        native_timer_key=
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
    [ "$old" -gt 0 ] && [ "$now" -ge "$old" ] && [ $((now-old)) -lt 600 ] && return 0
    tmp="$DNS_IPS.$$"; : > "$tmp"
    for host in mtalk.google.com alt1-mtalk.google.com; do
        if [ -x /system/bin/toybox ]; then
            /system/bin/toybox timeout -k 1 3 nslookup "$host" 2>/dev/null
        elif command -v timeout >/dev/null 2>&1; then
            timeout 3 nslookup "$host" 2>/dev/null
        else
            continue
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

# Current state only: do not match historical "Connected" or "Connecting"
# lines. GMS dump may contain private IDs and application data; persist only
# the selected fields and connection lifecycle events.
parse_mcs() {
    awk '
      function sec(v, a,n,i,r) {
        sub(/\/.*/, "", v); n=split(v,a,":")
        if(n<2 || n>3) return -1
        r=0; for(i=1;i<=n;i++){if(a[i]!~/^[0-9]+$/ || (i>1 && a[i]+0>=60))return -1; r=r*60+a[i]}
        return r
      }
      function endpoint(v) {return v ~ /^[][A-Za-z0-9.\/:_-]+$/ ? v : ""}
      {
        sub(/\r$/, ""); line=$0; sub(/^[[:space:]]+/, "",line); sub(/[[:space:]]+$/, "",line)
        # GMS headings vary. When no native heading exists, accept exact
        # current-state fields only with corroborating timing/stream metadata.
        if(line~/^DeviceID:/ || line~/^Direct boot mode /){
          if(header && state!=""){done=1;next}
          header=1;next
        }
        if(line~/^SERVICE /){
          if(!service_seen){
            service_seen=1
            state=""; remote=""; port=""; err=""; ct=""; dt=""
            has_ct=0; has_dt=0; has_stream=0
            explicit_status=0; explicit_client_status=0
            conflict=0; header=0; done=0
          }
          scoped=(line~/^SERVICE com\.google\.android\.gms\/(\.gcm\.GcmService|com\.google\.android\.gms\.gcm\.GcmService)([[:space:]]|$)/)
          next
        }
        # Once ActivityManager exposes service blocks, never borrow a state
        # field from another service. Legacy dumps without SERVICE
        # headings retain their existing DeviceID/current-field parsing.
        if(service_seen && !scoped) next
        if(done) next
        if(line~/^[0-9][0-9]-[0-9][0-9] [0-9][0-9]:/){done=1;next}
        if(line~/^connected=/){
          v=line;sub(/^connected=/,"",v);n=split(v,a,",port=")
          if(n==2 && endpoint(a[1])!="" && a[2]~/^[0-9]+$/ && a[2]+0>0 && a[2]+0<=65535){
            if(state!="" && state!="connected") conflict=1
            state="connected"; remote=a[1] ":" a[2]; port=a[2]
          }
        } else if(line~/^connecting=/){
          v=line;sub(/^connecting=/,"",v)
          if(endpoint(v)!="" && v~/:[0-9]+$/){
            if(state=="connected") conflict=1
            state="connecting"; remote=v; port=v;sub(/^.*:/,"",port)
          }
        } else if(line~/^pending=/ && line~/,host=/){
          v=line;sub(/^.*,host=/,"",v)
          if(endpoint(v)!="" && v~/:[0-9]+$/){
            if(state=="connected") conflict=1
            if(state!="connecting"){
              state="disconnected"; remote=endpoint(v);port=v;sub(/^.*:/,"",port)
            }
          }
        } else if(line=="Server: Connected" && (header || scoped)){
          if(state!="" && state!="connected") conflict=1
          state="connected"; explicit_status=1
        } else if((line=="Is client connected: true" || line=="Is client connected: false") && (header || scoped)){
          client_state=(line=="Is client connected: true" ? "connected" : "disconnected")
          if(state!="" && state!=client_state) conflict=1
          state=client_state; explicit_status=1; explicit_client_status=1
        } else if((line=="Not connected" || line=="Server: Not connected") && (header || scoped)){
          if(line=="Server: Not connected") explicit_status=1
          if(state=="connected") conflict=1
          if(state!="connecting") state="disconnected"
        } else if(line=="Connecting" && state=="" && (header || scoped)){state="connecting"}
        else if(line=="Disabled" && (header || scoped)){state="unknown";done=1}
        else if(line~/^connectTime=/){v=line;sub(/^connectTime=/,"",v);ct=sec(v);has_ct=(ct>=0)}
        else if(line~/^disconnectTime=/){v=line;sub(/^disconnectTime=/,"",v);dt=sec(v);has_dt=(dt>=0)}
        else if(line~/^streamId=/){
          if(line~/^streamId=[0-9]+\/[0-9]+(,|$)/) has_stream=1
          n=split(line,a,",")
          for(i=1;i<=n;i++){
            sub(/^[[:space:]]+/,"",a[i])
            if(a[i]~/^lastConnectionErrorCode=[A-Za-z0-9_]+$/){
              err=a[i];sub(/^lastConnectionErrorCode=/,"",err)
            }
          }
        } else if(line~/^lastConnectionErrorCode=[A-Za-z0-9_]+$/){
          err=line;sub(/^lastConnectionErrorCode=/,"",err)
        }
      }
      END {
        corroborated=(state=="connected" ? has_ct : has_dt)
        if(conflict || state=="" || state=="unknown" ||
          (!explicit_status && !header && !corroborated && !has_stream) ||
          (!explicit_status && !header && remote=="" && !corroborated)){
          detail=(conflict ? "conflicting_state" : (state=="" ? "no_current_state" : (state=="unknown" ? "disabled_or_unknown" : "missing_metadata")))
          print "unknown||||-1||" detail;exit
        }
        if((state=="connected" && has_dt && !has_ct) ||
           (state!="connected" && has_ct && !has_dt && !explicit_client_status)){
          print "unknown||||-1||inconsistent_timing";exit
        }
        if(port!~/^[0-9]+$/ || port+0<1 || port+0>65535)port=""
        duration=-1
        if(state=="connected" && ct!="")duration=ct
        if((state=="connecting" || state=="disconnected") && dt!="")duration=dt
        printf "%s|%s|%s|%s|%d|%s\n",state,(port==""?"":"tcp"port),remote,"gms",duration,err
      }'
}

dump_state_shape() {
    # Keep status field spelling and order without recording endpoint values or identifiers.
    awk '
      {
        line=$0
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        lower=tolower(line)
        if (!history && line ~ /^[0-9][0-9]-[0-9][0-9] [0-9][0-9]:/) history=NR
        if (!heading && line ~ /^(DeviceID:|Direct boot mode )/) heading=NR
        if (lower ~ /^(not connected|connected|connecting|disconnected|disabled)$/) {
          field=line
        } else if (match(lower, /^(is client connected|server([ _-]status)?|mcs[ _-]?(state|status)|connection[ _-]?(state|status)|state|status|connected|connecting|pending|connecttime|disconnecttime|time (dis)?connected)[[:space:]]*[:=]/)) {
          field=substr(line,1,RLENGTH)
          value=substr(lower,RLENGTH+1)
          sub(/^[[:space:]]+/, "", value)
          if (value ~ /^(not connected|connected|connecting|disconnected|pending|disabled|true|false)$/)
            field=field " " value
          else
            field=field " <redacted>"
        } else next
        if (!seen[field]++ && ++fields <= 3) detail=detail " " NR ":" field
      }
      END {
        printf "lines=%d heading=%d history=%d%s", NR, heading, history, detail
        if (fields > 3) printf " more=%d", fields-3
      }'
}

import_native_events() {
    # Preserve exact event timestamps (device local time, no invented year).
    # A Close event is a socket/MCS close, not necessarily a distinct outage:
    # simultaneous Wi-Fi/cellular and fallback attempts can produce several.
    tmp="$NATIVE_EVENTS.$$"
    { [ ! -f "$NATIVE_EVENTS" ] || cat "$NATIVE_EVENTS"
      printf '%s\n' "$1" | awk '
        {
          sub(/\r$/, ""); sub(/^[[:space:]]+/, "")
          if($0 !~ /^[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+ net=-?[0-9]+: /) next
          stamp=$1" "$2; msg=$0;sub(/^[^ ]+ [^ ]+ /,"",msg)
          if(msg~/^net=-?[0-9]+: Close err:[0-9]+([[:space:]]|$)/)kind="gms_close"
          else if(msg~/^net=-?[0-9]+: Connected[[:space:]]*$/)kind="gms_connected"
          else if(msg~/^net=-?[0-9]+: Failed connection err:[0-9]+/)kind="gms_failed"
          else if(msg~/^net=-?[0-9]+: Connecting using McsConnection/ && (msg~/WiFi\(/ || msg~/Cell\(/)) {
            kind="gms_network_attempt"
            msg=(msg~/WiFi\(/ ? "WiFi" : "Cell") " connection attempt; " (msg~/FALLBACK_ALTERNATIVE_HOSTPORT/ ? "fallback" : "primary")
          }
          else if(msg~/^net=-?[0-9]+: Heartbeat alarm delay: [0-9]+ ms$/)kind="gms_heartbeat_delay"
          else if(msg~/^net=-?[0-9]+: Reconnect alarm delay: [0-9]+ ms$/)kind="gms_reconnect_delay"
          else next
          gsub(/[|]/," ",msg)
          print stamp "|" kind "|" substr(msg,1,160)
        }'
    } | awk 'NF && !seen[$0]++' | tail -n 600 > "$tmp" && mv -f "$tmp" "$NATIVE_EVENTS"
    native_hint="$(printf '%s\n' "$1" | awk '
      {
        sub(/\r$/, ""); sub(/^[[:space:]]+/, "")
        if($0 !~ /^[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+ net=-?[0-9]+: /) next
        stamp=$1" "$2; msg=$0; sub(/^[^ ]+ [^ ]+ /,"",msg)
        if(msg~/^net=-?[0-9]+: Close err:[0-9]+([[:space:]]|$)/)kind="gms_close"
        else if(msg~/^net=-?[0-9]+: Connected[[:space:]]*$/)kind="gms_connected"
        else next
        token=stamp "|" kind
      }
      END {print token}')"
    if [ -n "$native_hint" ]; then
        old_hint="$(awk -F'|' 'NF>=3 {print $1 "|" $2}' "$NATIVE_HINT" 2>/dev/null)"
        if [ "$native_hint" != "$old_hint" ]; then
            hint_stamp="$(printf '%s' "$native_hint" | cut -d'|' -f1)"
            hint_kind="$(printf '%s' "$native_hint" | cut -d'|' -f2)"
            printf '%s|%s|%s\n' "$hint_stamp" "$hint_kind" "$(num "$(monotime)")" > "$NATIVE_HINT.tmp" &&
                mv -f "$NATIVE_HINT.tmp" "$NATIVE_HINT"
        fi
    fi
}

is_gms_stopped() {
    line="$("$DUMPSYS_BIN" -t 3 package "$GMS" 2>/dev/null | grep -E '^[[:space:]]*User 0:[[:space:]]+.*stopped=' | head -n 1)"
    case " $line " in *' stopped=false '*) echo 0;; *' stopped=true '*) echo 1;; *) echo -1;; esac
}

auto_enabled() {
    [ "$(cat "$DATA/enabled" 2>/dev/null)" = 1 ]
}

retry_interval() {
    case "$retry_streak" in 0) echo 30;; 1) echo 60;; 2) echo 120;; *) echo 180;; esac
}

# A down/absence sample remains useful for at most 15 minutes. Root can see the
# GMS UID's dedicated MCS TCP socket even when dumpsys returns only a wrapper.
# A fresh MCS socket means connected/connecting; repeated socket absence means
# disconnected. A single absence sample never creates an outage.
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
    [ "$socket_down_age" -ge 30 ]
}

native_close_fallback_ready() {
    [ -f "$NATIVE_HINT" ] || return 1
    IFS='|' read -r native_hint_stamp native_hint_kind native_hint_mono < "$NATIVE_HINT" || return 1
    [ "$native_hint_kind" = gms_close ] || return 1
    native_hint_now="$(num "$(monotime)")"
    native_hint_mono="$(num "$native_hint_mono")"
    [ "$native_hint_mono" -gt 0 ] && [ "$native_hint_now" -ge "$native_hint_mono" ] || return 1
    native_hint_age=$((native_hint_now-native_hint_mono))
    [ "$native_hint_age" -ge 30 ] && [ "$native_hint_age" -le 900 ]
}

promote_socket_fallback() {
    nowm="$(num "$(monotime)")"; nowe="$(num "$(now_epoch)")"
    state=disconnected; source=gms_socket_fallback; duration=-1; close_code=
    transport=; remote=; conn_key=; conn_since=0; conn_since_mono=0
    missing_since="$nowm"; missing_epoch="$nowe"; last_down="$nowe"; down_observed="$nowm"
    outage_hint_mono="$nowm"
    record_event recovery_socket_confirmed "GMS 原生字段暂缺；UID0 连续未观察到 GMS MCS TCP（证据年龄 ${socket_down_age} 秒）；按断联继续恢复"
}

request_reconnect() {
    reason="$1"; nowm="$(num "$(monotime)")"; nowe="$(num "$(now_epoch)")"
    if [ "$reason" = stalled_timer ]; then
        [ "$state" = connected ] || { decision=not_disconnected; return 0; }
    else
        case "$state" in connecting|disconnected) :;; *) decision=not_disconnected; return 0;; esac
    fi
    interval="$(retry_interval)"
    [ "$reason" != manual ] || interval=60
    [ "$reason" != stalled_timer ] || interval=300
    if [ "$last_try_mono" -gt 0 ] && [ "$nowm" -ge "$last_try_mono" ] && [ $((nowm-last_try_mono)) -lt "$interval" ]; then
        decision=cooldown
        if [ "$reason" = manual ]; then
            record_event reconnect_skipped "手动恢复未发送：距上次请求尚未达到退避间隔，剩余 $((interval-nowm+last_try_mono)) 秒"
        fi
        return 0
    fi
    case "$reason" in auto|stalled_timer) auto_enabled || { decision=disabled; return 0; };; esac
    if [ "$reason" = stalled_timer ]; then
        native_timer_last_request="$nowm"
        save_state || return $?
    fi
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
    force_native_poll="${1:-0}"
    load_state
    nowm="$(num "$(monotime)")"; nowe="$(num "$(now_epoch)")"
    [ "$nowm" -gt 0 ] && [ "$nowe" -gt 0 ] || return 12
    # Keep the previous observation only as a hint across a suspend gap.
    # Never represent that gap as proven continuous downtime.
    previous_down_observed=0; previous_down_state="$state"; previous_missing_epoch="$missing_epoch"
    # An unknown sample may retain a prior down observation as a hint, never as
    # proof of continuous downtime. Fresh native down evidence is required again.
    case "$state" in
      connecting|disconnected|unknown)
        previous_down_observed="$outage_hint_mono"
        # Migrate the previous on-disk schema without losing a down sample.
        [ "$previous_down_observed" -gt 0 ] || previous_down_observed="$down_observed"
        ;;
    esac
    if [ "$previous_down_observed" -gt "$nowm" ]; then
        previous_down_observed=0
    fi
    # Keep continuous absence evidence regardless of total outage length.
    # A real sampling gap, not an arbitrary 15-minute age cap, resets it.
    if [ "$sample_epoch" -gt 0 ] && [ "$nowe" -gt "$sample_epoch" ] && [ $((nowe-sample_epoch)) -gt 90 ]; then
        previous_down_observed=0
    fi
    outage_hint_mono="$previous_down_observed"
    previous_native_reason=
    if [ -f "$EVIDENCE" ]; then
        IFS='|' read -r old_source old_duration old_close old_tcp previous_native_reason old_decision < "$EVIDENCE" || :
    fi
    decision=not_evaluated
    gap_detected=0
    if [ "$sample_epoch" -gt 0 ] && [ "$nowe" -gt "$sample_epoch" ] && [ $((nowe-sample_epoch)) -gt 90 ]; then
        gap_detected=1
        record_event sample_gap "距离上次有效采样 $((nowe-sample_epoch)) 秒；空档内没有状态样本，现重新读取 Google 状态"
        state=unknown; missing_since=0; missing_epoch=0; conn_since=0; down_observed=0
    fi
    # Socket ownership is sampled every patrol cycle; the more expensive native
    # GMS dump is refreshed at most once per minute unless an explicit check or
    # a two-sample recovery confirmation requires fresh native evidence.
    native_poll_last="$(num "$(cat "$NATIVE_POLL_TIME" 2>/dev/null)")"
    native_poll_due=0
    if [ "$force_native_poll" = force_native ] || [ "${BERRY_FCM_TEST_MODE:-0}" = 1 ] ||
       [ "$native_poll_last" -le 0 ] || [ "$nowm" -lt "$native_poll_last" ] ||
       [ $((nowm-native_poll_last)) -ge 60 ]; then
        native_poll_due=1
    fi
    socket="$(scan_sockets)"
    if [ "$native_poll_due" = 1 ]; then
        dump="$("$DUMPSYS_BIN" -t 5 activity service "$GMS/.gcm.GcmService" 2>&1)"
        dump_rc=$?
        native_reason=none
        if printf '%s\n' "$dump" | grep -qiE 'Permission Denial|SecurityException|Permission denied'; then
            native_reason=permission_denied
        elif printf '%s\n' "$dump" | grep -qiE 'DUMP TIMEOUT|dump timed out|dumpsys.*timed out'; then
            native_reason=timeout
        elif printf '%s\n' "$dump" | grep -qiE 'No services match|No service found'; then
            native_reason=service_unavailable
        elif [ "$dump_rc" -ne 0 ]; then
            native_reason=dump_failed
        elif [ -z "$dump" ]; then
            native_reason=empty
        fi
        if [ "$native_reason" = none ]; then
            result="$(printf '%s\n' "$dump" | parse_mcs)"
            # Keep native lifecycle history even if the current-state parser rejects
            # an otherwise successful dump. Historical Close alone never authorizes recovery.
            import_native_events "$dump"
        else
            result='unknown||||-1|'
        fi
        printf '%s\n' "$nowm" > "$NATIVE_POLL_TIME.tmp" &&
            mv -f "$NATIVE_POLL_TIME.tmp" "$NATIVE_POLL_TIME"
    else
        dump=
        dump_rc=0
        native_reason=not_polled
        retry_rc=not_due
        result='unknown||||-1|native_poll_deferred'
    fi
    IFS='|' read -r observed new_transport new_remote source duration close_code parse_detail <<EOF_RESULT
$result
EOF_RESULT
    # A successful service command can return only ActivityManager wrapper lines.
    # Retry at most once per 60 seconds; repeated wrapper-only dumps must not double
    # the native dump cost on every 20-second patrol cycle.
    if [ "$native_poll_due" = 1 ]; then
        retry_rc=none
        retry_last="$(num "$(cat "$NATIVE_RETRY_TIME" 2>/dev/null)")"
        retry_due=0
        if [ "$retry_last" -le 0 ] || [ "$nowm" -lt "$retry_last" ] ||
           [ $((nowm-retry_last)) -ge 60 ]; then
            retry_due=1
        fi
        if [ "$native_reason" = none ] && [ "$parse_detail" = no_current_state ] && [ "$retry_due" = 1 ]; then
            printf '%s\n' "$nowm" > "$NATIVE_RETRY_TIME.tmp" &&
                mv -f "$NATIVE_RETRY_TIME.tmp" "$NATIVE_RETRY_TIME"
            [ "${BERRY_FCM_TEST_MODE:-0}" = 1 ] || sleep 1
            retry_dump="$("$DUMPSYS_BIN" -t 2 activity service "$GMS/.gcm.GcmService" 2>&1)"
            retry_rc=$?
            if [ "$retry_rc" -eq 0 ] &&
               ! printf '%s\n' "$retry_dump" | grep -qiE 'Permission Denial|SecurityException|Permission denied|DUMP TIMEOUT|dump timed out|dumpsys.*timed out|No services match|No service found'; then
                retry_result="$(printf '%s\n' "$retry_dump" | parse_mcs)"
                case "$retry_result" in
                  connected\|*|connecting\|*|disconnected\|*)
                    IFS='|' read -r observed new_transport new_remote source duration close_code parse_detail <<EOF_RETRY
$retry_result
EOF_RETRY
                    import_native_events "$retry_dump"
                    record_event sample_retry "first=no_current_state retry_rc=$retry_rc state=$observed"
                    ;;
                esac
            fi
        fi
    fi
    tcp_hint=none
    if [ "$observed" = unknown ]; then
        [ "$native_reason" != none ] || native_reason=unrecognized
        if [ "$native_reason" = service_unavailable ] && [ "$(is_gms_stopped)" = 1 ]; then native_reason=gms_stopped; fi
        # Root-visible GMS UID MCS sockets resolve the state when native state
        # is unavailable or this cycle intentionally skips dumpsys. Only exact
        # MCS ports or known mtalk IPs count, never arbitrary GMS HTTPS traffic.
        IFS='|' read -r socket_state socket_transport socket_remote socket_key socket_reason <<EOF_SOCKET
$socket
EOF_SOCKET
        tcp_hint="$socket_state"
        case "$tcp_hint" in connected) tcp_hint=established;; connecting|absent|unknown) :;; *) tcp_hint=unknown;; esac
        source=unavailable; duration=-1; close_code=
        case "$tcp_hint" in
          unknown|absent)
            if [ "$previous_down_state" != unknown ] ||
               [ "$previous_native_reason" != "$native_reason" ]; then
                record_event sample_unknown "reason=$native_reason parser=${parse_detail:-none} tcp=$tcp_hint prior_down=$previous_down_observed dump_rc=$dump_rc retry_rc=$retry_rc"
            fi
            ;;
        esac
        if [ "$native_poll_due" = 1 ]; then
            dump_shape="parser=${parse_detail:-none} rc=$dump_rc $(printf '%s' "$dump" | dump_state_shape)"
            dump_shape="$(printf '%s' "$dump_shape" | cut -c1-220)"
            previous_shape="$(awk -F '|' '$2=="sample_dump" { shape=$3 } END { print shape }' "$EVENTS" 2>/dev/null || :)"
            if [ "$previous_down_state" != unknown ] || [ "$dump_shape" != "$previous_shape" ]; then
                record_event sample_dump "$dump_shape"
            fi
        fi
        socket_now="$(num "$(monotime)")"
        case "$tcp_hint" in
          established)
            observed=connected; source=gms_socket
            new_transport="$socket_transport"; new_remote="$socket_remote"
            previous_down_observed=0; outage_hint_mono=0
            [ "$previous_down_state" = connected ] ||
                record_event socket_connected '本轮原生状态字段未提供；UID0 已观察到 GMS MCS TCP 建立'
            ;;
          connecting)
            observed=connecting; source=gms_socket
            new_transport="$socket_transport"; new_remote="$socket_remote"
            # Preserve the start of one continuous SYN-SENT period. Reset only
            # when entering a new connecting state or the monotonic clock moves back.
            if [ "$previous_down_state" != connecting ] || [ "$outage_hint_mono" -le 0 ] ||
               [ "$socket_now" -lt "$outage_hint_mono" ]; then
                down_observed="$socket_now"
                outage_hint_mono="$socket_now"
            fi
            previous_down_observed="$outage_hint_mono"
            [ "$previous_down_state" = connecting ] ||
                record_event socket_connecting '本轮原生状态字段未提供；UID0 已观察到 GMS MCS TCP 正在连接'
            ;;
          absent)
            if [ "$outage_hint_mono" -le 0 ] || [ "$socket_now" -lt "$outage_hint_mono" ]; then
                outage_hint_mono="$socket_now"
                record_event tcp_absence_started 'UID0 未观察到 GMS MCS TCP；开始连续缺失计时，暂不据单次缺失重连'
            fi
            socket_down_age=$((socket_now-outage_hint_mono))
            if [ "$socket_down_age" -ge 30 ]; then
                observed=disconnected; source=gms_socket_fallback
                new_transport=; new_remote=
                [ "$previous_down_state" = disconnected ] ||
                    record_event tcp_absence_confirmed "UID0 连续 $socket_down_age 秒未观察到 GMS MCS TCP；按断联进入恢复判断"
            fi
            ;;
        esac
        # A recent native MCS Close event is secondary evidence only when
        # socket ownership is unreadable; a later Connected event supersedes it.
        if [ "$observed" = unknown ] && [ "$tcp_hint" = unknown ] && native_close_fallback_ready; then
            observed=disconnected; source=gms_native_event_fallback
            duration=-1
            close_code=
            new_transport=; new_remote=
            [ "$previous_down_state" = disconnected ] ||
                record_event native_close_confirmed "GMS 原生 Close 事件已持续 $native_hint_age 秒，且未出现后续 Connected 事件"
        fi
    else
        # Reject implausible wall-clock-derived durations (e.g. no prior session).
        if [ "$duration" -gt "$nowm" ]; then duration=-1; fi
    fi
    case "$observed" in
      connected)
        if [ "$previous_down_state" = connecting ] || [ "$previous_down_state" = disconnected ] ||
           [ "$previous_down_observed" -gt 0 ]; then
            last_restore="$nowe"
            if [ "$last_result" = requested ] && [ "$last_try_epoch" -ge "$previous_missing_epoch" ] && [ "$last_try_epoch" -gt 0 ]; then last_result=restored; fi
            if [ "$gap_detected" = 1 ] || [ "$previous_down_state" = unknown ]; then
                if [ "$source" = gms_socket ]; then
                    record_event connection_restored 'UID0 重新观察到 GMS MCS TCP；本次 GMS 原生状态字段仍未读到'
                else
                    record_event connection_restored '采样空档后发现 GMS 已恢复连接；恢复具体时刻未能定位'
                fi
            else
                if [ "$source" = gms_socket ]; then
                    record_event connection_restored 'UID0 观察到 GMS MCS TCP 已建立；本次原生字段未读到'
                else
                    record_event connection_restored 'GMS 已确认重新连接'
                fi
            fi
        fi
        # The native GMS 00:00 can be real immediately after connection.
        # Separately track a bounded sequence of online observations, NOT
        # the precise connection lifetime. Reset after gaps or endpoint changes.
        current_key="$new_remote"
        if [ "$state" != connected ] || [ "$conn_key" != "$current_key" ] ||
           [ "$conn_since_mono" -le 0 ] || [ "$nowm" -lt "$conn_since_mono" ] ||
           [ "$sample_epoch" -le 0 ] || [ "$nowe" -lt "$sample_epoch" ] ||
           [ $((nowe-sample_epoch)) -gt 45 ]; then
            conn_since_mono="$nowm"
        fi
        conn_key="$current_key"
        state=connected; last_seen="$nowe"; missing_since=0; missing_epoch=0; down_observed=0; retry_streak=0; outage_hint_mono=0
        conn_since=0
        if [ "$duration" -ge 0 ] && [ "$duration" -le "$nowe" ]; then
            conn_since=$((nowe-duration))
        fi
        ;;
      connecting|disconnected)
        if [ "$state" != connecting ] && [ "$state" != disconnected ]; then
            [ "$previous_down_state" != connected ] || outages=$((outages+1))
            missing_since="$nowm"; missing_epoch="$nowe"; down_observed="$nowm"
            if [ "$source" = gms_socket_fallback ] || [ "$source" = gms_native_event_fallback ]; then
                : # The corresponding evidence event already records the source and threshold.
            elif [ "$source" = gms_socket ]; then
                record_event connection_down 'UID0 观察到 GMS MCS TCP 正在连接，尚未建立连接'
            elif [ "$previous_down_state" = unknown ] && [ "$previous_down_observed" -gt 0 ]; then
                record_event down_reconfirmed '读取恢复后再次确认 GMS 未连接；保留先前断联证据用于确认'
            else
                record_event connection_down 'GMS 原生状态确认尚未连接'
            fi
        fi
        [ "$down_observed" -gt 0 ] && [ "$down_observed" -le "$nowm" ] || down_observed="$nowm"
        [ "$outage_hint_mono" -gt 0 ] || outage_hint_mono="$nowm"
        if [ "$duration" -ge 0 ] && [ "$duration" -le "$nowe" ]; then
            missing_epoch=$((nowe-duration))
            [ "$duration" -lt "$nowm" ] && missing_since=$((nowm-duration))
        elif [ "$source" = gms_native_event_fallback ] && [ "$native_hint_age" -ge 0 ] && [ "$native_hint_age" -le "$nowm" ]; then
            missing_since=$((nowm-native_hint_age))
            missing_epoch=$((nowe-native_hint_age))
            down_observed="$missing_since"
        fi
        state="$observed"; last_down="$missing_epoch"; conn_key=; conn_since=0; conn_since_mono=0
        ;;
      *)
        state=unknown; conn_key=; missing_since=0; missing_epoch=0; conn_since=0; conn_since_mono=0
        # The separate hint survives alternating unknown/down samples, while
        # the visible observation timer is reset and cannot imply continuity.
        down_observed=0
        [ "$outage_hint_mono" -le 0 ] || missing_epoch="$previous_missing_epoch"
        new_transport=; new_remote=
        ;;
    esac
    transport="$new_transport"; remote="$new_remote"; sample_epoch="$nowe"
    update_native_timer_tracking
    write_evidence
    save_state
}

write_evidence() {
    printf '%s|%s|%s|%s|%s|%s\n' "$source" "$duration" "$close_code" "$tcp_hint" "$native_reason" "$decision" > "$EVIDENCE.tmp" && mv -f "$EVIDENCE.tmp" "$EVIDENCE"
}

confirm_recovery() {
    first_state="$state"; first_source="$source"; first_tcp_hint="$tcp_hint"; first_duration="$duration"
    [ "${BERRY_FCM_TEST_MODE:-0}" = 1 ] || sleep 2
    if [ "$first_source" = gms ]; then observe force_native; else observe; fi
    if { [ "$source" = gms ] || [ "$source" = gms_socket ]; } &&
       { [ "$state" = disconnected ] || [ "$state" = connecting ]; }; then
        record_event recovery_confirmed "二次采样仍确认 GMS MCS 尚未建立连接"
        request_reconnect "$1"
    elif [ "$source" = gms_native_event_fallback ] && [ "$state" = disconnected ] &&
         [ "$first_source" = gms_native_event_fallback ] && [ "$first_state" = disconnected ]; then
        record_event recovery_confirmed "GMS 原生 Close 事件持续 $native_hint_age 秒，二次采样仍未观察到连接"
        request_reconnect "$1"
    elif [ "$source" = gms_socket_fallback ] && [ "$state" = disconnected ] &&
         { { [ "$first_source" = gms ] || [ "$first_source" = gms_socket ]; } &&
           { [ "$first_state" = disconnected ] || [ "$first_state" = connecting ]; } ||
           { [ "$first_state" = unknown ] && [ "$first_tcp_hint" = absent ]; } ||
           { [ "$first_source" = gms_socket_fallback ] && [ "$first_state" = disconnected ]; }; }; then
        record_event recovery_confirmed '复核再次确认 GMS MCS TCP 缺失达到阈值，进入恢复请求'
        request_reconnect "$1"
    elif [ "$first_source" = gms_socket_fallback ] && [ "$first_state" = disconnected ] &&
         [ "$state" = unknown ] && [ "$tcp_hint" = absent ]; then
        socket_down_anchor="$(num "${outage_hint_mono:-0}")"
        socket_down_now="$(num "$(monotime)")"
        socket_down_age=0
        if [ "$socket_down_anchor" -gt 0 ] && [ "$socket_down_now" -ge "$socket_down_anchor" ]; then
            socket_down_age=$((socket_down_now-socket_down_anchor))
        fi
        promote_socket_fallback
        request_reconnect "$1"
    elif [ "$state" = unknown ] && [ "$tcp_hint" = absent ] &&
         { { [ "$first_source" = gms ] && { [ "$first_state" = disconnected ] || [ "$first_state" = connecting ]; }; } ||
           { [ "$first_state" = unknown ] && [ "$first_tcp_hint" = absent ]; }; } &&
         socket_fallback_ready "$first_duration"; then
        promote_socket_fallback
        request_reconnect "$1"
    else
        decision=confirmation_changed
        record_event recovery_confirmation_unavailable "复核未保持断联：first=$first_source/$first_state/$first_tcp_hint second=$source/$state/$tcp_hint；未发送重连"
    fi
}

confirm_stalled_timer() {
    first_duration="$duration"; first_remote="$remote"
    [ "${BERRY_FCM_TEST_MODE:-0}" = 1 ] || sleep 2
    observe force_native || return $?
    nowm="$(num "$(monotime)")
    stalled_age=0
    if [ "$native_timer_since" -gt 0 ] && [ "$nowm" -ge "$native_timer_since" ]; then
        stalled_age=$((nowm-native_timer_since))
    fi
    if [ "$source" = gms ] && [ "$state" = connected ] &&
       [ "$duration" = "$first_duration" ] && [ "$remote" = "$first_remote" ] &&
       [ "$stalled_age" -ge 300 ]; then
        decision=timer_stalled_recovery
        record_event native_timer_stalled "GMS 原生仍报告 Connected；connectTime=$duration 秒，连续 ${stalled_age} 秒未增长，二次采样保持不变"
        request_reconnect stalled_timer
    else
        decision=timer_stalled_cancelled
        record_event native_timer_check_cancelled "二次读取状态或原生计时已变化；取消计时停滞恢复请求"
    fi
}

auto_recovery() {
    decision=not_disconnected
    if [ "$source" = gms ] && [ "$state" = connected ] && [ "$native_timer_since" -gt 0 ]; then
        timer_now="$(num "$(monotime)")"
        timer_stall_age=0
        if [ "$timer_now" -ge "$native_timer_since" ]; then
            timer_stall_age=$((timer_now-native_timer_since))
        fi
        if [ "$timer_stall_age" -ge 300 ]; then
            if ! auto_enabled; then
                decision=timer_stalled_disabled
            elif [ "$native_timer_last_request" -gt 0 ] &&
                 [ "$timer_now" -ge "$native_timer_last_request" ] &&
                 [ $((timer_now-native_timer_last_request)) -lt 600 ]; then
                decision=timer_stalled_cooldown
            else
                confirm_stalled_timer
            fi
        fi
        return 0
    fi
    if [ "$state" = unknown ]; then
        if auto_enabled && socket_fallback_ready "$duration"; then
            confirm_recovery auto
        else
            decision=sample_unavailable
        fi
        return 0
    fi
    case "$source" in gms|gms_socket|gms_socket_fallback|gms_native_event_fallback) :;; *) return 0;; esac
    case "$state" in connecting|disconnected) :;; *) return 0;; esac
    if ! auto_enabled; then decision=disabled; return 0; fi
    nowm="$(num "$(monotime)")"
    interval="$(retry_interval)"
    if [ "$last_try_mono" -gt 0 ] && [ "$nowm" -ge "$last_try_mono" ] && [ $((nowm-last_try_mono)) -lt "$interval" ]; then
        decision=cooldown
        return 0
    fi
    # Let GMS try normally. After a long sampling gap, trust a native outage
    # timer or the previous down sample only to decide when to confirm again.
    required=60
    [ "$state" = disconnected ] && required=15
    observed_age=$((nowm-down_observed))
    if [ "$duration" -ge "$required" ] || [ "$observed_age" -ge "$required" ] ||
       { [ "$previous_down_observed" -gt 0 ] &&
         [ $((nowm-previous_down_observed)) -ge "$required" ]; }; then
        confirm_recovery auto
    else
        decision=waiting_duration
    fi
}

status_json() {
    load_state
    nowe="$(num "$(now_epoch)")"; age=-1
    [ "$sample_epoch" -gt 0 ] && [ "$nowe" -ge "$sample_epoch" ] && age=$((nowe-sample_epoch))
    source=unavailable; duration=-1; close_code=; tcp_hint=none; native_reason=unrecognized; decision=not_evaluated
    if [ -f "$EVIDENCE" ]; then IFS='|' read -r source duration close_code tcp_hint native_reason decision < "$EVIDENCE" || :; fi
    case "${decision:-}" in not_evaluated|not_disconnected|sample_unavailable|disabled|cooldown|gms_stopped_unknown|requested|request_failed|waiting_duration|waiting_confirmation|confirmation_changed|timer_stalled_recovery|timer_stalled_disabled|timer_stalled_cooldown|timer_stalled_cancelled) :;; *) decision=not_evaluated;; esac
    case "$native_reason" in none|not_polled|permission_denied|timeout|service_unavailable|dump_failed|empty|unrecognized|gms_stopped) :;; *) native_reason=unrecognized;; esac
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
    printf '{"fcm_state":"%s","fcm_source":"%s","fcm_transport":"%s","fcm_remote":"%s","fcm_connection_since":%s,"fcm_connected_seconds":%s,"fcm_disconnect_since":%s,"fcm_missing_seconds":%s,"fcm_native_duration":%s,"fcm_observed_up_seconds":%s,"fcm_native_close_events":%s,"fcm_native_connected_events":%s,"fcm_last_close_code":"%s","fcm_tcp_hint":"%s","fcm_last_seen":%s,"fcm_last_restore":%s,"fcm_last_try":%s,"fcm_last_try_reason":"%s","fcm_last_result":"%s","fcm_attempts":%s,"fcm_outages":%s,"fcm_sample_time":%s,"fcm_sample_age_seconds":%s,"fcm_native_reason":"%s","fcm_auto":%s,"fcm_retry_in":%s,"fcm_retry_streak":%s,"fcm_observed_down_seconds":%s,"fcm_recovery_decision":"%s"}\n' \
      "$state" "$source" "$transport" "$remote" "$conn_since" "$connected" "$last_down" "$missing" "$duration" "$observed_up" "$closes" "$successes" "$close_code" "$tcp_hint" "$last_seen" "$last_restore" "$last_try_epoch" "$last_try_reason" "$last_result" "$attempts" "$outages" "$sample_epoch" "$age" "$native_reason" "$auto" "$retry_in" "$retry_streak" "$observed_seconds" "$decision"
}

run_monitor_command() {
case "${1:-status}" in
    status)
        observe force_native || exit $?
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
                record_event recovery_decision "decision=$decision state=$state native_s=$duration reason=$native_reason parser=${parse_detail:-none} retry_streak=$retry_streak"
            fi;;
          connected)
            case "$decision" in timer_stalled_*)
                if [ "$decision" != "$prior_decision" ]; then
                    record_event recovery_decision "decision=$decision state=$state native_s=$duration reason=$native_reason parser=${parse_detail:-none} retry_streak=$retry_streak"
                fi;;
            esac;;
        esac
        ;;
    reconnect)
        observe force_native || exit $?
        if { { [ "$source" = gms ] || [ "$source" = gms_socket ] || [ "$source" = gms_socket_fallback ] || [ "$source" = gms_native_event_fallback ]; } && { [ "$state" = connecting ] || [ "$state" = disconnected ]; }; } ||
           { [ "$state" = unknown ] && socket_fallback_ready "$duration"; }; then
            confirm_recovery manual || exit $?
        else
            decision=not_disconnected
            record_event reconnect_skipped "GMS 已连接或状态不可确认，未发送手动重连"
        fi
        write_evidence || exit $?
        case "$decision" in
          requested) echo "已请求 GMS 恢复，等待下一次连接采样确认";;
          request_failed) echo "Root 重连广播未确认，请查看恢复事件";;
          cooldown) echo "仍在重连冷却期";;
          gms_stopped_unknown) echo "GMS 已停止或停止状态无法确认";;
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
    # Android mksh closes descriptors allocated by exec before launching
    # an external command. Attach the descriptor to this function call.
    lock_error="$("$@" -xn 9 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        if [ -z "$lock_error" ] && [ "$rc" -eq 1 ]; then
            echo "后台正在检查 GMS，请稍后重试" >&2
            return 13
        fi
        printf "无法取得 GMS 检查锁：%s\n" "${lock_error:-退出码 $rc}" >&2
        return 14
    fi
    if write_lock_owner; then trap 'clear_lock_owner' EXIT; fi
    run_monitor_command "$command"
    rc=$?
    clear_lock_owner
    trap - EXIT
    return "$rc"
}

command="${1:-status}"
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
            write_lock_owner || :
            trap 'clear_lock_owner; rm -f "$lock_dir/pid" "$lock_dir/starttime"; rmdir "$lock_dir" 2>/dev/null || :' EXIT
            trap 'exit 130' HUP INT TERM
            run_monitor_command "$command"
        fi
        ;;
    *) run_monitor_command "$command";;
esac
