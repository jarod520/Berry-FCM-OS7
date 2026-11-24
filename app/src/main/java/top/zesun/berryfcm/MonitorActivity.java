package top.zesun.berryfcm;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.Switch;
import android.widget.Button;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;
import org.json.JSONObject;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MonitorActivity extends Ui {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView headline, current, technical, events, eventsFull, runtimeEvents, environmentEvents, manualResult, reconnectHint;
    private Button checkButton, reconnectButton;
    private Switch enabled, automatic;
    private final Runnable update = new Runnable() {
        @Override public void run() { render(); ui.postDelayed(this, 10000); }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        title("FCM 监控", "连接状态、检查记录与断开事件");
        LinearLayout control = card("当前状态", "在后台检查 FCM 连接是否正常。");
        headline = text("等待检查", 22, true, muted);
        control.addView(headline);
        current = text("读取中…", 14, false, muted);
        current.setTextIsSelectable(true);
        current.setPadding(0, dp(8), 0, dp(10));
        control.addView(current);
        enabled = new Switch(this);
        enabled.setText("后台持续监控");
        enabled.setTextColor(ink);
        enabled.setMinHeight(dp(48));
        enabled.setChecked(prefs.monitorEnabled());
        control.addView(enabled);
        enabled.setOnCheckedChangeListener((b, value) -> {
            if (bindingSwitches()) return;
            if (value && !authorizationReady()) {
                syncChecked(enabled, prefs.monitorEnabled());
                error("请先完成授权");
                go(AuthActivity.class);
                return;
            }
            prefs.monitorEnabled(value);
            if (value) FcmMonitorService.start(this);
            else if (!prefs.guardEnabled()) FcmMonitorService.stop(this);
            render();
        });
        automatic = new Switch(this);
        automatic.setText("断开后自动请求恢复");
        automatic.setTextColor(ink);
        automatic.setMinHeight(dp(48));
        automatic.setChecked(prefs.autoReconnect());
        control.addView(automatic);
        automatic.setOnCheckedChangeListener((button, enabledAuto) -> {
            if (bindingSwitches()) return;
            prefs.autoReconnect(enabledAuto);
            if (prefs.monitorEnabled() && authorizationReady() && FcmMonitorService.isRunning()) FcmMonitorService.checkNow(this);
            render();
        });
        checkButton = button(control, "立即检查", () -> {
            if (!authorizationReady()) { go(AuthActivity.class); return; }
            // The worker remains inside the same service; do not run an independent
            // shell concurrently or overwrite the single-writer state file.
            if (!prefs.monitorEnabled()) prefs.monitorEnabled(true);
            syncChecked(enabled, prefs.monitorEnabled());
            FcmMonitorService.checkNow(this);
            render();
        }, true);
        reconnectButton = button(control, "尝试恢复断开的连接", this::reconnect, false);
        reconnectHint = text("", 12, false, muted);
        control.addView(reconnectHint);
        manualResult = text("", 13, false, muted);
        manualResult.setTextIsSelectable(true);
        control.addView(manualResult);
        manualResult.setVisibility(View.GONE);
        LinearLayout extra = disclosure(control, "连接详情", false);
        technical = text("暂无详细数据", 13, false, ink);
        technical.setTextIsSelectable(true);
        extra.addView(technical);

        LinearLayout timeline = card("最新事件", "最近的连接、断联与恢复记录。");
        events = text("暂无记录", 13, false, ink);
        events.setTextIsSelectable(true);
        timeline.addView(events);
        LinearLayout history = disclosure(timeline, "历史事件", false);
        eventsFull = text("暂无历史记录", 13, false, ink);
        eventsFull.setTextIsSelectable(true);
        history.addView(eventsFull);
        LinearLayout runtime = disclosure(timeline, "熄屏巡检与唤醒记录", false);
        runtimeEvents = text("暂无巡检记录", 13, false, ink);
        runtimeEvents.setTextIsSelectable(true);
        runtime.addView(runtimeEvents);
        LinearLayout environment = disclosure(timeline, "网络与休眠记录", false);
        environmentEvents = text("暂无环境记录", 13, false, ink);
        environmentEvents.setTextIsSelectable(true);
        environment.addView(environmentEvents);
        line(timeline, "网络诊断", "Google 原生诊断和 TCP 可达性", () -> go(DiagnosticsActivity.class));
    }

    private boolean authorizationReady() {
        return PrivilegeAccess.readyForUserAction(this);
    }

    private void render() {
        if (current == null) return;
        boolean ready = authorizationReady();
        syncChecked(enabled, prefs.monitorEnabled());
        syncChecked(automatic, prefs.autoReconnect());
        checkButton.setText(!ready ? "去授权" : !prefs.monitorEnabled() ? "开启监控" : !FcmMonitorService.isRunning() ? "启动监控" : "立即检查");
        String manual = FcmMonitorService.manualReconnectResult(this);
        manualResult.setVisibility(manual.isEmpty() ? View.GONE : View.VISIBLE);
        manualResult.setText("最近一次手动操作：" + manual);
        JSONObject j = FcmMonitorService.lastSnapshot(this);
        long sample = j.optLong("fcm_sample_time", 0);
        long age = FcmMonitorService.sampleAgeSeconds(this);
        String lastError = FcmMonitorService.currentError(this);
        String state = j.optString("fcm_state", "never_seen");
        String stateSource = j.optString("fcm_source");
        boolean stateEvidence = MonitorStatus.hasStateEvidence(stateSource);
        long attempt = FcmMonitorService.lastAttemptAt(this);
        long serviceStart = FcmMonitorService.lastStartAt(this);
        if (!prefs.monitorEnabled()) state = "监控未开启";
        else if (!FcmMonitorService.isRunning()) state = "后台服务未运行";
        else if (AppPrefs.WIRELESS.equals(prefs.mode()) && !PrivKitShell.isConnected())
            state = "独立服务未运行";
        else if (!lastError.isEmpty()) state = "最近一次检查失败";
        else if (sample <= 0 && (attempt > 0 || serviceStart > 0)) state = "waiting";
        else if (age < 0) state = "waiting";
        else if (age > 90) state = "检查数据过期";
        else if (!stateEvidence) state = "暂无有效状态样本";
        MonitorStatus.State verdict = MonitorStatus.resolve(ready, prefs.monitorEnabled(),
                FcmMonitorService.isRunning(), sample > 0 ? age : -1,
                !lastError.isEmpty(), stateEvidence, j.optString("fcm_state"));
        headline.setText(MonitorStatus.label(verdict, stateSource));
        headline.setTextColor(statusColor(verdict));
        boolean disconnectedNow = verdict == MonitorStatus.State.DISCONNECTED
                || verdict == MonitorStatus.State.CONNECTING;
        reconnectButton.setVisibility(disconnectedNow ? View.VISIBLE : View.GONE);
        reconnectButton.setEnabled(disconnectedNow && !manual.startsWith("正在读取"));
        reconnectHint.setText(verdict == MonitorStatus.State.CONNECTED
                ? "当前有连接证据，无需恢复。只有确认断联后才会显示恢复按钮。"
                : disconnectedNow
                ? "仅向 Google 推送请求恢复，不会强制断开；是否发送和结果请看下方记录。"
                : "尚未确认断开，不发送恢复请求。可先点“立即检查”。");
        String nativeReason = FcmMonitorService.describeNativeReason(j.optString("fcm_native_reason", "unrecognized"));
        String gate = j.optString("fcm_auto_gate", "unavailable");
        int retryIn = j.optInt("fcm_retry_in", 0);
        String progress = AppPrefs.WIRELESS.equals(prefs.mode()) && !PrivKitShell.isConnected()
                ? PrivKitShell.status() + "；可以在连接设置中启动服务，无需重新配对。"
                : FcmMonitorService.currentError(this).isEmpty()
                ? "后台将持续检查；如长时间无数据，请检查通知及系统后台策略。"
                : "后台正在自动重试，无需手动重复配对。";
        String durationLine = "";
        if ("gms_socket".equals(stateSource) && "connected".equals(state))
            durationLine = "\n" + MonitorStatus.connectedDuration(Math.max(j.optLong("fcm_connected_seconds", 0), j.optLong("fcm_observed_up_seconds", 0)));
        else if (("connecting".equals(state) || "disconnected".equals(state))
                && j.optLong("fcm_observed_down_seconds", -1) >= 0)
            durationLine = "\n已观察未连接：" + MonitorStatus.duration(j.optLong("fcm_observed_down_seconds"));
        current.setText("最近检查：" + (sample <= 0 ? "暂无" : time(sample)
                + (age < 0 ? "（上次运行的记录）" : "（" + age + " 秒前）"))
                + (prefs.monitorEnabled() && sample > 0 && age >= 0 && age <= 90
                    && !stateEvidence && lastError.isEmpty() ? "\n原因：" + nativeReason : "")
                + durationLine
                + (attempt > 0 ? "\n上次检查尝试：" + time(attempt / 1000) : "")
                + (stateEvidence && ("connecting".equals(state) || "disconnected".equals(state))
                    ? "\n恢复策略：" + (!prefs.autoReconnect() ? "仅监测" : "settling".equals(gate)
                        ? "等待网络稳定" : "offline".equals(gate) ? "当前无活动网络"
                        : "unavailable".equals(gate) ? "网络信息不可读取，自动恢复暂停"
                        : recoveryDecision(j, retryIn)) : "")
                + (stateEvidence && ("connecting".equals(state) || "disconnected".equals(state))
                    ? "\n恢复请求：" + j.optInt("fcm_attempts", 0) + " 次 · "
                        + recoveryLabel(j.optString("fcm_last_result", "none")) : "")
                + "\n" + FcmMonitorService.serviceStatus(this)
                + (FcmMonitorService.nextAttemptIn(this) > 0 ? " · " + FcmMonitorService.nextAttemptIn(this) + " 秒后重试" : "")
                + "\n" + progress
                + (lastError.isEmpty() ? "" : "\n检查异常：" + lastError));
        if (!ready) current.setText("完成核心授权后才能检查 FCM 连接；下方记录仅供查看历史。");
        else if (!prefs.monitorEnabled()) current.setText("监控未开启，点击下方按钮开启。");
        else if (!FcmMonitorService.isRunning()) current.setText("监控未运行，请点击下方按钮启动。");
        JSONObject env = j.optJSONObject("app_environment");
        technical.setText((age < 0 || age > 90 || !ready || !prefs.monitorEnabled()
                || !lastError.isEmpty() ? "以下为历史数据。\n" : "")
                + "原始状态：" + state
                + "\n状态来源：" + ("gms_socket".equals(stateSource) ? "GMS UID 的精确 MCS TCP 正向证据"
                    : "gms_socket_absence".equals(stateSource) ? "内核 Socket 连续 MCS TCP 缺失证据"
                    : "gms_socket_stalled".equals(stateSource) ? "TCP_INFO：MCS 连接卡死（重传/长时间无数据）"
                    : nativeReason)
                + "\nTCP 辅助检查：" + tcpHint(j.optString("fcm_tcp_hint", "none"))
                + "\n服务器：" + j.optString("fcm_transport", "无")
                + "  " + j.optString("fcm_remote", "")
                + (env == null ? "" : "\n检查环境（本应用）：" + env.optString("network", "unknown")
                    + " · 屏幕 " + localValue(env.optString("screen"))
                    + " · Doze " + localValue(env.optString("device_idle"))
                    + "\nGMS Doze 白名单：" + localValue(env.optString("gms_doze_exempt")))
                + "\n最后一次关闭错误：" + j.optString("fcm_last_close_code", "无")
                + "\n上次观察在线：" + time(j.optLong("fcm_last_seen", 0))
                + "\n最近一次历史断开：" + time(j.optLong("fcm_disconnect_since", 0))
                + "\n最近恢复观测：" + time(j.optLong("fcm_last_restore", 0))
                + "\n熄屏巡检方式：" + (AppPrefs.WAKE_CONTINUOUS.equals(prefs.wakeMode())
                    ? "持续唤醒" : "智能省电")
                + "\nCPU 唤醒锁：" + (FcmMonitorService.isCpuWakeLockHeld() ? "当前持有" : "未持有")
                + "\n累计持续持锁：" + MonitorStatus.duration(FcmMonitorService.continuousWakeMs(this) / 1000)
                + "\n累计确认窗口持锁：" + MonitorStatus.duration(FcmMonitorService.confirmationWakeMs(this) / 1000)
                + "\n累计任务持锁：" + MonitorStatus.duration(FcmMonitorService.transactionWakeMs(this) / 1000)
                + "\n历史已发送的恢复请求：" + j.optInt("fcm_attempts", 0) + " 次"
                + "\n连续恢复尝试次数：" + j.optInt("fcm_retry_streak", 0) + " 次"
                + "\n历史上次恢复请求结果：" + recoveryLabel(j.optString("fcm_last_result", "none")));
        String[] lines = FcmMonitorService.lastEvents(this).split("\n");
        events.setText(eventText(lines, 6));
        eventsFull.setText(eventText(lines, 24));
        runtimeEvents.setText(eventText(FcmMonitorService.lastRuntimeEvents(this).split("\\n"), 36));
        environmentEvents.setText(eventText(FcmMonitorService.lastEnvironmentEvents(this).split("\\n"), 24));
    }

    private static String tcpHint(String value) {
        switch (value) {
            case "established": return "发现相关 TCP 连接";
            case "connecting": return "发现正在建立的 TCP 连接";
            case "absent": return "未发现匹配的 TCP 连接";
            case "none": case "unknown": default: return "未取得独立证据（以 GMS UID 内核 Socket 检测为准）";
        }
    }

    private static String localValue(String value) {
        switch (value) {
            case "yes": return "是";
            case "no": return "否";
            case "on": return "亮屏";
            case "off": return "熄屏";
            default: return "未知";
        }
    }
    private String recoveryDecision(JSONObject j, int retryIn) {
        switch (j.optString("fcm_recovery_decision", "")) {
            case "requested": return "已请求 GMS 重连，等待原生确认";
            case "request_failed": return "重连请求失败，见恢复记录";
            case "confirmation_changed": return "第二次检查状态变化，暂不干预";
            case "cooldown": return "请求冷却约 " + retryIn + " 秒";
            case "recovery_exhausted": return "已依次尝试全部触发手段，内核复采仍未恢复；按退避等待下一轮";
            case "keepalive_nudged": return "内核证据不可用；已发送保活心跳（不判断联）";
            case "confirmation_recovered": return "第二次内核 Socket 检查已恢复，取消重连";
            case "waiting_confirmation": return "等待第二次内核 Socket 检查";
            case "waiting_duration":
                long seconds = j.optLong("fcm_observed_down_seconds", -1);
                return "尚未达到恢复条件" + (seconds < 0 ? "" : "（本轮已观察 " + seconds + " 秒）");
            default: return "等待有效恢复决策";
        }
    }
    private String recoveryLabel(String value) {
        switch (value) {
            case "requested": return "请求已提交，尚未确认恢复";
            case "failed": return "请求未确认";
            case "restored": return "请求后观察到原生恢复（不证明因果）";
            default: return "尚无请求";
        }
    }

    private String eventText(String[] lines, int maximum) {
        StringBuilder result = new StringBuilder();
        for (int i = lines.length - 1; i >= Math.max(0, lines.length - maximum); i--) {
            String[] parts = lines[i].split("\\|", 3);
            if (parts.length != 3) continue;
            String stamp;
            try { stamp = time(Long.parseLong(parts[0])); }
            catch (NumberFormatException ignored) { stamp = parts[0]; }
            String label = parts[1].equals("gms_close") ? "连接关闭"
                    : parts[1].equals("gms_connected") ? "连接成功"
                    : parts[1].equals("gms_failed") ? "连接失败"
                    : parts[1].equals("gms_network_attempt") ? "网络连接尝试"
                    : parts[1].equals("gms_heartbeat_delay") ? "心跳调度延迟"
                    : parts[1].equals("reconnect_requested") ? "已请求恢复"
                    : parts[1].equals("reconnect_failed") ? "恢复请求失败"
                    : parts[1].equals("recovery_confirmed") ? "二次采样确认仍未连接"
                    : parts[1].equals("recovery_socket_confirmed") ? "TCP 缺失确认断联"
                    : parts[1].equals("recovery_confirmation_unavailable") ? "复核未通过，未发送恢复"
                    : parts[1].equals("recovery_decision") ? "恢复决策"
                    : parts[1].equals("sample_unknown") ? "原生状态未返回"
                    : parts[1].equals("sample_dump") ? "原生输出摘要"
                    : parts[1].equals("socket_connected") ? "TCP 观察到连接"
                    : parts[1].equals("socket_connecting") ? "TCP 正在连接"
                    : parts[1].equals("tcp_absence_started") ? "TCP 缺失计时开始"
                    : parts[1].equals("tcp_absence_confirmed") ? "TCP 缺失确认断联"
                    : parts[1].equals("down_reconfirmed") ? "再次确认断联"
                    : parts[1].equals("connection_down") ? "确认 FCM 长连接未建立"
                    : parts[1].equals("connection_restored") ? "原生状态恢复"
                    : parts[1].equals("reconnect_skipped") ? "恢复请求跳过"
                    : parts[1].equals("watchdog_fired") ? "系统兜底闹钟触发"
                    : parts[1].equals("service_started") ? "后台服务启动"
                    : parts[1].equals("service_destroyed") ? "后台服务结束"
                    : parts[1].equals("check_started") ? "FCM 巡检开始"
                    : parts[1].equals("check_finished") ? "FCM 巡检完成"
                    : parts[1].equals("wake_lock_acquired") ? "CPU 唤醒锁获得"
                    : parts[1].equals("shell_duration") ? "Shell 执行耗时"
                    : parts[1].equals("sample_failed") ? "后台采样失败"
                    : parts[1].equals("sample_gap") ? "采样空档"
                    : parts[1].equals("environment") ? "检查环境变化（非 GMS 路由证据）" : parts[1];
            result.append(stamp).append("  ").append(label).append("\n")
                    .append(parts[2]).append("\n\n");
        }
        return result.length() == 0 ? "暂无监控事件" : result.toString().trim();
    }

    private void reconnect() {
        if (!authorizationReady()) { go(AuthActivity.class); return; }
        if (!prefs.monitorEnabled() || !FcmMonitorService.isRunning()) { error("请先开启 FCM 监控"); return; }
        JSONObject snapshot = FcmMonitorService.lastSnapshot(this);
        MonitorStatus.State verdict = MonitorStatus.resolve(true, true, true,
                FcmMonitorService.sampleAgeSeconds(this),
                !FcmMonitorService.currentError(this).isEmpty(),
                MonitorStatus.hasStateEvidence(snapshot.optString("fcm_source")),
                snapshot.optString("fcm_state"));
        if (verdict != MonitorStatus.State.DISCONNECTED
                && verdict != MonitorStatus.State.CONNECTING) {
            error("未确认断联，没有发送恢复请求。请先立即检查。");
            render();
            return;
        }
        worker.execute(() -> {
            try {
                String text = FcmMonitorService.manualReconnect(this);
                runOnUiThread(() -> { if (!isDestroyed()) { error(text); render(); } });
            } catch (Exception ex) {
                runOnUiThread(() -> error("重连请求失败：" + ex.getMessage()));
            }
        });
    }
    private String time(long seconds) {
        if (seconds <= 0) return "无";
        return new SimpleDateFormat("MM-dd HH:mm:ss", Locale.getDefault())
                .format(new Date(seconds * 1000));
    }
    @Override protected void onResume() {
        super.onResume();
        if (authorizationReady()) FcmMonitorService.resumeIfNeeded(this);
        ui.removeCallbacks(update);
        ui.post(update);
    }
    @Override protected void onPause() {
        ui.removeCallbacks(update);
        super.onPause();
    }
    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
