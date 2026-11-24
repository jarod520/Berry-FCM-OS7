package top.zesun.berryfcm;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class DiagnosticsActivity extends Ui {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private TextView results;
    private boolean checking;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        title("网络诊断", "不依赖 Shell 的基础检查与高级诊断");
        LinearLayout network = card("基础网络检查", "无需 Root / ADB，只测试本应用的 TCP 连接，不代表 GMS 推送已恢复。");
        button(network, "检测 mtalk.google.com 连接", this::checkNetwork, true);
        results = text("尚未执行检测", 13, false, muted);
        results.setTextIsSelectable(true);
        results.setPadding(0, dp(12), 0, dp(5));
        network.addView(results);

        LinearLayout diagnostics = card("更多诊断", "系统策略检测需要已授权的 Root / ADB Shell。");
        line(diagnostics, "Google FCM Diagnostics", "打开系统原生连接诊断",
                R.drawable.ic_bf_diagnostics, () -> openGoogle(this));
        line(diagnostics, "监控记录", "查看 GMS 原生连接状态、断联与恢复记录",
                R.drawable.ic_bf_history, () -> go(MonitorActivity.class));
        LinearLayout extra = disclosure(diagnostics, "高级 · 策略检查 / 分享日志", false);
        button(extra, "检查 GMS Doze / 后台网络 / 通知策略", this::checkPolicies, false);
        button(extra, "分享监控事件与错误", this::shareEvents, false);
    }

    static void openGoogle(Activity activity) {
        try {
            Intent intent = new Intent();
            intent.setClassName("com.google.android.gms", "com.google.android.gms.gcm.GcmDiagnostics");
            activity.startActivity(intent);
        } catch (RuntimeException error) {
            android.widget.Toast.makeText(activity,
                    "当前 GMS 未开放 Diagnostics 页面", android.widget.Toast.LENGTH_LONG).show();
        }
    }
    private void checkNetwork() {
        if (checking) { error("已有诊断正在执行"); return; }
        checking = true;
        results.setText("正在测试 mtalk.google.com；每个端口最多等待 3 秒（DNS 解析另计）…");
        worker.execute(() -> {
            StringBuilder report = new StringBuilder();
            for (int port : new int[]{5228, 5229, 5230}) {
                try (Socket socket = new Socket()) {
                    socket.connect(new InetSocketAddress("mtalk.google.com", port), 3000);
                    report.append(port).append("：TCP 握手成功\n");
                } catch (Exception error) {
                    report.append(port).append("：连接失败（")
                            .append(error.getClass().getSimpleName()).append("）\n");
                }
            }
            report.append("\n使用 BerryFCM 应用的网络路径；不检测 GMS UID 实际连接，不能证明 FCM 消息送达，也不能判断是否经过代理。");
            String output = report.toString();
            runOnUiThread(() -> { checking = false; if (!isDestroyed()) results.setText(output); });
        });
    }
    private void checkPolicies() {
        if (!PrivilegeAccess.readyForUserAction(this)) { go(AuthActivity.class); return; }
        if (checking) { error("已有诊断正在执行"); return; }
        checking = true;
        results.setText("正在回读 GMS 系统策略…");
        worker.execute(() -> {
            try (PrivilegeShell shell = PrivilegeAccess.open(this)) {
                String command = "echo '== Doze 当前状态（只读） ==' ; "
                        + "cmd deviceidle get deep 2>&1; cmd deviceidle get light 2>&1; "
                        + "echo '== GMS Doze 白名单 ==' ; cmd deviceidle whitelist 2>&1 | "
                        + "grep -F com.google.android.gms || true; "
                        + "echo '== DataSaver ==' ; cmd netpolicy get restrict-background 2>&1; "
                        + "echo '== Background Network ==' ; "
                        + "cmd netpolicy list restrict-background-whitelist 2>&1; "
                        + "echo '== GMS 后台 AppOps ==' ; "
                        + "cmd appops get com.google.android.gms RUN_ANY_IN_BACKGROUND 2>&1; "
                        + "cmd appops get com.google.android.gms RUN_IN_BACKGROUND 2>&1; "
                        + "echo '== GMS Notifications ==' ; "
                        + "cmd appops get com.google.android.gms POST_NOTIFICATION 2>&1";
                String output = shell.execute(command);
                runOnUiThread(() -> { if (!isDestroyed()) results.setText(output); });
            } catch (Exception error) {
                runOnUiThread(() -> { if (!isDestroyed()) results.setText("诊断失败：" + error.getMessage()); });
            } finally { runOnUiThread(() -> checking = false); }
        });
    }

    private void shareEvents() {
        String report = "BerryFCM 状态诊断\n"
                + "== 独立服务 / 启动证据 ==\n" + PrivKitShell.diagnostic(this) + "\n"
                + "监控错误：" + (FcmMonitorService.currentError(this).isEmpty()
                        ? "无" : FcmMonitorService.currentError(this)) + "\n"
                + FcmMonitorService.lastSnapshot(this).toString() + "\n"
                + "\n== GMS 原生连接事件 ==\n" + FcmMonitorService.lastEvents(this)
                + "\n== BerryFCM 恢复与采样事件 ==\n" + FcmMonitorService.lastEvents(this)
                + "\n== BerryFCM 熄屏巡检与唤醒 ==\n" + FcmMonitorService.lastRuntimeEvents(this)
                + "\n== 采样环境变化（不代表 GMS 实际路由） ==\n" + FcmMonitorService.lastEnvironmentEvents(this);
        Intent share = new Intent(Intent.ACTION_SEND);
        share.setType("text/plain");
        share.putExtra(Intent.EXTRA_TEXT, report);
        startActivity(Intent.createChooser(share, "分享 BerryFCM 诊断"));
    }
    @Override protected void onDestroy() { worker.shutdownNow(); super.onDestroy(); }
}
