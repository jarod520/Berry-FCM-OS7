package top.zesun.berryfcm;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import org.json.JSONObject;

/** Overview: FCM first. Permission guidance appears only when action is needed. */
public final class MainActivity extends Ui {
    private TextView state, summary;
    private Button monitorButton;
    private boolean wasAuthorized;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Runnable refresh = new Runnable() {
        @Override public void run() {
            boolean ready = authorizationReady();
            if (ready && !wasAuthorized) FcmMonitorService.resumeIfNeeded(MainActivity.this);
            wasAuthorized = ready;
            render();
            ui.postDelayed(this, 2000);
        }
    };

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        title("BerryFCM", "For OriginOS7");

        LinearLayout monitor = card("FCM 监控", "检查 Google 推送连接是否正常");
        state = text("正在读取状态", 23, true, ink);
        monitor.addView(state);
        summary = text("", 13, false, muted);
        summary.setPadding(0, dp(8), 0, dp(6));
        monitor.addView(summary);
        monitorButton = button(monitor, "启动 FCM 监控", this::monitorAction, true);
        line(monitor, "监控详情", "连接状态与断开记录", () -> go(MonitorActivity.class));

        LinearLayout quick = card("常用功能", null);
        line(quick, "应用守护", "所选应用检查与恢复", () -> go(GuardActivity.class));
        line(quick, "网络诊断", "无需授权的 FCM TCP 可达性检测", () -> go(DiagnosticsActivity.class));
        line(quick, "授权管理", "连接授权与系统后台权限", () -> go(AuthActivity.class));
        line(quick, "后台保活", "任务运行与启动策略", () -> go(BackgroundActivity.class));
        render();
    }

    private boolean authorizationReady() {
        return PrivilegeAccess.readyForUserAction(this);
    }

    private void monitorAction() {
        if (!authorizationReady()) {
            go(AuthActivity.class);
            return;
        }
        if (!prefs.monitorEnabled() || !FcmMonitorService.isRunning()) {
            prefs.monitorEnabled(true);
            FcmMonitorService.start(this);
        } else {
            FcmMonitorService.checkNow(this);
        }
        render();
    }

    private void render() {
        if (state == null) return;
        boolean wireless = AppPrefs.WIRELESS.equals(prefs.mode());
        boolean enabled = prefs.monitorEnabled();
        monitorButton.setEnabled(true);
        state.setTextColor(muted);
        if (!authorizationReady()) {
            state.setTextColor(warning);
            if (wireless && AdbPairingService.isPairingActive()) {
                state.setText("正在进行 ADB 授权");
                summary.setText("请按照无线调试页面和通知栏的提示完成配对。");
                monitorButton.setText("查看授权步骤");
            } else if (wireless && PrivKitShell.isStarting()) {
                state.setText("正在启动服务…");
                summary.setText("正在连接无线调试，请保持无线网络连接。");
                monitorButton.setText("正在启动");
                monitorButton.setEnabled(false);
            } else if (wireless && (prefs.adbPaired() || PrivKitShell.hasStoredIdentity(this)) && !prefs.pairingRejected()) {
                boolean failed = !PrivKitShell.lastStartupError(this).isEmpty() || "服务启动失败".equals(PrivKitShell.status());
                state.setText(failed ? "服务启动失败" : "服务未启动");
                summary.setText("请到 ADB 授权页面启动服务。可先尝试原有配对，无需立即重复配对。");
                monitorButton.setText(failed ? "重新启动" : "启动服务");
            } else {
                state.setText(wireless ? "需要 ADB 授权" : "需要授权");
                summary.setText(wireless
                        ? "授权后才能检查 FCM 连接。已有配对会自动检测。"
                        : "请完成当前连接方式的授权后再开启监控。");
                monitorButton.setText("去授权");
            }
            return; // No monitoring controls, retry timers or stale FCM states before authorization.
        }
        if (!enabled) {
            state.setText("监控未开启");
            summary.setText("开启后将在后台检查 Google 推送连接。");
            monitorButton.setText("开启监控");
            return;
        }
        if (!FcmMonitorService.isRunning()) {
            state.setText("监控未运行");
            summary.setText("请重新开启后台监控。");
            monitorButton.setText("启动监控");
            return;
        }
        monitorButton.setText("立即检查");
        JSONObject snapshot = FcmMonitorService.lastSnapshot(this);
        long stamp = snapshot.optLong("fcm_sample_time", 0);
        long age = FcmMonitorService.sampleAgeSeconds(this);
        String lastError = FcmMonitorService.currentError(this);
        String observed = snapshot.optString("fcm_state", "never_seen");
        String stateSource = snapshot.optString("fcm_source");
        boolean stateEvidence = MonitorStatus.hasStateEvidence(stateSource);
        MonitorStatus.State verdict = MonitorStatus.resolve(true, enabled, true,
                stamp > 0 ? age : -1, !lastError.isEmpty(), stateEvidence, observed);
        state.setText(MonitorStatus.label(verdict, stateSource));
        state.setTextColor(statusColor(verdict));

        String description = "后台监控已开启 · 应用守护" + (prefs.guardEnabled() ? "已开启" : "未开启")
                + "\n最近检查：" + (age >= 0 ? age + " 秒前" : "尚无本次检查结果");
        if (age >= 0 && age <= 90 && stateEvidence && lastError.isEmpty()) {
            if ("gms_socket".equals(stateSource) && "connected".equals(observed)) {
                description += "\n" + MonitorStatus.connectedDuration(-1,
                        snapshot.optLong("fcm_observed_up_seconds", -1));
                description += "\n依据 GMS UID 的 MCS TCP 正向证据；不代表消息送达。";
            } else if ("gms_socket_absence".equals(stateSource)) {
                description += "\n依据内核 Socket 连续缺失 MCS TCP 并经二次采样确认。";
                long down = snapshot.optLong("fcm_observed_down_seconds", -1);
                if (down >= 0) description += "\n已观察未连接：" + MonitorStatus.duration(down);
            } else if ("gms_socket_stalled".equals(stateSource)) {
                description += "\n依据 TCP_INFO：MCS 连接存在但持续重传或长时间无数据。";
            } else if ("gms_socket".equals(stateSource)) {
                description += "\n依据 GMS UID 的 MCS TCP 正向证据；连接尚未建立或正在重连。";
            }
        }
        if (!lastError.isEmpty()) description += "\n后台将自动重试，详情见监控详情。";
        summary.setText(description);
    }

    @Override protected void onResume() {
        super.onResume();
        RecentTasks.apply(this, prefs.hideRecents());
        wasAuthorized = authorizationReady();
        if (authorizationReady()) FcmMonitorService.resumeIfNeeded(this);
        else PrivKitShell.recoverOnForeground(this);
        ui.removeCallbacks(refresh);
        ui.post(refresh);
    }
    @Override protected void onPause() {
        ui.removeCallbacks(refresh);
        super.onPause();
    }
}
