#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
APK="$ROOT/app/src/main/assets/fcm-monitor.sh"
KSU="$ROOT/module/bin/fcm-monitor.sh"
CTL="$ROOT/module/bin/ctl.sh"

# APK monitor must not invoke or parse dumpsys anywhere in its runtime script.
! grep -Eiq 'dumpsys|DUMPSYS_BIN|is_gms_stopped|parse_mcs|dump_state_shape|import_native_events|socket_fallback_ready|promote_socket_fallback' "$APK"
grep -Fq 'uid="$("$CMD_BIN" package list packages -U "$GMS"' "$APK"
grep -Fq 'uid="$("$PM_BIN" list packages -U "$GMS"' "$APK"
grep -Fq 'socket="$(scan_sockets)"' "$APK"
grep -Fq 'native_reason=not_used' "$APK"
grep -Fq 'auto_recovery() {' "$APK"
! grep -Fq 'gms_socket_fallback' "$APK"
! grep -Fq 'socket_fallback_ready' "$APK"
grep -Fq 'observe || return $?' "$APK"

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
