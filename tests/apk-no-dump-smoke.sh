#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
APK="$ROOT/app/src/main/assets/fcm-monitor.sh"
KSU="$ROOT/module/bin/fcm-monitor.sh"
CTL="$ROOT/module/bin/ctl.sh"
GUARD="$ROOT/app/src/main/java/top/zesun/berryfcm/GuardOps.java"

# APK monitor must not invoke or parse dumpsys anywhere in its runtime script.
! grep -Eiq 'dumpsys|DUMPSYS_BIN|is_gms_stopped|parse_mcs|dump_state_shape|import_native_events|socket_fallback_ready|promote_socket_fallback' "$APK"
grep -Fq 'uid="$("$CMD_BIN" package list packages -U "$GMS"' "$APK"
grep -Fq 'uid="$("$PM_BIN" list packages -U "$GMS"' "$APK"
grep -Fq 'socket="$(scan_sockets)"' "$APK"
# A fresh observation must be committed before status/snapshot reloads the state file.
grep -Fq 'save_state || return $?' "$APK"
grep -Fq 'write_evidence || return $?' "$APK"
grep -Fq 'sample_mono' "$APK"
grep -Fq 'sample_gap_age' "$APK"
grep -Fq 'age=$((nowm-sample_mono))' "$APK"
save_block="$(sed -n '/^save_state() {/,/^}/p' "$APK")"
evidence_block="$(sed -n '/^write_evidence() {/,/^}/p' "$APK")"
printf '%s\\n' "$save_block" | grep -Fq 'tmp="$STATE.$"'
printf '%s\\n' "$evidence_block" | grep -Fq 'tmp="$EVIDENCE.$"'
printf '%s\\n' "$save_block" | grep -Fq 'rm -f "$tmp"'
printf '%s\\n' "$evidence_block" | grep -Fq 'rm -f "$tmp"'
request_block="$(sed -n '/^request_reconnect() {/,/^}/p' "$APK")"
printf '%s\\n' "$request_block" | grep -Fq 'if ! save_state; then'
printf '%s\\n' "$request_block" | grep -Fq 'reconnect_aborted'
printf '%s\\n' "$request_block" | grep -Fq 'reconnect_state_commit_failed'
grep -Fq '|state_save_failed)' "$APK"
grep -Fq 'native_reason=not_used' "$APK"
grep -Fq 'auto_recovery() {' "$APK"
! grep -Fq 'gms_socket_fallback' "$APK"
! grep -Fq 'socket_fallback_ready' "$APK"
grep -Fq 'observe || return $?' "$APK"
grep -Fq 'legacy_dump_state_discarded' "$APK"
grep -Fq 'gms_socket_absence_pending' "$APK"
repair_block="$(sed -n '/if (repair) {/,/} else {/p' "$GUARD")"
! printf '%s\\n' "$repair_block" | grep -Fq 'dumpsys'
printf '%s\\n' "$repair_block" | grep -Fq 'cmd package unstop --user 0'
grep -Fq 'dumpsys -t 3 package' "$GUARD"
grep -Fq 'unstop_submitted' "$GUARD"

# KSU monitor, patrol and supervisor are also dump-independent.
! grep -Eiq 'dumpsys|DUMPSYS_BIN' "$KSU" "$ROOT/module/bin/patrol.sh" "$ROOT/module/service.sh"

# Package dump data may remain visible in diagnostics, but must not gate fix/unstop/heartbeat.
fix_block="$(sed -n '/^fix() {/,/^}/p' "$CTL")"
! printf '%s\n' "$fix_block" | grep -Eiq 'dumpsys|stopped\('
printf '%s\n' "$fix_block" | grep -Fq 'cmd package unstop --user 0 "$pkg"'
printf '%s\n' "$fix_block" | grep -Fq 'if installed "$GMS"; then'
printf '%s\n' "$fix_block" | grep -Fq 'heartbeat || echo'

sh -n "$APK"
sh -n "$KSU"
sh -n "$CTL"
echo 'APK/KSU dump-isolation static checks passed'
