#!/system/bin/sh
# KernelSU hot-install supported by newer ksud (official module spec).
# No system mounts, boot-time partition changes, or sepolicy rules require reboot.
chmod 0755 "$MODPATH/hotinstall.sh" 2>/dev/null || abort 'hotinstall.sh is missing or not executable'
chmod 0755 "$MODPATH/uninstall.sh" 2>/dev/null || abort 'uninstall.sh is missing or not executable'
export MODULE_HOT_INSTALL_REQUEST=true
export MODULE_HOT_RUN_SCRIPT=hotinstall.sh
ui_print '- Berry-FCM KSU: no system mounts, no Shizuku required'
ui_print '- Applying module update immediately when KernelSU hot install is available'
[ ! -f "$MODPATH/bin/wake-timer-arm64" ] || set_perm "$MODPATH/bin/wake-timer-arm64" 0 0 0755
