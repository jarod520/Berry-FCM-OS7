package top.zesun.berryfcm;

import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Switch;
import android.widget.TextView;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Selected-first guard list. Scan installed apps only when opening the picker. */
public final class GuardActivity extends Ui {
    private static final int PAGE_SIZE = 24;
    private static final class App {
        final String pkg, label;
        final boolean system, available;
        App(String pkg, String label, boolean system, boolean available) {
            this.pkg = pkg;
            this.label = label;
            this.system = system;
            this.available = available;
        }
    }

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final List<App> candidates = new ArrayList<>();
    private final Map<String, Drawable> icons = new HashMap<>();
    private LinearLayout selectedEntries, picker, candidateEntries;
    private EditText filter;
    private CheckBox showSystem;
    private TextView selectedCount, candidateCount, report, guardStatus;
    private Button choose, more;
    private int shown = PAGE_SIZE;
    private boolean loading, scanned, operationRunning;
    private Switch running;
    private java.util.concurrent.Future<?> watchFuture;
    private long operationGeneration;
    private final android.os.Handler ui = new android.os.Handler(android.os.Looper.getMainLooper());
    private android.content.SharedPreferences guardReport;
    private String renderedReport;
    private Set<String> renderedTargets;
    private final Runnable refreshReport = this::refreshStoredReport;
    private final android.content.SharedPreferences.OnSharedPreferenceChangeListener reportListener =
            (store, key) -> {
                ui.removeCallbacks(refreshReport);
                ui.post(refreshReport);
            };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        title("应用守护", "仅显示已选择的守护应用，按需添加更多");

        LinearLayout selected = card("已选择的守护应用", "Google Play 服务为核心目标，始终保留。");
        selectedCount = text("", 12, false, muted);
        selected.addView(selectedCount);
        selectedEntries = new LinearLayout(this);
        selectedEntries.setOrientation(LinearLayout.VERTICAL);
        selected.addView(selectedEntries);
        choose = button(selected, "选择应用", this::togglePicker, true);

        picker = card("添加守护应用", "只在这里显示候选应用；系统应用需手动开启筛选。");
        picker.setVisibility(View.GONE);
        filter = new EditText(this);
        filter.setSingleLine(true);
        filter.setTextSize(14);
        filter.setHint("搜索应用名称或包名");
        filter.setTextColor(ink);
        filter.setHintTextColor(muted);
        filter.setMinHeight(dp(52));
        filter.setPadding(dp(12), dp(9), dp(12), dp(9));
        android.graphics.drawable.GradientDrawable search = new android.graphics.drawable.GradientDrawable();
        search.setColor(panel);
        search.setCornerRadius(dp(12));
        search.setStroke(dp(1), muted);
        filter.setBackground(search);
        picker.addView(filter);
        filter.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence text, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence text, int start, int before, int count) {
                renderCandidates(true);
            }
            @Override public void afterTextChanged(Editable text) {}
        });
        showSystem = new CheckBox(this);
        showSystem.setText("显示可守护的系统应用");
        showSystem.setTextColor(ink);
        showSystem.setTextSize(13);
        showSystem.setChecked(false);
        showSystem.setMinHeight(dp(48));
        picker.addView(showSystem);
        showSystem.setOnCheckedChangeListener((button, checked) -> renderCandidates(true));
        candidateCount = text("", 12, false, muted);
        picker.addView(candidateCount);
        candidateEntries = new LinearLayout(this);
        candidateEntries.setOrientation(LinearLayout.VERTICAL);
        picker.addView(candidateEntries);
        more = button(picker, "显示更多", () -> {
            shown += PAGE_SIZE;
            renderCandidates(false);
        }, false);
        button(picker, "刷新候选应用", this::loadCandidates, false);

        LinearLayout actions = card("自动守护", "约每五分钟检查已选目标；不等于强制常驻或保证 FCM 消息送达。");
        running = new Switch(this);
        running.setText("启用后台自动守护");
        running.setTextColor(ink);
        running.setMinHeight(dp(50));
        running.setChecked(prefs.guardEnabled());
        actions.addView(running);
        running.setOnCheckedChangeListener((view, enabled) -> {
            if (bindingSwitches()) return;
            if (enabled && !PrivilegeAccess.readyForUserAction(this)) {
                syncChecked(running, prefs.guardEnabled());
                error("请先完成授权并启动服务");
                go(AuthActivity.class);
                return;
            }
            prefs.guardEnabled(enabled);
            if (enabled) FcmMonitorService.start(this);
            else if (!prefs.monitorEnabled()) FcmMonitorService.stop(this);
            renderGuardStatus();
        });
        guardStatus = text("", 13, false, muted);
        actions.addView(guardStatus);
        button(actions, "检查所选应用", () -> runCheck(false), true);
        button(actions, "恢复已停止的应用", () -> runCheck(true), false);
        LinearLayout advanced = disclosure(actions, "高级操作 · 90 秒巡检 / GMS 心跳", false);
        button(advanced, "运行 90 秒巡检", this::watchNinetySeconds, false);
        button(advanced, "请求 GMS 心跳", this::requestHeartbeat, false);
        LinearLayout output = disclosure(actions, "检查日志", false);
        guardReport = getSharedPreferences("berry_fcm_guard_report", MODE_PRIVATE);
        report = text(guardReport.getString("report", "尚未检查"), 12, false, muted);
        report.setTextIsSelectable(true);
        output.addView(report);
        renderSelected();
        renderGuardStatus();
    }

    private void renderGuardStatus() {
        if (guardStatus == null) return;
        syncChecked(running, prefs.guardEnabled());
        long last = getSharedPreferences("berry_fcm_guard_report", MODE_PRIVATE).getLong("last_run", 0);
        String time = last > 0 ? new java.text.SimpleDateFormat("MM-dd HH:mm:ss",
                Locale.getDefault()).format(new java.util.Date(last)) : "尚未检查";
        guardStatus.setText(!PrivilegeAccess.readyForUserAction(this)
                ? "需要授权，完成授权后才能检查或恢复应用。"
                : (prefs.guardEnabled() && FcmMonitorService.isRunning()
                    ? "后台守护已开启" : "后台守护未运行") + "\n最近检查：" + time);
    }

    private boolean requireAuthorization() {
        if (PrivilegeAccess.readyForUserAction(this)) return true;
        go(AuthActivity.class);
        return false;
    }

    private void togglePicker() {
        boolean open = picker.getVisibility() != View.VISIBLE;
        picker.setVisibility(open ? View.VISIBLE : View.GONE);
        choose.setText(open ? "完成选择 / 收起列表" : "选择应用");
        if (open && !scanned && !loading) loadCandidates();
    }

    private void loadCandidates() {
        if (loading) return;
        loading = true;
        candidateCount.setText("正在读取可选择应用…");
        worker.execute(() -> {
            List<App> found = new ArrayList<>();
            try {
                PackageManager pm = getPackageManager();
                for (ApplicationInfo info : pm.getInstalledApplications(0)) {
                    if (!eligible(info, pm)) continue;
                    boolean system = isSystem(info);
                    String label = String.valueOf(info.loadLabel(pm));
                    found.add(new App(info.packageName, label, system, true));
                }
                found.sort(Comparator.comparing((App app) -> app.label,
                        String.CASE_INSENSITIVE_ORDER));
                runOnUiThread(() -> {
                    candidates.clear();
                    candidates.addAll(found);
                    loading = false;
                    scanned = true;
                    renderCandidates(true);
                });
            } catch (RuntimeException error) {
                runOnUiThread(() -> {
                    loading = false;
                    candidateCount.setText("读取失败：" + error.getMessage());
                });
            }
        });
    }

    /** Conservative candidate filter, not a claim that the privileged command will succeed. */
    private static boolean eligible(ApplicationInfo info, PackageManager pm) {
        if (!info.enabled || (info.flags & ApplicationInfo.FLAG_INSTALLED) == 0
                || info.uid < 10000
                || info.packageName.equals("top.zesun.berryfcm")
                || (info.flags & ApplicationInfo.FLAG_PERSISTENT) != 0) return false;
        // System services and hidden framework components do not belong in a
        // normal user application picker, even when QUERY_ALL_PACKAGES sees them.
        return !isSystem(info) || pm.getLaunchIntentForPackage(info.packageName) != null;
    }

    private static boolean isSystem(ApplicationInfo info) {
        return (info.flags & (ApplicationInfo.FLAG_SYSTEM
                | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0;
    }

    private App selectedApp(String pkg) {
        PackageManager pm = getPackageManager();
        try {
            ApplicationInfo info = pm.getApplicationInfo(pkg, 0);
            String label = String.valueOf(info.loadLabel(pm));
            return new App(pkg, label, isSystem(info), eligible(info, pm));
        } catch (PackageManager.NameNotFoundException error) {
            return new App(pkg, pkg.equals(GuardOps.GMS) ? "Google Play 服务"
                    : "应用已卸载", false, false);
        }
    }

    private void renderSelected() {
        if (selectedEntries == null) return;
        Set<String> target = new HashSet<>(prefs.guardTargets());
        target.add(GuardOps.GMS);
        String previous = guardReport.getString("report", "");
        if (target.equals(renderedTargets) && previous.equals(renderedReport)) return;
        renderedTargets = new HashSet<>(target);
        renderedReport = previous;
        List<App> chosen = new ArrayList<>();
        for (String pkg : target) chosen.add(selectedApp(pkg));
        chosen.sort(Comparator.comparingInt((App app) ->
                GuardOps.GMS.equals(app.pkg) ? 0 : 1)
                .thenComparing(app -> app.label, String.CASE_INSENSITIVE_ORDER));
        selectedEntries.removeAllViews();
        for (App app : chosen) addAppRow(selectedEntries, app, true);
        selectedCount.setText("已选择 " + chosen.size() + " 个守护目标"
                + (chosen.size() == 1 ? " · 点击选择应用添加目标" : " · 可取消非核心应用"));
    }

    private void renderCandidates(boolean resetPage) {
        if (candidateEntries == null || picker.getVisibility() != View.VISIBLE) return;
        if (resetPage) shown = PAGE_SIZE;
        Set<String> selected = prefs.guardTargets();
        selected.add(GuardOps.GMS);
        String keyword = filter.getText().toString().trim().toLowerCase(Locale.ROOT);
        boolean system = showSystem.isChecked();
        List<App> visible = new ArrayList<>();
        for (App app : candidates) {
            if (!app.available || selected.contains(app.pkg)) continue;
            if (app.system && !system) continue;
            if (!keyword.isEmpty()
                    && !(app.label + " " + app.pkg).toLowerCase(Locale.ROOT).contains(keyword))
                continue;
            visible.add(app);
        }
        candidateEntries.removeAllViews();
        int end = Math.min(shown, visible.size());
        for (int i = 0; i < end; i++) addAppRow(candidateEntries, visible.get(i), false);
        if (!scanned && !loading) candidateCount.setText("点击刷新读取可选应用");
        else if (!loading) candidateCount.setText("可添加 " + visible.size()
                + " 个 · 当前显示 " + end + " 个"
                + (system ? "\n系统应用仅显示已启用、具备入口的普通应用进程" : ""));
        if (more != null) {
            more.setVisibility(shown < visible.size() ? View.VISIBLE : View.GONE);
        }
    }

    private void addAppRow(LinearLayout parent, App app, boolean selected) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(4), 0, dp(4));
        ImageView image = new ImageView(this);
        Drawable icon = icons.get(app.pkg);
        if (icon == null) {
            try { icon = getPackageManager().getApplicationIcon(app.pkg); }
            catch (PackageManager.NameNotFoundException error) {
                icon = getDrawable(android.R.drawable.sym_def_app_icon);
            }
            icons.put(app.pkg, icon);
        }
        image.setImageDrawable(icon);
        LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(dp(34), dp(34));
        ip.rightMargin = dp(10);
        row.addView(image, ip);
        CheckBox check = new CheckBox(this);
        String previous = getSharedPreferences("berry_fcm_guard_report", MODE_PRIVATE)
                .getString("report", "");
        String state = lastState(previous, app.pkg);
        check.setText(app.label + (app.system ? " · 系统" : "")
                + (!app.available && selected && !GuardOps.GMS.equals(app.pkg)
                    ? " · 已停用/不在候选范围" : "")
                + (state.isEmpty() ? "" : " · " + state)
                + "\n" + app.pkg);
        check.setTextSize(13);
        check.setTextColor(ink);
        check.setMinHeight(dp(52));
        check.setChecked(selected);
        check.setEnabled(!GuardOps.GMS.equals(app.pkg));
        if (GuardOps.GMS.equals(app.pkg)) {
            check.setContentDescription("Google Play 服务，核心守护目标，不可移除");
        } else {
            check.setOnCheckedChangeListener((button, checked) -> {
                Set<String> targets = prefs.guardTargets();
                if (checked) targets.add(app.pkg);
                else targets.remove(app.pkg);
                prefs.guardTargets(targets);
                renderSelected();
                renderCandidates(false);
            });
        }
        row.addView(check, new LinearLayout.LayoutParams(0, -2, 1));
        parent.addView(row);
    }

    private static String lastState(String report, String pkg) {
        for (String line : report.split("\n")) {
            if (!line.startsWith(pkg + "|")) continue;
            String code = line.substring(pkg.length() + 1).trim();
            switch (code) {
                case "not_stopped": case "running": return "上次未被强制停止";
                case "stopped": return "上次处于强制停止状态";
                case "unstop_submitted": return "已提交解除停止命令（未做状态复检）";
                case "not_installed": return "目标未安装";
                case "restored": return "上次已解除停止";
                case "repair_failed": return "上次恢复失败";
                case "unknown": return "上次无法判断";
                default: return "";
            }
        }
        return "";
    }

    private void runCheck(boolean fix) {
        if (!requireAuthorization() || !beginOperation()) return;
        guardStatus.setText(fix ? "正在检查并尝试恢复…" : "正在检查应用…");
        report.setText(fix ? "正在检查并尝试恢复…" : "正在检查应用是否被强制停止…");
        worker.execute(() -> {
            try (PrivilegeShell shell = PrivilegeAccess.open(this)) {
                String result = runGuardBatches(shell, fix);
                getSharedPreferences("berry_fcm_guard_report", MODE_PRIVATE)
                        .edit().putString("report", result).putLong("last_run", System.currentTimeMillis()).apply();
                runOnUiThread(() -> { if (!isDestroyed()) { report.setText(result); renderSelected(); renderGuardStatus(); } });
            } catch (Exception e) {
                runOnUiThread(() -> { if (!isDestroyed()) { report.setText("操作失败：" + e.getMessage()); guardStatus.setText("检查失败，请查看检查日志。"); } });
            } finally { runOnUiThread(() -> operationRunning = false); }
        });
    }
    private String runGuardBatches(PrivilegeShell shell, boolean fix) throws Exception {
        StringBuilder result = new StringBuilder();
        for (String command : GuardOps.commandBatches(prefs.guardTargets(), fix)) {
            if (Thread.currentThread().isInterrupted()) throw new InterruptedException();
            result.append(shell.execute(command)).append("\n");
        }
        return result.toString().trim();
    }
    private boolean beginOperation() {
        if (operationRunning) { error("已有守护检查正在执行"); return false; }
        operationRunning = true;
        return true;
    }
    private void requestHeartbeat() {
        if (!requireAuthorization() || !beginOperation()) return;
        report.setText("正在请求 GMS 心跳…");
        worker.execute(() -> {
            try (PrivilegeShell shell = PrivilegeAccess.open(this)) {
                String output = shell.execute(GuardOps.heartbeatCommand());
                runOnUiThread(() -> { if (!isDestroyed()) report.setText("心跳广播结果（不是推送送达证明）\n" + output); });
            } catch (Exception error) {
                runOnUiThread(() -> { if (!isDestroyed()) report.setText("心跳请求失败：" + error.getMessage()); });
            } finally { runOnUiThread(() -> operationRunning = false); }
        });
    }

    private void watchNinetySeconds() {
        if (!requireAuthorization() || !beginOperation()) return;
        report.setText("正在运行 90 秒巡检；离开页面会中止本次交互测试");
        final long generation = ++operationGeneration;
        watchFuture = worker.submit(() -> {
            try (PrivilegeShell shell = PrivilegeAccess.open(this)) {
                for (int i = 0; i < 7; i++) {
                    String result = runGuardBatches(shell, true);
                    // An unstopped application is not proof of an MCS outage.
                    // Keep the manual heartbeat button, but do not broadcast
                    // automatically during guardian verification.
                    getSharedPreferences("berry_fcm_guard_report", MODE_PRIVATE).edit()
                            .putString("report", result).putLong("last_run", System.currentTimeMillis()).apply();
                    final int sample = i + 1;
                    final String current = result;
                    runOnUiThread(() -> {
                        if (!isDestroyed() && generation == operationGeneration) {
                            report.setText("巡检 " + sample + "/7\n" + current);
                            renderSelected(); renderGuardStatus();
                        }
                    });
                    if (i < 6) Thread.sleep(15000);
                }
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!isDestroyed() && generation == operationGeneration) report.setText("巡检异常：" + error.getMessage());
                });
            } finally {
                runOnUiThread(() -> {
                    if (generation == operationGeneration) { operationRunning = false; watchFuture = null; }
                });
            }
        });
    }

    private void refreshStoredReport() {
        if (isDestroyed() || isFinishing()) return;
        if (!operationRunning) report.setText(guardReport.getString("report", "尚未检查"));
        renderSelected();
        renderGuardStatus();
    }

    @Override protected void onResume() {
        super.onResume();
        renderedTargets = null; // re-read app installation state after returning
        guardReport.registerOnSharedPreferenceChangeListener(reportListener);
        refreshStoredReport();
    }

    @Override protected void onPause() {
        guardReport.unregisterOnSharedPreferenceChangeListener(reportListener);
        ui.removeCallbacks(refreshReport);
        if (watchFuture != null) {
            operationGeneration++;
            watchFuture.cancel(true);
            watchFuture = null;
            operationRunning = false;
            report.setText("本次交互巡检已取消；后台守护开关不变。");
        }
        super.onPause();
    }
    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
