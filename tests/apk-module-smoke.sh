#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
src="$root/app/src/main/java/top/zesun/berryfcm"
manifest="$root/app/src/main/AndroidManifest.xml"
need() {
  grep -q "$1" "$2" || { echo "MISSING: $1 in $2" >&2; exit 1; }
}
for class in MainActivity AuthActivity MonitorActivity GuardActivity BackgroundActivity DiagnosticsActivity SettingsActivity UpdateActivity AdbPairingService FcmTileService FcmMonitorService; do
  test -s "$src/$class.java" || { echo "MISSING: $class" >&2; exit 1; }
  need "$class" "$manifest"
done
need 'RemoteInput' "$src/AdbPairingService.java"
need 'START_NOT_STICKY' "$src/AdbPairingService.java"
if grep -q 'START_REDELIVER_INTENT' "$src/AdbPairingService.java"; then
  echo 'Pairing code must never be redelivered on service restart' >&2
  exit 1
fi
if grep -q 'adbConnected' "$src/FcmMonitorService.java"; then
  echo 'Cached ADB transport would bypass mode changes' >&2
  exit 1
fi
# In wireless mode ADB launches Priv Kit; all ordinary commands use its Binder.
need 'adb.executeOnce(this, mode, prefs.host(), prefs.staticPort(), command)' "$src/FcmMonitorService.java"
need 'PrivKitShell.execute(this, command)' "$src/FcmMonitorService.java"
need 'PrivKitShell.execute(context, command)' "$src/AdbShell.java"
need 'PrivKitShell.start(context)' "$src/PrivilegeAccess.java"
need 'KIT.startCommand(request, 45000L, continuation)' "$src/PrivKitShell.java"
need 'io.github.priv-kit:priv-core:0.20.0' "$root/app/build.gradle"
need 'autoAttempted' "$src/PrivKitShell.java"
need 'RECOVERY_COOLDOWN_MS' "$src/PrivKitShell.java"
need 'getLifecycleBinder().isBinderAlive()' "$src/PrivKitShell.java"
need 'synchronized String executeOnce' "$src/AdbConnectionManager.java"
# Check the command transaction itself, not only the pairing cleanup.
transaction="$(sed -n '/synchronized String executeOnce(/,/synchronized String shell(/p' "$src/AdbConnectionManager.java")"
printf '%s\n' "$transaction" | grep -q 'finally {'
printf '%s\n' "$transaction" | grep -q 'disconnectSession();'
need 'return adb.executeOnce' "$src/AdbShell.java"
need 'requireShellIdentity(adb.executeOnce' "$src/PrivilegeAccess.java"
need 'Shizuku.bindUserService' "$src/ShizukuShell.java"
need 'Binder.getCallingUid() != ownerUid' "$src/BerryShellUserService.java"
need 'Shizuku.requestPermission' "$src/AuthActivity.java"
need 'android.permission.INTERACT_ACROSS_USERS_FULL' "$manifest"
need 'dev.rikka.shizuku:api:13.1.5' "$root/app/build.gradle"
test -s "$root/app/src/main/aidl/top/zesun/berryfcm/IBerryShell.aidl"
need 'shellInvalidate' "$src/AppPrefs.java"
need 'R.drawable.ic_bf_auth' "$src/AdbPairingService.java"
need 'android:name=".MonitorWatchdog"' "$manifest"
need 'MonitorWatchdog.schedule(this)' "$src/FcmMonitorService.java"
need 'AlarmManager.ELAPSED_REALTIME_WAKEUP' "$src/MonitorWatchdog.java"
need 'getBroadcast(context, 7313, intent' "$src/MonitorWatchdog.java"
need 'ACTION_SCREEN_OFF' "$src/FcmMonitorService.java"
need 'monitorWorker.scheduleWithFixedDelay' "$src/FcmMonitorService.java"
need 'guardWorker.scheduleWithFixedDelay' "$src/FcmMonitorService.java"
need 'wake_lock_acquired' "$src/FcmMonitorService.java"
need 'lastRuntimeEvents(this)' "$src/MonitorActivity.java"
need 'RECOVERY_COOLDOWN_MS = 30000L' "$src/PrivKitShell.java"
need '@drawable/berry_launcher_selected' "$root/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
need 'For OriginOS7' "$src/MainActivity.java"
need 'OriginOS 7（已测试）' "$src/SettingsActivity.java"
need 'R.drawable.ic_berry_fcm_mono' "$src/FcmMonitorService.java"
need 'R.drawable.ic_berry_fcm_mono' "$src/AuthActivity.java"
need '@drawable/ic_berry_fcm_mono' "$manifest"
need 'setOnApplyWindowInsetsListener' "$src/Ui.java"
need 'setTheme(R.style.AppThemeDark)' "$src/Ui.java"
need 'AppThemeDark' "$root/app/src/main/res/values/styles.xml"
need '@mipmap/ic_launcher' "$manifest"
need '@drawable/ic_berry_fcm' "$root/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
need '@color/berry_launcher_background' "$root/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
need '<monochrome' "$root/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
need 'BerryFCM"' "$manifest"
need 'SIGNATURE_PADDING_RSA_PSS' "$src/AdbConnectionManager.java"
need 'DIGEST_NONE' "$src/AdbConnectionManager.java"
need 'ENCRYPTION_PADDING_NONE' "$src/AdbConnectionManager.java"
need 'berry_fcm_adb_identity_v3' "$src/AdbConnectionManager.java"
need 'group.addView(tab, params)' "$src/AuthActivity.java"
# Single-tap pairing starts the notification, then opens wireless settings.
need 'button(parent, "开始配对"' "$src/AuthActivity.java"
need 'openWirelessDebugging()' "$src/AuthActivity.java"
need 'Settings\$WirelessDebuggingActivity' "$src/AuthActivity.java"
need 'onRequestPermissionsResult' "$src/AuthActivity.java"
need 'prefs.enableMonitorOnFirstAuthorization()' "$src/AdbPairingService.java"
need 'FcmMonitorService.start(this)' "$src/AdbPairingService.java"
need 'lastAttemptAt' "$src/FcmMonitorService.java"
need 'authorizationReady()' "$src/MainActivity.java"
need 'monitorButton.setText("去授权")' "$src/MainActivity.java"
need 'disclosure' "$src/Ui.java"
need 'View.generateViewId()' "$src/SettingsActivity.java"
# Pair once, do not gate monitoring on a two-minute manual Shell probe.
need 'boolean adbPaired()' "$src/AppPrefs.java"
need 'void markAdbPaired()' "$src/AppPrefs.java"
need 'prefs.enableMonitorOnFirstAuthorization()' "$src/AdbPairingService.java"
need 'FcmMonitorService.start(this)' "$src/AdbPairingService.java"
need 'lastStartAt' "$src/FcmMonitorService.java"
need 'lastAttemptAt' "$src/MonitorActivity.java"
need 'monitorButton.setText("去授权")' "$src/MainActivity.java"
need 'View.GONE' "$src/Ui.java"
# Selected-first app guardian and conservative system-app eligibility.
need 'private void renderSelected()' "$src/GuardActivity.java"
need 'private void togglePicker()' "$src/GuardActivity.java"
need 'picker.setVisibility(View.GONE)' "$src/GuardActivity.java"
need 'private void loadCandidates()' "$src/GuardActivity.java"
need 'if (open && !scanned && !loading) loadCandidates()' "$src/GuardActivity.java"
need 'getLaunchIntentForPackage' "$src/GuardActivity.java"
need 'FLAG_INSTALLED' "$src/GuardActivity.java"
need 'FLAG_PERSISTENT' "$src/GuardActivity.java"
need 'showSystem.setChecked(false)' "$src/GuardActivity.java"
need 'getApplicationIcon(app.pkg)' "$src/GuardActivity.java"
# Original FCM icon uses shield and pulse rather than the old SMS glyph.
need 'strokeColor' "$root/app/src/main/res/drawable/ic_bf_fcm.xml"
need 'strokeColor' "$root/app/src/main/res/drawable/ic_berry_fcm.xml"

need 'View.GONE' "$src/UpdateActivity.java"
need 'Drawable icon = icons.get' "$src/GuardActivity.java"
need 'ic_berry_fcm_mono' "$root/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
if grep -q 'if (!prefs.shellRecentlyVerified()) state =' "$src/MonitorActivity.java"; then
  echo 'Sampling UI must not treat verification TTL as loss of ADB pairing' >&2
  exit 1
fi

need 'authorizationReady()' "$src/MonitorActivity.java"
need 'PrivilegeAccess.readyForUserAction(this)' "$src/GuardActivity.java"
need 'PrivilegeAccess.readyForUserAction(this)' "$src/BackgroundActivity.java"
need 'PrivilegeAccess.readyForUserAction(this)' "$src/FcmTileService.java"
need 'checkedRead' "$src/BackgroundSettings.java"
need 'BERRY_POLICY_READ_OK' "$src/BackgroundSettings.java"
need 'dozePresent' "$src/BackgroundSettings.java"
need 'putLong("last_run", System.currentTimeMillis())' "$src/GuardActivity.java"
need 'shellVerified' "$src/PrivilegeAccess.java"
need 'shell_verified_elapsed' "$src/AppPrefs.java"
need 'Math.abs(wallAge - elapsedAge)' "$src/AppPrefs.java"
need 'R.drawable.ic_bf_fcm' "$src/Ui.java"
for asset in home fcm guard battery settings auth update diagnostics alert; do
  test -s "$root/app/src/main/res/drawable/ic_bf_$asset.xml" || {
    echo "Missing Material icon: $asset" >&2; exit 1;
  }
done
test -s "$root/app/src/main/res/drawable/ic_berry_fcm.xml"
test -s "$root/app/src/main/res/drawable/ic_berry_fcm_mono.xml"
need 'QUERY_ALL_PACKAGES' "$manifest"
need 'GuardOps.commandBatches' "$src/GuardActivity.java"
need 'GuardOps.commandBatches' "$src/FcmMonitorService.java"
need 'watchNinetySeconds' "$src/GuardActivity.java"
need 'heartbeatCommand' "$src/GuardOps.java"
need 'gmsBackgroundNetwork' "$src/BackgroundSettings.java"
need 'checkPolicies' "$src/DiagnosticsActivity.java"
need 'Socket socket = new Socket()' "$src/DiagnosticsActivity.java"
need 'socket.connect(new InetSocketAddress' "$src/DiagnosticsActivity.java"
need '无需 Root / ADB' "$src/DiagnosticsActivity.java"
need 'BackgroundSettings.optimize(this, shell)' "$src/BackgroundActivity.java"
need 'BackgroundSettings.restoreSelf(this, shell)' "$src/BackgroundActivity.java"
need 'self_op_previous_' "$src/BackgroundSettings.java"
need 'readAppOp' "$src/BackgroundSettings.java"
need '恢复未通过回读' "$src/BackgroundSettings.java"
need 'areNotificationsEnabled' "$src/AuthActivity.java"
need 'AppTask' "$src/RecentTasks.java"

for old in AccessibilityOps RestoreService RestoreTileService; do
  test ! -e "$src/$old.java" || { echo "Obsolete accessibility component: $old" >&2; exit 1; }
  if grep -q "$old" "$manifest"; then echo "Obsolete manifest component: $old" >&2; exit 1; fi
done
if grep -q 'BIND_ACCESSIBILITY_SERVICE' "$manifest" || grep 'WRITE_SECURE_SETTINGS' "$manifest" | grep -vq 'tools:node="remove"'; then
  echo 'Unnecessary accessibility settings permission in manifest' >&2; exit 1
fi

# Service lifecycle and transport consistency: a preference is not proof that
# the monitor is alive; a previous session is not live connection evidence.
need 'sampleAgeSeconds' "$src/FcmMonitorService.java"
need 'sample_session' "$src/FcmMonitorService.java"
need 'sample_elapsed' "$src/FcmMonitorService.java"
need 'sample_mode' "$src/FcmMonitorService.java"
need 'registerDefaultNetworkCallback' "$src/FcmMonitorService.java"
need 'unregisterNetworkCallback' "$src/FcmMonitorService.java"
need 'ACTION_DEVICE_IDLE_MODE_CHANGED' "$src/FcmMonitorService.java"
need 'persistentWakeLock.acquire()' "$src/FcmMonitorService.java"
need 'persistentWakeLock.release()' "$src/FcmMonitorService.java"
need 'resumeIfNeeded' "$src/MainActivity.java"
need 'sampleAgeSeconds' "$src/MonitorActivity.java"
need 'android.permission.WAKE_LOCK' "$manifest"
need 'job.get(45, TimeUnit.SECONDS)' "$src/AdbConnectionManager.java"
need 'process.waitFor(45, TimeUnit.SECONDS)' "$src/RootShell.java"
need 'PrivilegeAccess.probe' "$src/AuthActivity.java"
need 'prefs.activateMode' "$src/AuthActivity.java"
need 'connectionKey' "$src/AppPrefs.java"
if grep -q 'prefs.mode(mode);' "$src/AuthActivity.java"; then
  echo 'Browsing authorization tabs must not switch the active transport' >&2; exit 1
fi

# Exercise the actual plain-Java shell command builder with >10 selected apps.
classes="${RUNNER_TEMP:-/tmp}/berryfcm-guard-smoke"
mkdir -p "$classes"
javac -d "$classes" "$src/GuardOps.java" "$root/tests/GuardOpsSmoke.java"
java -cp "$classes" top.zesun.berryfcm.GuardOpsSmoke
javac -d "$classes" "$src/LaunchCooldown.java" "$root/tests/LaunchCooldownSmoke.java"
java -cp "$classes" top.zesun.berryfcm.LaunchCooldownSmoke
need 'PrivilegeConfig.INSTANCE.configure(3600000L, false)' "$src/PrivKitShell.java"
need 'PrivKitShell.initialize()' "$src/BerryFcmApp.java"
need 'rememberLaunch(context)' "$src/PrivKitShell.java"

echo 'PASS: APK navigation modules, notification ADB pairing, FCM guard, insets, tile, release workflow, and removed accessibility scope'

# Optional Shizuku service uses public Android SDK exceptions.
if grep -q "android.os.ServiceSpecificException" "$src/BerryShellUserService.java"; then
  echo "Hidden Android exception import in Shizuku service"; exit 1
fi

# One identity and the official upstream discovery/authorization/start path.
need 'adb.discoverPairingPort(6000L, continuation)' "$src/PrivKitShell.java"
need 'adb.pair(code, port, 15000L, continuation)' "$src/PrivKitShell.java"
need 'adb.checkPairing(port, 15000L, continuation)' "$src/PrivKitShell.java"
need 'KIT.startAdb(options, 20000L, ADB_NAME' "$src/PrivKitShell.java"
need 'PrivKitShell.discoverPairingPort()' "$src/AdbPairingService.java"
need 'gate.submit(generation, port)' "$src/AdbPairingService.java"
need 'gate.submitManual(generation, entered)' "$src/AdbPairingService.java"
need 'MANUAL_FALLBACK_DELAY_MS' "$src/AdbPairingService.java"
need 'last_startup_trace' "$src/PrivKitShell.java"
need 'getNotificationChannel' "$src/AuthActivity.java"
need 'gate.ready(generation, found)' "$src/AdbPairingService.java"
need 'PrivKitShell.pair(this, selectedPort, code)' "$src/AdbPairingService.java"
need 'if (!authorizationReady())' "$src/MainActivity.java"
need 'monitorButton.setText("立即检查")' "$src/MainActivity.java"
need 'if (!authorizationReady()) { go(AuthActivity.class); return; }' "$src/MonitorActivity.java"
need 'if (authorizationReady()) FcmMonitorService.resumeIfNeeded(this)' "$src/MainActivity.java"
if grep -Eq '立即采样|等待独立服务|localPortListening' "$src/MainActivity.java" "$src/AdbPairingService.java"; then
  echo 'Home must gate monitoring by authorization; pairing must not recheck loopback'; exit 1
fi
need 'PrivKitShell.start(this)' "$src/AdbPairingService.java"
need 'PrivKitShell.execute(this, "id")' "$src/AdbPairingService.java"
need 'prefs.rejectAdbIdentity()' "$src/PrivKitShell.java"
need 'privkit_pairing_history' "$src/AppPrefs.java"
need 'startAfterSettings && leftForSettings' "$src/AuthActivity.java"
if grep -Eq 'AdbConnectionManager|executeOnce\(' "$src/PrivKitShell.java" "$src/AdbPairingService.java"; then
  echo 'Wireless pairing and bootstrap must not call legacy libadb'; exit 1
fi
if grep -Eq 'autoConnectLocal|pairLocal|connectTls' "$src/AdbConnectionManager.java"; then
  echo 'Legacy manager must be static TCP only'; exit 1
fi
javac -d "$classes" "$src/PairingGate.java" "$root/tests/PairingGateSmoke.java"
java -cp "$classes" top.zesun.berryfcm.PairingGateSmoke

# No unsolicited tile or persistent first-run unauthorized monitoring.
# Check the specific tile component, not an unrelated disabled component.
awk '/android:name="\.FcmTileService"/ {tile=1; next} tile && /android:enabled="false"/ {ok=1; exit} tile && /<service|<intent-filter/ {exit} END {exit !ok}' "$manifest"
# Neither authorization success nor service startup may opt in to the tile.
if grep -n 'FcmTileService.setOffered' "$src/AdbPairingService.java" "$src/FcmMonitorService.java" "$src/PrivKitShell.java" "$src/BerryFcmApp.java" "$src/BootReceiver.java"; then
  echo 'Only an explicit user action may expose the Quick Settings tile' >&2; exit 1
fi
need 'FcmTileService.setOffered(this, true)' "$src/AuthActivity.java"
need 'Tile.STATE_UNAVAILABLE' "$src/FcmTileService.java"
need 'canRunInBackground(context)' "$src/FcmMonitorService.java"
need 'canRunInBackground(this)' "$src/FcmMonitorService.java"
need 'STOP_FOREGROUND_REMOVE' "$src/FcmMonitorService.java"

need 'private void addTile()' "$src/AuthActivity.java"
need 'BackgroundSettings.backgroundRestriction(this)' "$src/AuthActivity.java"
# Old private/OEM or duplicate settings assertion removed.
need 'onTileAdded()' "$src/FcmTileService.java"
need 'onTileRemoved()' "$src/FcmTileService.java"

# Auxiliary permissions are advisory; core monitor and guard cannot depend on them.
need 'createAuxiliaryPermissions()' "$src/AuthActivity.java"
need 'refreshAuxiliaryPermissions()' "$src/AuthActivity.java"
need 'BackgroundSettings.associatedStart(this)' "$src/AuthActivity.java"
need 'BackgroundSettings.powerSettings(this)' "$src/AuthActivity.java"
need 'BackgroundSettings.monitorNotifications(this)' "$src/AuthActivity.java"
if grep -nE 'BackgroundSettings\.(batteryExempt|originAutoStartStatus|backgroundRestriction|monitorNotificationStatus)|FcmTileService\.(offered|displayStatus)|areNotificationsEnabled' "$src/PrivilegeAccess.java" "$src/FcmMonitorService.java" "$src/BootReceiver.java"; then
  echo 'Optional system permissions must not block background task execution' >&2; exit 1
fi

need '立即更新' "$src/UpdateActivity.java"
need 'pollDownload()' "$src/UpdateActivity.java"
need 'waiting_install_permission' "$src/UpdateActivity.java"
need 'if (!resumed) return' "$src/UpdateActivity.java"
need 'code != expectedVersion' "$src/UpdateActivity.java"

# Concentrated regression: identity, optional vendor permission evidence and release promotion.
need 'source version.properties' "$root/.github/workflows/build-apk.yml"
need 'versionName releaseVersion.getProperty' "$root/app/build.gradle"
need 'prefs.watchdogMinutes() [*] 60_000L' "$src/MonitorWatchdog.java"
need 'MonitorWatchdog.reschedule(this)' "$src/BackgroundActivity.java"
need 'requireShellIdentity(PrivKitShell.execute(context, "id"), false)' "$src/PrivilegeAccess.java"
# Old private/OEM or duplicate settings assertion removed.
# Old private/OEM or duplicate settings assertion removed.
# Old private/OEM or duplicate settings assertion removed.
# Removed bulk AppOps diagnostic; negative guard at end of file.

need 'PendingIntent.getService(this, 10, reply' "$src/AdbPairingService.java"
need 'setTimeoutAfter(15000L)' "$src/AdbPairingService.java"
need 'enableMonitorOnFirstAuthorization()' "$src/AppPrefs.java"
if grep -q 'Manifest.permission.NEARBY_WIFI_DEVICES' "$src/AuthActivity.java"; then
  echo 'Do not require nearby WiFi permission for Priv Kit NSD' >&2; exit 1
fi

# Shared state and UI lifecycle regression.
need 'MonitorStatus.resolve' "$src/MainActivity.java"
need 'MonitorStatus.resolve' "$src/MonitorActivity.java"
need '"gms_socket".equals(latest.optString("fcm_source"))' "$src/FcmMonitorService.java"
if grep -Fq '"gms".equals(latest.optString("fcm_source"))' "$src/FcmMonitorService.java"; then
  echo 'Manual recovery UI must not accept legacy dump-derived source' >&2; exit 1
fi
need 'Notification.DecoratedCustomViewStyle()' "$src/FcmMonitorService.java"
need 'MonitorStatus.resolve(true, true, isRunning(), age,' "$src/FcmMonitorService.java"
need 'syncChecked(enabled, prefs.monitorEnabled())' "$src/MonitorActivity.java"
need 'syncChecked(running, prefs.guardEnabled())' "$src/GuardActivity.java"
need 'syncChecked(monitorSwitch, prefs.monitorEnabled())' "$src/BackgroundActivity.java"
need 'finally { syncingSwitches = previous; }' "$src/Ui.java"
need 'watchFuture.cancel(true)' "$src/GuardActivity.java"
need 'runSafe(requested, source)' "$src/FcmMonitorService.java"
need 'key.equals(p.connectionKey())' "$src/FcmMonitorService.java"
need 'tileRequestPending' "$src/AuthActivity.java"
# Old private/OEM or duplicate settings assertion removed.
status_classes="$(mktemp -d)"
javac -d "$status_classes" "$src/MonitorStatus.java" "$root/tests/MonitorStatusSmoke.java"
java -cp "$status_classes" top.zesun.berryfcm.MonitorStatusSmoke
rm -rf "$status_classes"

need 'lastAttemptKey = attemptKey' "$src/FcmMonitorService.java"
need 'stopSelfResult(startId)' "$src/FcmMonitorService.java"
need 'error_session' "$src/FcmMonitorService.java"
need 'registerOnSharedPreferenceChangeListener(reportListener)' "$src/GuardActivity.java"
need 'unregisterOnSharedPreferenceChangeListener(reportListener)' "$src/GuardActivity.java"

# Priv Kit requires host API compatibility before initialization and platform TLS.
need 'hiddenapibypass:6.2' "$root/app/build.gradle"
need 'attachBaseContext(Context base)' "$src/BerryFcmApp.java"
need 'HiddenApiBypass.addHiddenApiExemptions("L")' "$src/BerryFcmApp.java"
if grep -q 'Security.insertProviderAt' "$src/BerryFcmApp.java"; then
  echo 'Do not replace platform TLS provider used by Priv Kit' >&2; exit 1
fi
need 'PrivKitShell.recoverOnForeground(this)' "$src/MainActivity.java"
need 'PrivKitShell.recoverOnForeground(this)' "$src/AuthActivity.java"
need 'hasStoredIdentity(context)' "$src/PrivKitShell.java"
need 'foregroundRecovery.compareAndSet(false, true)' "$src/PrivKitShell.java"
echo 'PASS: Priv Kit host integration and persisted-identity recovery wiring'


# Command concurrency regression: one authorization, multiple independently
# scheduled Shell jobs. Lifecycle changes stay serialized; command waits do not.
python3 - "$src/PrivKitShell.java" "$src/FcmMonitorService.java" "$src/BerryShellUserService.java" "$src/AdbConnectionManager.java" "$src/GuardActivity.java" <<'PY_PARALLEL'
from pathlib import Path
import sys
priv, service, shizuku, static_adb, guard = [Path(p).read_text() for p in sys.argv[1:]]
assert "private static synchronized void ensureCommandServer(Context context)" in priv
assert "static String execute(Context context, String command)" in priv
assert "static synchronized String execute(Context context, String command)" not in priv
assert "ensureCommandServer(context);" in priv
assert "static synchronized void start(Context context)" in priv
assert "static synchronized void stopManually(Context context)" in priv
assert "static synchronized void pair(Context context" in priv
assert "process.close();" in priv and "45000L" in priv
assert "monitorWorker.scheduleWithFixedDelay" in service
assert "guardWorker.scheduleWithFixedDelay" in service
assert "ReentrantLock" not in service and "commandLock" not in service
assert "shell_duration" in service
assert "private volatile AdbConnectionManager adb;" in service
assert "!PrivKitShell.isConnected()" in service
assert "!ShizukuShell.isRunning()" in service
assert "synchronized String executeOnce" in static_adb
assert "@Override public String execute(String command)" in shizuku
assert "@Override public synchronized String execute" not in shizuku
assert "Binder.getCallingUid() != ownerUid" in shizuku
assert "process.waitFor(45, TimeUnit.SECONDS)" in shizuku
assert "requestHeartbeat()" in guard and "shell.execute(GuardOps.heartbeatCommand())" in guard
assert 'if (result.contains("|restored"))' not in guard
print("PASS: parallel privileged commands with serialized lifecycle, static ADB, UID checks and bounded shell execution")
PY_PARALLEL

# Android 17 permission, TLS port and explicit service lifecycle.
need 'targetSdk 37' "$root/app/build.gradle"
need 'android.permission.ACCESS_LOCAL_NETWORK' "$root/app/src/main/AndroidManifest.xml"
need 'requestLocalNetworkIfNeeded' "$src/AuthActivity.java"
need 'systemConnectPort()' "$src/PrivKitShell.java"
need 'service.adb.tls.port' "$src/PrivKitShell.java"
need 'stopManually(this)' "$src/AuthActivity.java"
need 'ShizukuShell.stopBinding()' "$src/AuthActivity.java"
need 'prefs.authTab(mode)' "$src/AuthActivity.java"

need 'PrivKitShell.pair(this, selectedPort, code)' "$src/AdbPairingService.java"
need 'return;' "$src/AdbPairingService.java"

# ADB startup crash regression: 0/0 => nullable port for NSD (no Integer.intValue NPE)
need 'AdbConnectPort.select(manual, tls)' "$src/PrivKitShell.java"
need 'ShizukuShell.isRunning()' "$src/PrivilegeAccess.java"
tmp_adb_port="$(mktemp -d)"
javac -d "$tmp_adb_port" "$src/AdbConnectPort.java" "$root/tests/AdbConnectPortSmoke.java"
java -cp "$tmp_adb_port" top.zesun.berryfcm.AdbConnectPortSmoke
rm -rf "$tmp_adb_port"

# Compact authorization controls and selected method state.
need 'detail.setText("当前来源：" + methodName(currentMode)' "$src/AuthActivity.java"
need 'pendingAction = "正在验证 "' "$src/AuthActivity.java"
need 'confirmSwitch(this::startCandidateService)' "$src/AuthActivity.java"
need 'AdbPairingService.isAwaitingInput()' "$src/AuthActivity.java"
need 'openedPairSettings && leftForPairSettings' "$src/AuthActivity.java"
need 'PAIR_INPUT_TIMEOUT_MS' "$src/AdbPairingService.java"
need 'isCodeSubmitted()' "$src/AdbPairingService.java"
if grep -q '当前授权正在进行，请先完成或取消' "$src/AuthActivity.java"; then
  echo 'Browsing authorization methods must remain available' >&2; exit 1
fi
need 'pendingAction = "正在停止 "' "$src/AuthActivity.java"
need 'pendingAction = "正在重启 "' "$src/AuthActivity.java"
if grep -q 'busy ? "处理中"' "$src/AuthActivity.java"; then
  echo 'Generic authorization processing status is prohibited' >&2; exit 1
fi
need 'if (isSelectedRunning()) stopSelectedService()' "$src/AuthActivity.java"
need 'stateToggle.setContentDescription((running ? "停止" : "启动")' "$src/AuthActivity.java"
need 'errorSummary.setText(displayed.replace' "$src/AuthActivity.java"
need 'errorLog.setText(displayed +' "$src/AuthActivity.java"
need 'ShizukuShell.isRunning()' "$src/AuthActivity.java"

# Do not expose irrelevant full AppOps dump as OEM permission diagnosis.
if grep -q 'cmd appops get top.zesun.berryfcm 2>&1' "$src/AuthActivity.java"; then
  echo 'Full Android AppOps is not Vivo permission status' >&2; exit 1
fi
need 'permissionText(associatedRow, "关联启动", "需在 OriginOS 中查看")' "$src/AuthActivity.java"
need 'permissionText(highPowerRow, "允许后台高耗电", "需在 OriginOS 中查看")' "$src/AuthActivity.java"

# Keep optional permissions out of the main authorization view.
need 'disclosure(permissionCard, "自启动、电池和后台权限", false)' "$src/AuthActivity.java"
# Old private/OEM or duplicate settings assertion removed.

# No automatic ADB recovery when Android 17 local network authorization is absent.
need 'PrivKitShell.localNetworkAllowed(context)' "$src/PrivilegeAccess.java"

# Theme-aware toggle must use accessible Ui palette, not private Ui.dark.
need 'toggleSurface.setColor(surface)' "$src/AuthActivity.java"

# Actionable authorization UI and truthful OriginOS permission state.
need 'disclosure(chooser, "选择与管理授权方式", true)' "$src/AuthActivity.java"
need 'permissionText(autoStartRow, "自启动", "需在 OriginOS 中查看")' "$src/AuthActivity.java"
need 'step("Root 授权"' "$src/AuthActivity.java"
need 'step("Shizuku "' "$src/AuthActivity.java"
need 'text(caption, 16, true, ink)' "$src/Ui.java"
need '后台监控运行通知' "$src/FcmMonitorService.java"
need 'new Notification.Builder(this, CHANNEL)' "$src/FcmMonitorService.java"
need 'setColor(android.graphics.Color.WHITE)' "$src/AdbPairingService.java"
if grep -q 'readAutoStartPermission\|厂商权限检测诊断\|监控通知低干扰模式' "$src/AuthActivity.java"; then
  echo 'Misleading OEM status or excessive notification UI remains' >&2; exit 1
fi

if test -e "$root/app/src/main/res/drawable-nodpi/berry_launcher_selected.jpg"; then
  echo "Malformed legacy JPEG must not be bundled"; exit 1
fi
# Reject launcher images that aapt can package but Android cannot decode at runtime.
# Verify PNG checksum, compressed pixels, and a visible blue foreground.
python3 - "$root/app/src/main/res/drawable-nodpi/berry_launcher_selected.png" <<'PY_ICON'
import struct, sys, zlib
data = open(sys.argv[1], "rb").read()
assert data[:8] == b"\x89PNG\r\n\x1a\n", "launcher image must be PNG"
pos, image_data, dimensions, ended = 8, bytearray(), None, False
while pos + 12 <= len(data):
    size = struct.unpack(">I", data[pos:pos + 4])[0]
    name = data[pos + 4:pos + 8]
    payload = data[pos + 8:pos + 8 + size]
    check = struct.unpack(">I", data[pos + 8 + size:pos + 12 + size])[0]
    assert zlib.crc32(name + payload) & 0xffffffff == check, "invalid PNG chunk CRC"
    if name == b"IHDR":
        dimensions = struct.unpack(">II", payload[:8])
    if name == b"IDAT":
        image_data.extend(payload)
    pos += size + 12
    if name == b"IEND":
        ended = True
        break
assert ended and pos == len(data), "truncated PNG"
assert dimensions == (192, 192), "unexpected launcher dimensions"
assert len(zlib.decompress(image_data)) > 192 * 192, "empty launcher image"
assert len(data) > 2500, "launcher artwork missing"
assert len(set(zlib.decompress(image_data))) > 12, "launcher image lacks visible detail"
print("PASS: launcher PNG decoded (192x192, valid chunks and pixels)")
PY_ICON

# Issues #1 and #2: review policy/UI invariants before any Gradle invocation.
python3 - "$src" <<'PY_WAKE_UI'
from pathlib import Path
import sys
root = Path(sys.argv[1])
read = lambda name: (root / name).read_text(encoding="utf-8")
p, svc, wd = (read(x) for x in ("AppPrefs.java", "FcmMonitorService.java", "MonitorWatchdog.java"))
ui, bg, auth = (read(x) for x in ("Ui.java", "BackgroundActivity.java", "AuthActivity.java"))
settings, main = read("SettingsActivity.java"), read("MainActivity.java")
monitor = read("MonitorActivity.java")
manifest = (root.parents[3] / "AndroidManifest.xml").read_text(encoding="utf-8")
def must(ok, reason):
    assert ok, reason

must('WAKE_SMART = "smart"' in p and 'WAKE_CONTINUOUS = "continuous"' in p, "wake modes")
must('p.contains("monitor_enabled") || p.contains("guard_enabled")' in p
     and 'p.getString("wake_mode", fallback)' in p
     and 'p.edit().putString("wake_mode", initial).commit()' in p, "preference migration")
must('if (!monitorEnabled || !AppPrefs.WAKE_CONTINUOUS.equals(' in svc
     and 'persistentWakeLock.acquire()' in svc, "continuous CPU lock gate")
must(all(x in svc for x in ('new TransactionLock("sample", 120000L)',
     'new TransactionLock("manual", 120000L)', 'new TransactionLock("guard", 60000L)',
     'transactions.remove(lock)', 'try (TransactionLock lease')), "bounded task CPU locks")
must('if (!prefs.monitorEnabled()) resetConfirmationWindow();' in svc,
     "turning off FCM while guard remains enabled must release the confirmation lock")
must('confirmationLock.acquire(90000L)' in svc
     and svc.index('if (confirmationUsed)') < svc.index('confirmationUsed = true;')
     and 'resetConfirmationWindow()' in svc, "finite one-shot outage confirmation")
must('updateConfirmationWindow(parsed)' in svc
     and 'MonitorStatus.hasStateEvidence(sample.optString("fcm_source"))' in svc,
     "GMS UID kernel Socket evidence")
must(svc.count('releaseConfirmationWakeLock();') >= 3
     and svc.count('releasePersistentWakeLock();') >= 3, "lifecycle cleanup")
must('holdForService(context)' in wd and 'handoff.acquire(90000L)' in wd
     and 'PendingIntent.FLAG_IMMUTABLE' in wd
     and 'AlarmManager.ELAPSED_REALTIME_WAKEUP' in wd
     and 'setAndAllowWhileIdle' in wd, "bounded immutable alarm handoff")
must('if (!p.monitorEnabled()) MonitorWatchdog.releaseHandoff();' in svc,
     "guard must not drop FCM alarm handoff")
must('String[] names = {"概览", "监控", "守护", "设置"}' in ui
     and 'type == BackgroundActivity.class' not in ui, "four-tab navigation")
must('() -> go(BackgroundActivity.class)' in settings
     and '() -> go(BackgroundActivity.class)' in main, "background entry retained")
must('navContainer.setPadding(dp(14), dp(6), dp(14), bottom + dp(8));' in ui,
     "gesture navigation safe inset")
must('protected void confirmAction(' in ui
     and 'dialog.setOnCancelListener' in ui
     and 'AlertDialog.Builder' not in auth
     and auth.count('confirmAction(') >= 2, "themed safe confirmation dialogs")
must('this::syncWakeChoice' in bg
     and 'confirmAction("开启持续唤醒？"' in bg
     and 'FcmMonitorService.wakeModeChanged(this)' in bg, "mode switch requires confirmation")
must('累计确认窗口持锁' in monitor and '累计事务持锁' in bg,
     "CPU wake statistics visible")
must('setSmallIcon(R.drawable.ic_berry_fcm_mono)' in svc
     and 'android:icon="@drawable/ic_berry_fcm_mono"' in manifest
     and 'Icon.createWithResource(this, R.drawable.ic_berry_fcm_mono)' in auth,
     "notification and tile must use chosen app monochrome icon")
must('android.permission.WAKE_LOCK' in manifest
     and 'android:name=".MonitorWatchdog"' in manifest, "Manifest permissions")
print("PASS: issues 1/2 pre-build policy, lifecycle, UI and Android permissions")
PY_WAKE_UI

# The check's CPU lock evidence must be sampled after acquisition, and
# the watchdog and manual paths must remain distinguishable.
python3 - "$src/FcmMonitorService.java" "$src/DiagnosticsActivity.java" <<'PY_TRIGGER'
from pathlib import Path
import sys
service = Path(sys.argv[1]).read_text(encoding="utf-8")
diagnostics = Path(sys.argv[2]).read_text(encoding="utf-8")
monitor = service[service.index('private void runSafe(boolean requested, String source)') :
                  service.index('private void recordFailure(')]
assert monitor.index('new TransactionLock("sample", 120000L)') < monitor.index('"check_started"')
assert 'transaction_lock=" + lease.isHeld()' in monitor
assert 'source=" + source' in monitor
assert 'runSafe(false, "periodic")' in service
assert 'runSafe(true, "manual_followup")' in service
assert 'queueCheck(false, "network")' in service
assert 'queueCheck(true, WATCHDOG_CHECK.equals(action) ? "watchdog" : "manual")' in service
assert 'PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED.equals(action)' in service
assert 'filter.addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)' in service
assert 'validated != lastValidated' in service
assert 'if (scheduled && pendingSource != null) schedulePendingCheck(0);' in service
assert '() -> queueCheck(false, "network_settled")' in service
assert 'start(context, WATCHDOG_CHECK)' in service
assert 'FcmMonitorService.currentError(this).isEmpty()' in diagnostics
print("PASS: trigger provenance, correct CPU lock observation and active error state")
PY_TRIGGER

# Pre-build semantic icon contract: runtime labels must not silently fall back
# to one FCM icon, and keepalive must not be represented by a battery.
python3 - "$src/Ui.java" "$root/app/src/main/res/drawable" <<'PY_SEMANTIC_ICONS'
import re, sys
import xml.etree.ElementTree as ET
from pathlib import Path
ui = Path(sys.argv[1]).read_text(encoding="utf-8")
res = Path(sys.argv[2])
selector = ui.split("private int symbolFor(String label) {", 1)[1].split("private ImageView symbol(", 1)[0]
branches = re.findall(r'if \(([^\n]+)\) return R\.drawable\.(\w+);', selector)
assert branches, "icon mapping missing"
def icon_for(label):
    for expression, icon in branches:
        if any(word in label for word in re.findall(r'label\.contains\("([^"]+)"\)', expression)):
            return icon
    return "ic_bf_fcm"
expected = {
    "后台保活": "ic_bf_heartbeat",
    "后台保活设置": "ic_bf_heartbeat",
    "放宽后台限制": "ic_bf_heartbeat",
    "电池优化": "ic_bf_battery",
    "项目主页": "ic_bf_code",
    "反馈问题": "ic_bf_feedback",
    "当前版本": "ic_bf_info",
    "适配范围": "ic_bf_device",
}
for label, icon in expected.items():
    assert icon_for(label) == icon, (label, icon_for(label), icon)
icons = ["ic_bf_heartbeat", "ic_bf_code", "ic_bf_feedback", "ic_bf_info", "ic_bf_device"]
paths = []
android = "{http://schemas.android.com/apk/res/android}"
for name in icons:
    root = ET.parse(res / (name + ".xml")).getroot()
    assert root.tag == "vector" and root.attrib[android+"viewportWidth"] == "24"
    assert root.attrib[android+"viewportHeight"] == "24"
    shapes = tuple(p.attrib[android+"pathData"] for p in root)
    assert shapes and all(shapes), name
    paths.append(shapes)
assert len(set(paths)) == len(icons), "icons share identical artwork"
assert "line(box, label, detail, symbolFor(label), action)" in ui
diagnostics = (Path(sys.argv[1]).parent / "DiagnosticsActivity.java").read_text(encoding="utf-8")
assert re.search(r'"Google FCM Diagnostics"[^;]+R\.drawable\.ic_bf_diagnostics', diagnostics)
assert re.search(r'"监控记录"[^;]+R\.drawable\.ic_bf_history', diagnostics)
assert ET.parse(res / "ic_bf_history.xml").find("path").attrib[android+"pathData"] != ET.parse(res / "ic_bf_diagnostics.xml").find("path").attrib[android+"pathData"]
print("PASS: heartbeat keepalive, battery-only battery, four distinct settings icons and valid vectors")
PY_SEMANTIC_ICONS

# Must stay independent from the watchdog, the regular monitor, and packaging.
python3 - "$src/FcmMonitorService.java" "$root/app/src/main/assets/fcm-monitor.sh" <<'PY_RESCUE'
from pathlib import Path
import sys
service, script = (Path(p).read_text(encoding="utf-8") for p in sys.argv[1:])
run = service.split("private void runSafe(boolean requested, String source)",1)[1].split("private void recordFailure(",1)[0]
episode = service.split("private void runRescueEpisode(",1)[1].split("private void runGuardSafe(",1)[0]
assert 'gap >= RESCUE_GAP_MS' in run
assert 'getLong("sample_elapsed", -1L)' in service
assert 'runRescueEpisode(now + 120000L)' in run and 'runOnce(true, false)' in run
assert 'WATCHDOG_CHECK.equals(action)' not in run
assert 'RESCUE_COOLDOWN_MS = 60000L' in service
assert 'Thread.sleep' not in episode
assert 'SystemClock.elapsedRealtime() + 50000L >= deadline' in episode
assert 'queueCheck(false, "rescue_followup")' in episode
assert episode.index('if ("requested".equals(decision)') < episode.index('.putLong("rescue_started_elapsed"')
assert '    rescue)' in script and 'request_reconnect rescue' in script
assert '[ "${BERRY_AUTO_GATE:-ready}" != ready ]' in script and '[ "$source" = gms_socket ]' in script and '[ "$source" = gms_socket_absence ]' in script
assert '(normalRecovery ? "monitor" : "status")' in service
print("PASS: single wake-gap request, shared backoff and nonblocking follow-up")
PY_RESCUE

# Consolidated UI and decorated notification contract: all native glyphs use
# the same outline family; the notification keeps its original app identity.
python3 - "$src/Ui.java" "$src/FcmMonitorService.java" "$root/app/src/main/res" <<'PY_VISUAL'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
ui, service = (Path(p).read_text(encoding="utf-8") for p in sys.argv[1:3])
res = Path(sys.argv[3])
a = "{http://schemas.android.com/apk/res/android}"
icons = sorted((res / "drawable").glob("ic_bf_*.xml"))
assert len(icons) >= 19, len(icons)
for path in icons:
    root = ET.parse(path).getroot()
    assert root.tag == "vector", path
    assert (root.attrib[a+"viewportWidth"],root.attrib[a+"viewportHeight"]) == ("24","24"), path
    assert list(root), path
    for shape in root:
        assert shape.attrib[a+"fillColor"] == "#00000000", path
        assert shape.attrib[a+"strokeColor"] == "#FFFFFFFF", path
        assert 1.5 <= float(shape.attrib[a+"strokeWidth"]) <= 2.1, path
assert 'ic_bf_chevron' in ui and 'ic_bf_heartbeat' in ui
assert 'return R.drawable.ic_bf_info;' in ui
assert 'setCompoundDrawablesRelative(icon, null, null, null)' in ui
assert 'arrow.setRotation(opening ? 180f : 0f)' in ui
assert '.setSmallIcon(R.drawable.ic_berry_fcm_mono)' in service
assert '.setContentTitle("BerryFCM")' in service
assert 'Notification.DecoratedCustomViewStyle()' in service
assert 'setCustomContentView(body)' in service
assert 'sampleAgeSeconds(this)' in service
assert 'MonitorStatus.resolve(' in service
assert 'MonitorStatus.notificationDuration(seconds)' in service
assert 'MonitorStatus.duration(' not in service
assert 'R.drawable.ic_bf_heartbeat' not in service
layout = ET.parse(res / "layout/berry_fcm_notification_status.xml").getroot()
assert layout.tag == "LinearLayout"
body = list(layout)
assert [c.tag for c in body] == ["ImageView", "TextView"]
assert body[0].attrib[a+"src"] == "@drawable/ic_bf_heartbeat"
assert body[1].attrib[a+"id"] == "@+id/berry_status_text"
print("PASS: outlined vector assets, minute-only notification and preserved app icon with inline heartbeat")
PY_VISUAL

# Guard command generation is pure Java; execute its batching and dump-isolation contract.
guard_classes="$(mktemp -d)"
javac -d "$guard_classes" "$src/GuardOps.java" "$root/tests/GuardOpsSmoke.java"
java -cp "$guard_classes" top.zesun.berryfcm.GuardOpsSmoke
rm -rf "$guard_classes"
