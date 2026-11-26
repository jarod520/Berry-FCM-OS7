package top.zesun.berryfcm;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.widget.RemoteViews;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.BroadcastReceiver;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.SystemClock;
import android.util.Base64;
import java.io.InputStream;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import org.json.JSONObject;

/** Foreground monitoring runs independently of activities; only MCS state writes are serialized. */
public final class FcmMonitorService extends Service {
    private static final String SNAPSHOT = "berry_fcm_monitor_snapshot";
    // Preserve the existing silent channel ID across upgrades.
    private static final String CHANNEL = "berry_fcm_monitor_quiet";
    private static final int NOTIFICATION_ID = 7212;
    private static final String CHECK = "berryfcm.monitor.check";
    private static final String WATCHDOG_CHECK = "berryfcm.monitor.watchdog";
    private static final String RECONNECT = "berryfcm.monitor.reconnect";
    private static final String REFRESH_DISPLAY = "berryfcm.monitor.display";
    private static final long RESCUE_GAP_MS = 90000L;
    private static final long RESCUE_COOLDOWN_MS = 60000L;
    private final ScheduledExecutorService monitorWorker = Executors.newSingleThreadScheduledExecutor();
    private final ScheduledExecutorService guardWorker = Executors.newSingleThreadScheduledExecutor();
    private volatile boolean scheduled;
    private boolean installed;
    private static volatile String activeSession = "";
    private final String session = UUID.randomUUID().toString();
    private static volatile long lastResumeRequest;
    private ConnectivityManager networkManager;
    private ConnectivityManager.NetworkCallback networkCallback;
    private BroadcastReceiver resumeReceiver;
    private volatile long networkSignal;
    private long consumedNetworkSignal;
    private long lastCheckElapsed;
    private long lastCheckUptime;
    private long lastLoggedCheckElapsed;
    private long nextAttemptElapsed;
    private int failureStreak;
    private boolean checkQueued;
    private boolean pendingRequested;
    private String pendingSource;
    private ScheduledFuture<?> networkRecheck;
    private final AtomicBoolean reconnectQueued = new AtomicBoolean();
    private String installedMode;
    private String lastAttemptKey = "";
    private ScheduledFuture<?> periodic;
    private ScheduledFuture<?> guardPeriodic;
    // Held across checks while monitoring/guard is enabled, not just inside a sample.
    private PowerManager.WakeLock persistentWakeLock;
    private static volatile boolean wakeLockHeld;
    private static volatile FcmMonitorService live;
    private long continuousSince = -1;
    private PowerManager.WakeLock confirmationLock;
    private long confirmationSince = -1;
    private boolean confirmationUsed;
    private final java.util.concurrent.atomic.AtomicLong transactionTotalMs = new java.util.concurrent.atomic.AtomicLong();
    private static final java.util.Set<PowerManager.WakeLock> transactions =
            java.util.Collections.newSetFromMap(
                    new java.util.concurrent.ConcurrentHashMap<PowerManager.WakeLock, Boolean>());
    private final android.os.Handler main = new android.os.Handler(android.os.Looper.getMainLooper());
    private int newestStartId;
    private volatile AdbConnectionManager adb;
    private long lastGuardAt;
    private Network observedNetwork;
    private String lastNotificationText = "";
    private long networkChangedAt;

    static boolean start(Context context) { return start(context, null); }
    static boolean isRunning() { return !activeSession.isEmpty(); }
    static boolean isCpuWakeLockHeld() {
        if (wakeLockHeld) return true;
        FcmMonitorService active = live;
        if (active != null && active.confirmationLock != null && active.confirmationLock.isHeld()) return true;
        for (PowerManager.WakeLock lock : transactions) if (lock.isHeld()) return true;
        return false;
    }
    static long continuousWakeMs(Context context) {
        SharedPreferences state = context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
        long value = state.getLong("wake_continuous_ms", 0);
        FcmMonitorService instance = live;
        if (instance != null && wakeLockHeld && instance.continuousSince >= 0)
            value += Math.max(0, SystemClock.elapsedRealtime() - instance.continuousSince);
        return value;
    }
    static long confirmationWakeMs(Context context) {
        SharedPreferences state = context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
        long value = state.getLong("wake_confirmation_ms", 0);
        FcmMonitorService instance = live;
        if (instance != null && instance.confirmationSince >= 0
                && instance.confirmationLock != null && instance.confirmationLock.isHeld())
            value += Math.min(90000L,
                    Math.max(0, SystemClock.elapsedRealtime() - instance.confirmationSince));
        return value;
    }
    static long transactionWakeMs(Context context) {
        FcmMonitorService instance = live;
        return instance != null ? instance.transactionTotalMs.get()
                : context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE).getLong("wake_transaction_ms", 0);
    }
    static void wakeModeChanged(Context context) {
        FcmMonitorService instance = live;
        if (instance != null) {
            AppPrefs prefs = new AppPrefs(context);
            instance.resetConfirmationWindow();
            instance.updatePersistentWakeLock(prefs.monitorEnabled());
            logRuntime(context, "wake_mode_changed", prefs.wakeMode()
                    + "; lock_held=" + isCpuWakeLockHeld());
        }
    }

    // Called only from a visible activity. Restore existing enabled tasks,
    // without changing the user's settings or bypassing a force-stop.
    static void resumeIfNeeded(Context context) {
        AppPrefs prefs = new AppPrefs(context);
        if (!prefs.monitorEnabled() && !prefs.guardEnabled()) return;
        if (!PrivilegeAccess.canRunInBackground(context)) return;
        long now = SystemClock.elapsedRealtime();
        long age = sampleAgeSeconds(context);
        if (isRunning() && (!prefs.monitorEnabled() || (age >= 0 && age <= 90)
                || nextAttemptIn(context) > 0)) return;
        if (lastResumeRequest > 0 && now - lastResumeRequest < 15000) return;
        lastResumeRequest = now;
        checkNow(context);
    }

    static long sampleAgeSeconds(Context context) {
        SharedPreferences stored = context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
        if (!isRunning() || !activeSession.equals(stored.getString("sample_session", ""))) return -1;
        if (!new AppPrefs(context).connectionKey().equals(stored.getString("sample_mode", ""))) return -1;
        long at = stored.getLong("sample_elapsed", -1);
        long age = SystemClock.elapsedRealtime() - at;
        return at >= 0 && age >= 0 ? age / 1000 : -1;
    }

    static String serviceStatus(Context context) {
        AppPrefs prefs = new AppPrefs(context);
        if (!prefs.monitorEnabled() && !prefs.guardEnabled()) return "未启用";
        if (!isRunning()) return "后台服务未运行";
        if (!prefs.monitorEnabled()) return "应用守护运行中";
        long age = sampleAgeSeconds(context);
        if (!currentError(context).isEmpty()) return "采样失败，后台重试中";
        if (age < 0 || age > 90) return "等待本次有效采样";
        return "后台服务运行中";
    }
    static void checkNow(Context context) { start(context, CHECK); }
    static boolean startFromWatchdog(Context context) { return start(context, WATCHDOG_CHECK); }
    static void refreshDisplay(Context context) {
        if (!isRunning()) return;
        try { context.startService(new Intent(context, FcmMonitorService.class).setAction(REFRESH_DISPLAY)); }
        catch (RuntimeException ignored) { /* existing notification remains until next refresh */ }
    }
    static String manualReconnect(Context context) {
        return start(context, RECONNECT)
                ? "正在检查是否需要发送恢复请求，请查看下方执行结果"
                : "未安排恢复检查，请确认监控已开启且已授权";
    }
    static String manualReconnectResult(Context context) {
        SharedPreferences stored = context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
        return !activeSession.isEmpty()
                && activeSession.equals(stored.getString("manual_session", ""))
                && new AppPrefs(context).connectionKey().equals(stored.getString("manual_mode", ""))
                ? stored.getString("manual_result", "") : "";
    }
    private void saveManualResult(String key, String value) {
        if (!scheduled || !session.equals(activeSession)
                || !key.equals(new AppPrefs(this).connectionKey())) return;
        getSharedPreferences(SNAPSHOT, MODE_PRIVATE).edit()
                .putString("manual_session", session).putString("manual_mode", key)
                .putString("manual_result", value).apply();
    }
    private static boolean start(Context context, String action) {
        AppPrefs prefs = new AppPrefs(context);
        if (!prefs.monitorEnabled() && !prefs.guardEnabled()) {
            stop(context);
            return false;
        }
        if (!PrivilegeAccess.canRunInBackground(context)) return false;
        Intent intent = new Intent(context, FcmMonitorService.class);
        if (action != null) intent.setAction(action);
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent);
            else context.startService(intent);
            return true;
        } catch (RuntimeException error) {
            context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE).edit()
                    .putString("error", "系统禁止启动后台监测：" + error.getMessage())
                    .putString("error_session", activeSession)
                    .putString("error_mode", prefs.connectionKey()).apply();
            return false;
        }
    }
    static void stop(Context context) {
        MonitorWatchdog.cancel(context);
        MonitorWatchdog.releaseHandoff();
        context.stopService(new Intent(context, FcmMonitorService.class));
    }
    static JSONObject lastSnapshot(Context context) {
        try {
            String raw = context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE).getString("json", "");
            return raw.isEmpty() ? new JSONObject() : new JSONObject(raw);
        } catch (Exception error) { return new JSONObject(); }
    }
    static String lastEvents(Context context) {
        return context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE).getString("events", "");
    }
    static String lastEnvironmentEvents(Context context) {
        return diagnosticHistory(context, "environment_events", 24);
    }
    static String lastRuntimeEvents(Context context) {
        return diagnosticHistory(context, "runtime_events", 36);
    }
    static synchronized String diagnosticHistory(Context context, String stream, int limit) {
        SharedPreferences stored = context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
        String legacy = stored.getString(stream, "");
        try {
            return DiagnosticHistory.read(context.getDir("diagnostic_logs", MODE_PRIVATE), stream, legacy, limit);
        } catch (java.io.IOException error) {
            android.util.Log.w("BerryFCM", "读取诊断日志失败", error);
            return legacy;
        }
    }
    private static synchronized boolean appendDiagnostic(Context context, String stream, String event, String details) {
        SharedPreferences stored = context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
        String safe = details.replace('\r', ' ').replace('\n', ' ').replace('|', '/');
        long epoch = System.currentTimeMillis() / 1000L;
        try {
            DiagnosticHistory.append(context.getDir("diagnostic_logs", MODE_PRIVATE), stream, epoch,
                    stored.getString(stream, ""), epoch + "|" + event + "|" + safe);
            if (stored.contains(stream)) stored.edit().remove(stream).commit();
            return true;
        } catch (java.io.IOException error) {
            android.util.Log.w("BerryFCM", "保存诊断日志失败", error);
            return false;
        }
    }
    static void logRuntime(Context context, String event, String details) {
        appendDiagnostic(context, "runtime_events", event, details);
    }
    static String lastError(Context context) {
        return context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE).getString("error", "");
    }
    static String currentError(Context context) {
        SharedPreferences stored = context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
        return activeSession.equals(stored.getString("error_session", "no-session"))
                && new AppPrefs(context).connectionKey().equals(stored.getString("error_mode", ""))
                ? stored.getString("error", "") : "";
    }
    static long nextAttemptIn(Context context) {
        if (!isRunning()) return 0;
        long at = context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE).getLong("next_attempt_elapsed", 0);
        return Math.max(0, (at - SystemClock.elapsedRealtime() + 999) / 1000);
    }
    static long lastAttemptAt(Context context) {
        return context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE).getLong("attempt_time", 0);
    }
    static long lastStartAt(Context context) {
        return context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE).getLong("service_start_time", 0);
    }
    static String lastAttemptState(Context context) {
        return context.getSharedPreferences(SNAPSHOT, MODE_PRIVATE).getString("attempt_state", "pending");
    }

    @Override public void onCreate() {
        super.onCreate();
        live = this;
        transactionTotalMs.set(getSharedPreferences(SNAPSHOT, MODE_PRIVATE)
                .getLong("wake_transaction_ms", 0));
        NotificationManager manager = getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(CHANNEL,
                "后台监控运行通知", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("后台监控运行通知");
        channel.setSound(null, null);
        manager.createNotificationChannel(channel);
        startForeground(NOTIFICATION_ID, notification());
        registerResumeTriggers();
        logRuntime(this, "service_created", "pid=" + android.os.Process.myPid());
    }
    private Notification notification() {
        PendingIntent open = PendingIntent.getActivity(this, 0,
                new Intent(this, MainActivity.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        String status = notificationText();
        Notification.Builder builder = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_berry_fcm_mono)
                .setColor(0xff365ed6)
                .setContentTitle("BerryFCM")
                .setContentText(status)
                .setOnlyAlertOnce(true)
                .setContentIntent(open)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setOngoing(true);
        // Decorate only the notification body. The system keeps the original
        // app icon, notification header, and foreground-service behavior.
        RemoteViews body = new RemoteViews(getPackageName(), R.layout.berry_fcm_notification_status);
        body.setTextViewText(R.id.berry_status_text, status);
        builder.setStyle(new Notification.DecoratedCustomViewStyle())
                .setCustomContentView(body)
                .setCustomBigContentView(body);
        return builder.build();
    }

    private String notificationText() {
        if (!PrivilegeAccess.readyForUserAction(this)) return "正在恢复授权服务，暂未监控";
        AppPrefs prefs = new AppPrefs(this);
        if (!prefs.monitorEnabled()) return "应用守护已开启";
        JSONObject snapshot = lastSnapshot(this);
        long age = sampleAgeSeconds(this);
        String stateSource = snapshot.optString("fcm_source");
        boolean stateEvidence = MonitorStatus.hasStateEvidence(stateSource);
        MonitorStatus.State state = MonitorStatus.resolve(true, true, isRunning(), age,
                !currentError(this).isEmpty(), stateEvidence,
                snapshot.optString("fcm_state", "unknown"));
        if (state == MonitorStatus.State.CONNECTED) {
            long up = Math.max(snapshot.optLong("fcm_connected_seconds", 0), snapshot.optLong("fcm_observed_up_seconds", 0));
            return "FCM 长连接已建立 · " + (up >= 60 ? MonitorStatus.notificationDuration(up) : "刚建立");
        }
        if (state == MonitorStatus.State.DISCONNECTED || state == MonitorStatus.State.CONNECTING) {
            long seconds = snapshot.optLong("fcm_observed_down_seconds", -1);
            if (seconds >= 15)
                return MonitorStatus.label(state, stateSource) + " · 已观察：" + MonitorStatus.notificationDuration(seconds);
            return MonitorStatus.label(state, stateSource);
        }
        return MonitorStatus.label(state, stateSource);
    }

    private void refreshNotification() {
        if (!scheduled) return;
        String text = notificationText();
        if (text.equals(lastNotificationText)) return;
        try {
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.notify(NOTIFICATION_ID, notification());
                lastNotificationText = text;
            }
        } catch (RuntimeException error) {
            android.util.Log.w("BerryFCM", "Monitor notification refresh failed", error);
        }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        newestStartId = startId;
        AppPrefs prefs = new AppPrefs(this);
        if (intent != null && REFRESH_DISPLAY.equals(intent.getAction())) {
            if (scheduled) {
                startForeground(NOTIFICATION_ID, notification());
                lastNotificationText = notificationText();
                return START_STICKY;
            }
            stopIfIneligible(startId);
            return START_NOT_STICKY;
        }
        if ((!prefs.monitorEnabled() && !prefs.guardEnabled()) || !PrivilegeAccess.canRunInBackground(this)) {
            stopIfIneligible(startId);
            return START_NOT_STICKY;
        }
        startForeground(NOTIFICATION_ID, notification());
        lastNotificationText = notificationText();
        boolean firstStart = !scheduled;
        if (firstStart) {
            activeSession = session;
            getSharedPreferences(SNAPSHOT, MODE_PRIVATE).edit()
                    .putLong("service_start_time", System.currentTimeMillis())
                    .putLong("next_attempt_elapsed", 0)
                    .putLong("attempt_time", 0)
                    .putString("attempt_state", "pending").apply();
            scheduled = true;
            logRuntime(this, "service_started", "pid=" + android.os.Process.myPid()
                    + "，版本=" + appVersion(this) + "，授权模式=" + prefs.mode()
                    + "，启动来源=" + (intent != null && WATCHDOG_CHECK.equals(intent.getAction())
                            ? "系统兜底闹钟" : "服务启动"));
        }
        updatePersistentWakeLock(prefs.monitorEnabled());
        // The guard may continue after FCM monitoring is disabled. A pending
        // anomaly-confirmation lease must end immediately, not at its timeout.
        if (!prefs.monitorEnabled()) resetConfirmationWindow();
        updatePeriodicSchedules(prefs);
        MonitorWatchdog.schedule(this);
        String action = intent == null ? null : intent.getAction();
        if (!firstStart && (CHECK.equals(action) || WATCHDOG_CHECK.equals(action)))
            queueCheck(true, WATCHDOG_CHECK.equals(action) ? "watchdog" : "manual");
        if (RECONNECT.equals(action) && reconnectQueued.compareAndSet(false, true)) {
            saveManualResult(prefs.connectionKey(), "正在读取 GMS 并检查重连条件…");
            monitorWorker.execute(() -> {
                try (TransactionLock lease = new TransactionLock("manual", 120000L)) {
                    MonitorWatchdog.releaseHandoff();
                    manualReconnectInternal();
                } finally { reconnectQueued.set(false); }
            });
        }
        return START_STICKY;
    }

    private void updatePeriodicSchedules(AppPrefs prefs) {
        if (prefs.monitorEnabled()) {
            if (periodic == null || periodic.isCancelled() || periodic.isDone())
                periodic = monitorWorker.scheduleWithFixedDelay(
                        () -> runSafe(false, "periodic"), 0, 15, TimeUnit.SECONDS);
        } else if (periodic != null) {
            periodic.cancel(false);
            periodic = null;
        }
        if (prefs.guardEnabled()) {
            if (guardPeriodic == null || guardPeriodic.isCancelled() || guardPeriodic.isDone())
                guardPeriodic = guardWorker.scheduleWithFixedDelay(this::runGuardSafe, 0, 5, TimeUnit.MINUTES);
        } else if (guardPeriodic != null) {
            guardPeriodic.cancel(false);
            guardPeriodic = null;
        }
    }

    /** Only the explicitly selected continuous policy holds the CPU between checks. */
    private void updatePersistentWakeLock(boolean monitorEnabled) {
        if (!monitorEnabled || !AppPrefs.WAKE_CONTINUOUS.equals(new AppPrefs(this).wakeMode())) {
            releasePersistentWakeLock();
            return;
        }
        try {
            PowerManager power = getSystemService(PowerManager.class);
            if (power == null) throw new IllegalStateException("PowerManager unavailable");
            if (persistentWakeLock == null) {
                persistentWakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BerryFCM:monitor");
                persistentWakeLock.setReferenceCounted(false);
            }
            if (!persistentWakeLock.isHeld()) {
                persistentWakeLock.acquire();
                continuousSince = SystemClock.elapsedRealtime();
                logRuntime(this, "wake_lock_acquired", "mode=continuous; screen="
                        + (power.isInteractive() ? "on" : "off"));
            }
            wakeLockHeld = persistentWakeLock.isHeld();
        } catch (RuntimeException error) {
            wakeLockHeld = false;
            getSharedPreferences(SNAPSHOT, MODE_PRIVATE).edit()
                    .putString("wake_lock_error", safeError(error)).apply();
            logRuntime(this, "wake_lock_failed", safeError(error));
        }
    }

    private void releasePersistentWakeLock() {
        long elapsed = continuousSince >= 0
                ? Math.max(0, SystemClock.elapsedRealtime() - continuousSince) : 0L;
        try {
            if (persistentWakeLock != null && persistentWakeLock.isHeld()) persistentWakeLock.release();
        } catch (RuntimeException error) {
            logRuntime(this, "wake_lock_release_error", safeError(error));
        } finally {
            wakeLockHeld = false;
            continuousSince = -1L;
            if (elapsed > 0) {
                SharedPreferences state = getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
                state.edit().putLong("wake_continuous_ms",
                        state.getLong("wake_continuous_ms", 0) + elapsed).apply();
                logRuntime(this, "wake_lock_released", "held_ms=" + elapsed);
            }
        }
    }

    /** One finite 90-second confirmation window per observed outage, never renewed
     * until a fresh native connected observation has been recorded. */
    private synchronized void updateConfirmationWindow(JSONObject sample) {
        String state = sample.optString("fcm_state", "unknown");
        if ("connected".equals(state) && MonitorStatus.hasStateEvidence(sample.optString("fcm_source"))) {
            releaseConfirmationWakeLock();
            confirmationUsed = false;
            return;
        }
        boolean abnormal = MonitorStatus.hasStateEvidence(sample.optString("fcm_source"))
                && ("disconnected".equals(state) || "connecting".equals(state))
                && new AppPrefs(this).autoReconnect();
        if (!new AppPrefs(this).autoReconnect()
                || !AppPrefs.WAKE_SMART.equals(new AppPrefs(this).wakeMode())) {
            resetConfirmationWindow();
            return;
        }
        // A transient unreadable sample must not release the existing bounded
        // confirmation lease prematurely. It still cannot authorize recovery.
        if (!abnormal) {
            if (!confirmationUsed || confirmationSince < 0
                    || SystemClock.elapsedRealtime() - confirmationSince >= 90000L)
                releaseConfirmationWakeLock();
            return;
        }
        if (confirmationUsed) {
            if (confirmationSince >= 0
                    && SystemClock.elapsedRealtime() - confirmationSince >= 90000L)
                releaseConfirmationWakeLock();
            return;
        }
        confirmationUsed = true;
        try {
            PowerManager power = getSystemService(PowerManager.class);
            if (power == null) throw new IllegalStateException("PowerManager unavailable");
            confirmationLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,
                    "BerryFCM:outage-confirmation");
            confirmationLock.setReferenceCounted(false);
            confirmationLock.acquire(90000L);
            confirmationSince = SystemClock.elapsedRealtime();
            logRuntime(this, "wake_confirmation_started", "state=" + state + "; max_ms=90000");
        } catch (RuntimeException error) {
            confirmationLock = null;
            confirmationSince = -1;
            logRuntime(this, "wake_lock_failed", "confirmation: " + safeError(error));
        }
    }
    private synchronized void resetConfirmationWindow() {
        releaseConfirmationWakeLock();
        confirmationUsed = false;
    }
    private synchronized void releaseConfirmationWakeLock() {
        if (confirmationLock == null) return;
        long elapsed = confirmationSince < 0 ? 0 : Math.min(90000L,
                Math.max(0, SystemClock.elapsedRealtime() - confirmationSince));
        try {
            if (confirmationLock.isHeld()) confirmationLock.release();
        } catch (RuntimeException error) {
            logRuntime(this, "wake_lock_release_error", "confirmation: " + safeError(error));
        } finally {
            confirmationLock = null;
            confirmationSince = -1;
            if (elapsed > 0) {
                SharedPreferences state = getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
                state.edit().putLong("wake_confirmation_ms",
                        state.getLong("wake_confirmation_ms", 0) + elapsed).apply();
                logRuntime(this, "wake_confirmation_finished", "held_ms=" + elapsed);
            }
        }
    }

    /** A bounded lease protects an already dispatched task; it cannot wake a sleeping CPU. */
    private final class TransactionLock implements AutoCloseable {
        private PowerManager.WakeLock lock;
        private final long started = SystemClock.elapsedRealtime();
        private final long timeout;
        private final String purpose;
        TransactionLock(String purpose, long timeout) {
            this.purpose = purpose;
            this.timeout = timeout;
            try {
                PowerManager power = getSystemService(PowerManager.class);
                if (power == null) throw new IllegalStateException("PowerManager unavailable");
                lock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BerryFCM:" + purpose);
                lock.setReferenceCounted(false);
                lock.acquire(timeout);
                transactions.add(lock);
            } catch (RuntimeException error) {
                lock = null;
                logRuntime(FcmMonitorService.this, "wake_lock_failed", purpose + ": " + safeError(error));
            }
        }
        boolean isHeld() { return lock != null && lock.isHeld(); }
        @Override public void close() {
            if (lock == null) return;
            boolean expired = !lock.isHeld();
            try {
                if (!expired) lock.release();
            } catch (RuntimeException error) {
                logRuntime(FcmMonitorService.this, "wake_lock_release_error",
                        purpose + ": " + safeError(error));
            } finally {
                transactions.remove(lock);
                long elapsed = Math.max(0, SystemClock.elapsedRealtime() - started);
                long total = transactionTotalMs.addAndGet(Math.min(elapsed, timeout));
                // An old worker must never overwrite a newer service session's counter.
                if (live == FcmMonitorService.this)
                    getSharedPreferences(SNAPSHOT, MODE_PRIVATE).edit()
                            .putLong("wake_transaction_ms", total).apply();
                if (elapsed > 15000 || expired)
                    logRuntime(FcmMonitorService.this, "wake_transaction",
                            "purpose=" + purpose + "; elapsed_ms=" + elapsed + "; timeout=" + expired);
            }
        }
    }

    // Lifecycle changes are serialized on Android's main thread. A delayed
    // stop from an old worker must not kill a newer user start.
    private void stopIfIneligible(int startId) {
        AppPrefs prefs = new AppPrefs(this);
        if (startId != newestStartId || (scheduled
                && (prefs.monitorEnabled() || prefs.guardEnabled())
                && PrivilegeAccess.canRunInBackground(this))) return;
        if (!stopSelfResult(startId)) return;
        scheduled = false;
        if (session.equals(activeSession)) activeSession = "";
        if (periodic != null) periodic.cancel(false);
        if (guardPeriodic != null) guardPeriodic.cancel(false);
        releasePersistentWakeLock();
        releaseConfirmationWakeLock();
        MonitorWatchdog.releaseHandoff();
        stopForeground(STOP_FOREGROUND_REMOVE);
    }

    private void registerResumeTriggers() {
        try {
            networkManager = getSystemService(ConnectivityManager.class);
            networkCallback = new ConnectivityManager.NetworkCallback() {
                @Override public void onAvailable(Network network) { onNetworkChange(); }
                @Override public void onLost(Network network) { onNetworkChange(); }
                private String lastTransport = "";
                private boolean lastValidated;
                @Override public void onCapabilitiesChanged(Network network, NetworkCapabilities caps) {
                    String transport = transportName(caps);
                    boolean validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
                    if (!transport.equals(lastTransport) || validated != lastValidated) {
                        lastTransport = transport;
                        lastValidated = validated;
                        onNetworkChange();
                    }
                }
            };
            if (networkManager != null) networkManager.registerDefaultNetworkCallback(networkCallback);
        } catch (RuntimeException ignored) { networkCallback = null; }
        try {
            resumeReceiver = new BroadcastReceiver() {
                @Override public void onReceive(Context context, Intent intent) {
                    // Screen and idle transitions schedule a check only while
                    // this process is running; they are not cold-start wake sources.
                    String action = intent == null ? "" : intent.getAction();
                    String source = "screen_transition";
                    if (PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED.equals(action)) source = "idle_transition";
                    if (PowerManager.ACTION_POWER_SAVE_MODE_CHANGED.equals(action)) source = "power_save_transition";
                    queueCheck(false, source);
                }
            };
            IntentFilter filter = new IntentFilter(Intent.ACTION_USER_PRESENT);
            filter.addAction(Intent.ACTION_SCREEN_ON);
            filter.addAction(Intent.ACTION_SCREEN_OFF);
            filter.addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED);
            filter.addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED);
            if (Build.VERSION.SDK_INT >= 33)
                registerReceiver(resumeReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
            else registerReceiver(resumeReceiver, filter);
        } catch (RuntimeException ignored) { resumeReceiver = null; }
    }

    private void onNetworkChange() {
        networkSignal = SystemClock.elapsedRealtime();
        queueCheck(false, "network");
    }

    private synchronized void queueCheck(boolean requested, String source) {
        if (!scheduled || !new AppPrefs(this).monitorEnabled()) return;
        if (requested || !pendingRequested) pendingSource = source;
        pendingRequested |= requested;
        if (!checkQueued) schedulePendingCheck(0);
    }

    private synchronized void schedulePendingCheck(long delayMs) {
        checkQueued = true;
        try {
            monitorWorker.schedule(this::runPendingCheck, delayMs, TimeUnit.MILLISECONDS);
        } catch (RejectedExecutionException ignored) {
            checkQueued = false;
            pendingSource = null;
            pendingRequested = false;
        }
    }

    private void runPendingCheck() {
        String source;
        boolean requested;
        synchronized (this) {
            long delay = lastCheckElapsed + 5000L - SystemClock.elapsedRealtime();
            if (scheduled && !pendingRequested && delay > 0) {
                schedulePendingCheck(delay);
                return;
            }
            source = pendingSource;
            requested = pendingRequested;
            pendingSource = null;
            pendingRequested = false;
        }
        try {
            if (scheduled && new AppPrefs(this).monitorEnabled()) runSafe(requested, source);
        } finally {
            synchronized (this) {
                checkQueued = false;
                if (scheduled && pendingSource != null) schedulePendingCheck(0);
            }
        }
    }

    private void runSafe(boolean requested, String source) {
        if (Thread.currentThread().isInterrupted() || !scheduled || !session.equals(activeSession)) return;
        long now = SystemClock.elapsedRealtime();
        long uptimeNow = SystemClock.uptimeMillis();
        // A newly recreated service can still recover a sampling gap from
        // the previous service session; a monotonic clock rewind is ignored.
        long previousSample = lastCheckElapsed > 0 ? lastCheckElapsed
                : getSharedPreferences(SNAPSHOT, MODE_PRIVATE).getLong("sample_elapsed", -1L);
        long gap = previousSample >= 0 && now >= previousSample ? now - previousSample : -1;
        long uptimeGap = lastCheckUptime > 0 ? uptimeNow - lastCheckUptime : -1;
        lastCheckElapsed = now;
        lastCheckUptime = uptimeNow;
        boolean trace = lastLoggedCheckElapsed == 0 || now - lastLoggedCheckElapsed >= 60000
                || gap > 30000;
        try (TransactionLock lease = new TransactionLock("sample", 120000L)) {
            // Log after obtaining the bounded lease. Previously this always
            // reported wake_lock=false for smart mode, even during active work.
            MonitorWatchdog.releaseHandoff();
            if (trace || !"periodic".equals(source)) {
                lastLoggedCheckElapsed = now;
                PowerManager power = getSystemService(PowerManager.class);
                logRuntime(this, "check_started", "gap_ms=" + gap
                        + "; suspend_ms=" + (gap < 0 || uptimeGap < 0 ? -1 : Math.max(0, gap - uptimeGap))
                        + "; screen=" + (power != null && power.isInteractive() ? "on" : "off")
                        + "; idle=" + (power != null && power.isDeviceIdleMode())
                        + "; wake_lock=" + isCpuWakeLockHeld()
                        + "; transaction_lock=" + lease.isHeld()
                        + "; wake_mode=" + new AppPrefs(this).wakeMode()
                        + "; source=" + source
                        + "; requested=" + requested);
            }
            try {
                AppPrefs prefs = new AppPrefs(this);
                boolean gapRescue = gap >= RESCUE_GAP_MS && prefs.monitorEnabled()
                        && prefs.autoReconnect() && AppPrefs.WAKE_SMART.equals(prefs.wakeMode());
                if (gapRescue) {
                    // Sampling gap, not watchdog origin, controls the rescue.
                    // First take a normal-status reading without poll auto_recovery.
                    runOnce(true, false);
                    JSONObject observed = lastSnapshot(this);
                    if ("ready".equals(recoveryGate())
                            && sampleAgeSeconds(this) >= 0 && sampleAgeSeconds(this) <= 15
                            && currentError(this).isEmpty()
                            && MonitorStatus.hasStateEvidence(observed.optString("fcm_source"))
                            && ("disconnected".equals(observed.optString("fcm_state"))
                                || "connecting".equals(observed.optString("fcm_state")))) {
                        runRescueEpisode(now + 120000L);
                    }
                } else runOnce(requested);
            }
            catch (RuntimeException error) {
                if (scheduled && session.equals(activeSession)) recordFailure(error);
            }
        } finally {
            long duration = SystemClock.elapsedRealtime() - now;
            if (trace || !"periodic".equals(source) || duration > 15000)
                logRuntime(this, "check_finished", "source=" + source + "; duration_ms=" + duration
                        + "; result=" + lastAttemptState(this)
                        + "; error=" + (currentError(this).isEmpty() ? "none" : "present"));
            if (PrivilegeAccess.canRunInBackground(this)) refreshNotification();
        }
    }

    private void recordFailure(Exception error) {
        failureStreak = Math.min(failureStreak + 1, 4);
        long backoff = Math.min(30000L, 15000L << (failureStreak - 1));
        nextAttemptElapsed = SystemClock.elapsedRealtime() + backoff;
        getSharedPreferences(SNAPSHOT, MODE_PRIVATE).edit()
                .putString("error", safeError(error))
                .putString("error_session", session)
                .putString("error_mode", new AppPrefs(this).connectionKey())
                .putString("attempt_state", "failed")
                .putLong("next_attempt_elapsed", nextAttemptElapsed).apply();
        logRuntime(this, "sample_failed", "retry_ms=" + backoff + "; " + safeError(error));
    }

    static String describeNativeReason(String value) {
        switch (value) {
            case "not_used": return "本轮不调用原生 dump；以 GMS UID 内核 Socket 证据为准";
            case "none": return "";
            default: return "未识别到原生状态";
        }
    }
    private void runOnce(boolean requested) { runOnce(requested, true); }

    private void runOnce(boolean requested, boolean normalRecovery) {
        AppPrefs p = new AppPrefs(this);
        if ((!p.monitorEnabled() && !p.guardEnabled()) || !PrivilegeAccess.canRunInBackground(this)) {
            main.post(() -> stopIfIneligible(newestStartId));
            return;
        }
        final String attemptKey = p.connectionKey();
        boolean modeChanged = !attemptKey.equals(lastAttemptKey);
        if (p.monitorEnabled() && (requested || modeChanged || SystemClock.elapsedRealtime() >= nextAttemptElapsed)) {
            lastAttemptKey = attemptKey;
            getSharedPreferences(SNAPSHOT, MODE_PRIVATE).edit()
                    .putLong("attempt_time", System.currentTimeMillis())
                    .putString("attempt_state", "running")
                    .putLong("next_attempt_elapsed", 0).apply();
            try {
                String mode = p.mode();
                String key = p.connectionKey();
                if (!installed || !key.equals(installedMode)) {
                    installed = false;
                    installScript(p, mode);
                    installedMode = key;
                    installed = true;
                }
                if (!p.monitorEnabled() || !key.equals(p.connectionKey())) return;
                String prefix = monitorPrefix(p, mode);
                String result = execute(p, mode, prefix + (normalRecovery ? "monitor" : "status")
                        + " >/dev/null 2>&1 || exit 9; "
                        + "echo BERRY_JSON_BEGIN; " + prefix + "snapshot; "
                        + "echo BERRY_EVENTS_BEGIN; " + prefix + "events");
                int jsonStart = result.indexOf("BERRY_JSON_BEGIN\n");
                int eventsStart = result.indexOf("\nBERRY_EVENTS_BEGIN");
                if (jsonStart < 0 || eventsStart <= jsonStart)
                    throw new IllegalStateException("监测脚本未返回完整状态");
                String json = result.substring(jsonStart + "BERRY_JSON_BEGIN\n".length(), eventsStart).trim();
                JSONObject parsed = new JSONObject(json);
                if (!parsed.has("fcm_source") || !parsed.has("fcm_native_reason"))
                    throw new IllegalStateException("监测脚本版本不匹配");
                String events = result.substring(eventsStart + "\nBERRY_EVENTS_BEGIN".length()).trim();
                if (!scheduled || !session.equals(activeSession) || !p.monitorEnabled()
                        || !key.equals(p.connectionKey())) return;
                updateConfirmationWindow(parsed);
                recordEnvironment(parsed);
                json = parsed.toString();
                failureStreak = 0;
                nextAttemptElapsed = 0;
                getSharedPreferences(SNAPSHOT, MODE_PRIVATE).edit()
                        .putString("sample_session", session)
                        .putString("sample_mode", key)
                        .putLong("sample_elapsed", SystemClock.elapsedRealtime())
                        .putLong("next_attempt_elapsed", 0)
                        .putString("json", json).putString("events", events)
                        .remove("error").putString("attempt_state", "success").apply();
            } catch (Exception error) {
                if (!Thread.currentThread().isInterrupted() && attemptKey.equals(p.connectionKey())
                        && scheduled && session.equals(activeSession) && p.monitorEnabled()) recordFailure(error);
                installed = false;
            }
        }
    }


    /** Make one bounded request after a long sampling gap. The normal monitor
     * handles subsequent retries using its existing backoff. */
    private void runRescueEpisode(long deadline) {
        AppPrefs prefs = new AppPrefs(this);
        String key = prefs.connectionKey();
        if (!rescueAllowed(prefs, key) || SystemClock.elapsedRealtime() + 50000L >= deadline) return;

        long now = SystemClock.elapsedRealtime();
        SharedPreferences stored = getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
        long last = stored.getLong("rescue_started_elapsed", -1);
        if (last > 0 && now >= last && now - last < RESCUE_COOLDOWN_MS) {
            logRuntime(this, "rescue_skipped", "cooldown_ms=" + (RESCUE_COOLDOWN_MS - (now - last)));
            return;
        }
        try {
            String mode = prefs.mode();
            JSONObject outcome = readRescueStatus(prefs, mode,
                    monitorPrefix(prefs, mode) + "rescue >/dev/null 2>&1 || exit 9; ");
            String decision = outcome.optString("fcm_recovery_decision");
            logRuntime(this, "rescue_finished", "decision=" + decision
                    + "; connected_observed=" + connectionObserved(outcome));
            if ("requested".equals(decision) || "request_failed".equals(decision)
                    || "recovery_exhausted".equals(decision)) {
                stored.edit().putLong("rescue_started_elapsed", now).apply();
                monitorWorker.schedule(() -> {
                    if (rescueAllowed(prefs, key)) queueCheck(false, "rescue_followup");
                }, 12, TimeUnit.SECONDS);
            }
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
        } catch (Exception error) {
            logRuntime(this, "rescue_failed", safeError(error));
        }
    }

    private boolean rescueAllowed(AppPrefs prefs, String key) {
        return scheduled && session.equals(activeSession) && prefs.monitorEnabled()
                && prefs.autoReconnect() && AppPrefs.WAKE_SMART.equals(prefs.wakeMode())
                && key.equals(prefs.connectionKey())
                && PrivilegeAccess.canRunInBackground(this)
                && !Thread.currentThread().isInterrupted();
    }

    private static boolean connectionObserved(JSONObject value) {
        return MonitorStatus.hasStateEvidence(value.optString("fcm_source"))
                && "connected".equals(value.optString("fcm_state"));
    }

    private JSONObject readRescueStatus(AppPrefs prefs, String mode, String command) throws Exception {
        String result = execute(prefs, mode, command + "echo BERRY_JSON_BEGIN; "
                + monitorPrefix(prefs, mode) + "snapshot");
        int start = result.indexOf("BERRY_JSON_BEGIN\n");
        if (start < 0) throw new IllegalStateException("未收到恢复状态快照");
        JSONObject value = new JSONObject(result.substring(start + "BERRY_JSON_BEGIN\n".length()).trim());
        if (!value.has("fcm_source") || !value.has("fcm_recovery_decision"))
            throw new IllegalStateException("恢复状态字段缺失");
        return value;
    }

    private void runGuardSafe() {
        if (!scheduled || !session.equals(activeSession) || Thread.currentThread().isInterrupted()) return;
        AppPrefs p = new AppPrefs(this);
        if (!p.guardEnabled() || !PrivilegeAccess.canRunInBackground(this)) return;
        long now = SystemClock.elapsedRealtime();
        if (lastGuardAt != 0 && now >= lastGuardAt
                && now - lastGuardAt < TimeUnit.MINUTES.toMillis(5)) return;
        lastGuardAt = now;
        String key = p.connectionKey();
        String mode = p.mode();
        try {
            StringBuilder reports = new StringBuilder();
            // A single target per transaction bounds how long FCM may wait for Shell.
            for (String command : GuardOps.commandBatches(p.guardTargets(), true, 1)) {
                if (Thread.currentThread().isInterrupted() || !scheduled || !p.guardEnabled()
                        || !key.equals(p.connectionKey())) return;
                try (TransactionLock lease = new TransactionLock("guard", 60000L)) {
                    // If monitoring is also enabled, only its own worker may
                    // finish the watchdog handoff; guard must not release it early.
                    if (!p.monitorEnabled()) MonitorWatchdog.releaseHandoff();
                    reports.append(execute(p, mode, command)).append("\n");
                }
            }
            if (!scheduled || !p.guardEnabled() || !key.equals(p.connectionKey())) return;
            String report = reports.toString().trim();
            // Unstopping an app is not evidence that GMS is disconnected;
            // only the FCM monitor may request a recovery heartbeat.
            getSharedPreferences("berry_fcm_guard_report", MODE_PRIVATE).edit()
                    .putString("report", report).putLong("last_run", System.currentTimeMillis()).apply();
        } catch (Exception error) {
            if (scheduled && session.equals(activeSession) && p.guardEnabled()
                    && key.equals(p.connectionKey()) && !Thread.currentThread().isInterrupted())
                getSharedPreferences("berry_fcm_guard_report", MODE_PRIVATE).edit()
                        .putString("report", "守护检查失败：" + safeError(error))
                        .putLong("last_run", System.currentTimeMillis()).apply();
        }
    }

    private void manualReconnectInternal() {
        AppPrefs p = new AppPrefs(this);
        if (!scheduled || !session.equals(activeSession) || !p.monitorEnabled()
                || !PrivilegeAccess.canRunInBackground(this)) return;
        String mode = p.mode();
        String key = p.connectionKey();
        try {
            if (!installed || !key.equals(installedMode)) {
                installScript(p, mode);
                installed = true;
                installedMode = key;
            }
            if (!scheduled || !p.monitorEnabled() || !key.equals(p.connectionKey())) return;
            String prefix = monitorPrefix(p, mode);
            String result = execute(p, mode, prefix + "reconnect >/dev/null || exit 9; "
                    + "echo BERRY_MANUAL_RESULT; " + prefix + "snapshot");
            int offset = result.indexOf("BERRY_MANUAL_RESULT\n");
            if (offset < 0) throw new IllegalStateException("重连脚本未返回结果");
            JSONObject reply = new JSONObject(result.substring(offset + "BERRY_MANUAL_RESULT\n".length()).trim());
            String decision = reply.optString("fcm_recovery_decision");
            String message;
            switch (decision) {
                case "requested": message = "广播已返回，尚未确认 FCM 恢复"; break;
                case "confirmation_recovered": message = "复采已观察到 FCM 长连接建立"; break;
                case "recovery_exhausted": message = "本轮恢复流程已结束，复采未确认 FCM 恢复"; break;
                case "state_save_failed": message = "恢复状态保存失败，请查看恢复记录"; break;
                case "request_failed": message = "广播请求失败，请查看恢复记录中的 UID 和错误"; break;
                case "cooldown": message = "未发送广播：距上次请求不足60秒"; break;
                case "network_gate": message = "未发送广播：当前无活动网络"; break;
                case "not_disconnected": message = "没有发送恢复请求：" + ("connected".equals(reply.optString("fcm_state"))
                        ? "Google 推送当前已连接，不会产生新重连事件" : "Google 推送状态无法确认"); break;
                default: message = "重连结果未确认，见恢复记录"; break;
            }
            saveManualResult(key, message);
            if (key.equals(p.connectionKey())) {
                runSafe(true, "manual_followup");
                JSONObject latest = lastSnapshot(this);
                if (key.equals(p.connectionKey()) && "gms_socket".equals(latest.optString("fcm_source"))
                        && "connected".equals(latest.optString("fcm_state"))
                        && sampleAgeSeconds(this) >= 0 && sampleAgeSeconds(this) <= 90
                        && currentError(this).isEmpty() && "requested".equals(decision)) {
                    saveManualResult(key, message + "；随后检查已连接（不能证明由请求导致）");
                }
            }
        } catch (Exception error) {
            saveManualResult(key, "手动重连执行异常：" + safeError(error));
            if (scheduled && session.equals(activeSession) && p.monitorEnabled() && key.equals(p.connectionKey()))
                getSharedPreferences(SNAPSHOT, MODE_PRIVATE).edit()
                        .putString("error", "手动重连请求失败：" + safeError(error))
                        .putString("error_session", session)
                        .putString("error_mode", key).apply();
        }
    }

    private static String transportName(NetworkCapabilities caps) {
        if (caps == null) return "unknown";
        StringBuilder names = new StringBuilder();
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) names.append("VPN+");
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) names.append("WiFi+");
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) names.append("Cell+");
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) names.append("Ethernet+");
        return names.length() == 0 ? "other" : names.substring(0, names.length() - 1);
    }

    // Sample context, not GMS route: do not log SSIDs, addresses, or tokens.
    // Environment changes are event-driven by the existing sample and add
    // no probes or privileged commands.
    private void recordEnvironment(JSONObject snapshot) throws org.json.JSONException {
        String network = "unknown", validated = "unknown";
        String screen = "unknown", idle = "unknown", powerSave = "unknown", gmsExempt = "unknown";
        try {
            ConnectivityManager manager = getSystemService(ConnectivityManager.class);
            if (manager != null) {
                Network active = manager.getActiveNetwork();
                if (active == null) network = "none";
                else {
                    NetworkCapabilities caps = manager.getNetworkCapabilities(active);
                    network = transportName(caps);
                    if (caps != null) validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) ? "yes" : "no";
                }
            }
        } catch (RuntimeException ignored) { }
        try {
            PowerManager power = getSystemService(PowerManager.class);
            if (power != null) {
                screen = power.isInteractive() ? "on" : "off";
                idle = power.isDeviceIdleMode() ? "yes" : "no";
                powerSave = power.isPowerSaveMode() ? "yes" : "no";
                gmsExempt = power.isIgnoringBatteryOptimizations(GuardOps.GMS) ? "yes" : "no";
            }
        } catch (RuntimeException ignored) { }
        JSONObject env = new JSONObject();
        env.put("network", network);
        env.put("android_validated", validated);
        env.put("screen", screen);
        env.put("device_idle", idle);
        env.put("power_save", powerSave);
        env.put("gms_doze_exempt", gmsExempt);
        snapshot.put("app_environment", env);
        String state = snapshot.optString("fcm_state", "unknown");
        String description = "FCM 状态=" + MonitorActivity.connectionLabel(state) + "，应用网络=" + network
                + "，系统已验证网络=" + yesNo(validated) + "，屏幕=" + ("on".equals(screen) ? "亮" : "off".equals(screen) ? "熄" : "未知")
                + "，设备闲置=" + yesNo(idle) + "，省电模式=" + yesNo(powerSave)
                + "，GMS 在电池优化白名单=" + yesNo(gmsExempt);
        SharedPreferences stored = getSharedPreferences(SNAPSHOT, MODE_PRIVATE);
        if (description.equals(stored.getString("environment_key", ""))
                && session.equals(stored.getString("environment_session", ""))) return;
        if (appendDiagnostic(this, "environment_events", "environment", description)) {
            stored.edit().putString("environment_key", description)
                    .putString("environment_session", session).apply();
        }
    }

    private static String yesNo(String value) {
        return "yes".equals(value) ? "是" : "no".equals(value) ? "否" : "未知";
    }

    private static String appVersion(Context context) {
        try {
            return context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName;
        } catch (android.content.pm.PackageManager.NameNotFoundException error) {
            return "未知";
        }
    }

    private static String safeError(Exception error) {
        String message = error.getMessage();
        return message == null ? "后台监测执行失败" : message;
    }

    private static String workDir(String mode) {
        if (AppPrefs.SHIZUKU.equals(mode)) return ShizukuShell.authorizedUid() == 0
                ? "/data/local/tmp/berry_fcm_shizuku_root" : "/data/local/tmp/berry_fcm_apk";
        return AppPrefs.ROOT.equals(mode) ? "/data/adb/berry_fcm_apk" : "/data/local/tmp/berry_fcm_apk";
    }
    // This is the app's default network, not proof of GMS's route or reachability.
    // It is used only to defer automatic intervention during a network change.
    private String recoveryGate() {
        try {
            ConnectivityManager manager = getSystemService(ConnectivityManager.class);
            if (manager == null) return "unavailable";
            Network current = manager.getActiveNetwork();
            long now = SystemClock.elapsedRealtime();
            long signal = networkSignal;
            if (signal != consumedNetworkSignal) {
                consumedNetworkSignal = signal;
                networkChangedAt = now;
            }
            if (current == null) {
                observedNetwork = null;
                networkChangedAt = now;
                return "offline";
            }
            if (!current.equals(observedNetwork)) {
                observedNetwork = current;
                networkChangedAt = now;
            }
            long remaining = 15000L - (now - networkChangedAt);
            if (remaining <= 0) return "ready";
            if (networkRecheck == null || networkRecheck.isDone()) {
                networkRecheck = monitorWorker.schedule(
                        () -> queueCheck(false, "network_settled"), remaining, TimeUnit.MILLISECONDS);
            }
            return "settling";
        } catch (RuntimeException error) {
            return "unavailable";
        }
    }
    private String monitorPrefix(AppPrefs prefs, String mode) {
        String dir = workDir(mode);
        return "BERRY_FCM_AUTO=" + (prefs.autoReconnect() ? "1" : "0")
                + " BERRY_AUTO_GATE=" + recoveryGate()
                + " BERRY_FCM_DATA=" + dir
                + (AppPrefs.ROOT.equals(mode) ? "" : " BERRY_FCM_ADB_SHELL=1")
                + " /system/bin/sh " + dir + "/fcm-monitor.sh ";
    }
    private String stageScript(String directory, String name) throws java.io.IOException {
        byte[] script;
        try (InputStream input = getAssets().open(name);
                java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = input.read(buffer)) >= 0) out.write(buffer, 0, read);
            script = out.toByteArray();
        }
        String dest = directory + "/" + name;
        String temp = dest + ".new";
        return "printf '%s' '" + Base64.encodeToString(script, Base64.NO_WRAP) + "' | base64 -d > " + temp
                + " && /system/bin/sh -n " + temp + " && chmod 700 " + temp
                + " && mv -f " + temp + " " + dest;
    }

    private void installScript(AppPrefs prefs, String mode) throws Exception {
        String dir = workDir(mode);
        String result = execute(prefs, mode, "umask 077; mkdir -p " + dir
                + " && " + stageScript(dir, "diagnostic-logs.sh")
                + " && " + stageScript(dir, "fcm-monitor.sh")
                + " && echo 1 > " + dir + "/enabled && echo BERRY_INSTALL_OK");
        if (!result.trim().endsWith("BERRY_INSTALL_OK"))
            throw new IllegalStateException("监测脚本安装未通过确认");
    }

    static String fullMonitorEvents(Context context) throws Exception {
        AppPrefs prefs = new AppPrefs(context);
        try (PrivilegeShell shell = PrivilegeAccess.open(context)) {
            String dir = workDir(prefs.mode());
            String script = dir + "/fcm-monitor.sh";
            return shell.execute("if [ -f " + script + " ]; then BERRY_FCM_DATA=" + dir
                    + " BERRY_FCM_ADB_SHELL=1 /system/bin/sh " + script + " events all; fi");
        }
    }

    private String execute(AppPrefs prefs, String mode, String command) throws Exception {
        // Monitor and guard use independent Shell commands. The legacy static
        // ADB transport remains serialized by AdbConnectionManager.executeOnce.
        long started = SystemClock.elapsedRealtime();
        try {
        if (AppPrefs.ROOT.equals(mode)) {
            try (PrivilegeShell shell = new RootShell(this)) {
                String result = shell.execute(command);
                if (mode.equals(prefs.mode())) prefs.shellVerified("uid=0(root)");
                return result;
            } catch (Exception error) {
                if (mode.equals(prefs.mode())) prefs.shellFailed(error.getMessage());
                throw error;
            }
        }
        if (AppPrefs.SHIZUKU.equals(mode)) {
            try (PrivilegeShell shell = new ShizukuShell(this)) {
                int uid = ShizukuShell.authorizedUid();
                if (uid < 0) throw new IllegalStateException(ShizukuShell.readiness());
                String result = shell.execute(command);
                if (mode.equals(prefs.mode())) prefs.shellVerified(uid == 0 ? "uid=0(root)" : "uid=2000(shell)");
                return result;
            } catch (Exception error) {
                // A failed command is not proof that the Shizuku authorization
                // was revoked. Do not overwrite a parallel successful probe.
                if (mode.equals(prefs.mode()) && (!ShizukuShell.isRunning() || ShizukuShell.authorizedUid() < 0))
                    prefs.shellFailed(error.getMessage());
                throw error;
            }
        }
        if (!AppPrefs.WIRELESS.equals(mode) && !AppPrefs.STATIC.equals(mode))
            throw new IllegalStateException("请先在授权中心选择 Root 或 ADB");
        try {
            String result;
            if (AppPrefs.WIRELESS.equals(mode)) {
                result = PrivKitShell.execute(this, command);
            } else {
                if (adb == null) adb = AdbConnectionManager.get(this);
                result = adb.executeOnce(this, mode, prefs.host(), prefs.staticPort(), command);
            }
            if (mode.equals(prefs.mode())) prefs.shellVerified("uid=2000(shell)");
            return result;
        } catch (Exception error) {
            // Guard and FCM commands may now overlap; a command-level error
            // must not invalidate a still-live UID 2000 Binder.
            if (mode.equals(prefs.mode()) && (!AppPrefs.WIRELESS.equals(mode)
                    || !PrivKitShell.isConnected()))
                prefs.shellFailed(error.getMessage());
            throw error;
        }
        } finally {
            long duration = SystemClock.elapsedRealtime() - started;
            if (duration > 2000)
                logRuntime(this, "shell_duration", "mode=" + mode + "; duration_ms=" + duration);
        }
    }
    @Override public void onDestroy() {
        logRuntime(this, "service_destroyed", "pid=" + android.os.Process.myPid());
        scheduled = false;
        if (session.equals(activeSession)) activeSession = "";
        if (networkManager != null && networkCallback != null) {
            try { networkManager.unregisterNetworkCallback(networkCallback); }
            catch (RuntimeException ignored) { }
        }
        if (resumeReceiver != null) {
            try { unregisterReceiver(resumeReceiver); }
            catch (RuntimeException ignored) { }
        }
        main.removeCallbacksAndMessages(null);
        if (periodic != null) periodic.cancel(true);
        if (guardPeriodic != null) guardPeriodic.cancel(true);
        releasePersistentWakeLock();
        releaseConfirmationWakeLock();
        MonitorWatchdog.releaseHandoff();
        if (live == this) live = null;
        monitorWorker.shutdownNow();
        guardWorker.shutdownNow();
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
