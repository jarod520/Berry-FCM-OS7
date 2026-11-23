package top.zesun.berryfcm;

/** One presentation verdict for overview, monitor detail and foreground notification.
 * No Android dependency; live authorization and a fresh native sample are required.
 */
final class MonitorStatus {
    enum State {
        AUTH_REQUIRED("需要授权"), DISABLED("监控未开启"), NOT_RUNNING("监控未运行"),
        WAITING("等待有效检查"), FAILED("连接检查失败"), UNKNOWN("暂无有效状态样本"),
        CONNECTED("FCM 已连接"), CONNECTING("FCM 正在重连（尚未连接）"),
        DISCONNECTED("FCM 已断开");
        final String label;
        State(String label) { this.label = label; }
    }
    private MonitorStatus() {}
    static boolean hasStateEvidence(String source) {
        return "gms_socket".equals(source) || "gms_socket_absence".equals(source)
                || "gms_socket_stalled".equals(source);
    }
    static String label(State state, String source) {
        if (state == State.CONNECTED && "gms_socket".equals(source))
            return "GMS MCS TCP 已建立（FCM 认证未证实）";
        if (state == State.CONNECTING && "gms_socket".equals(source))
            return "GMS MCS TCP 正在连接（尚未建立）";
        if (state == State.DISCONNECTED && "gms_socket_absence".equals(source))
            return "GMS MCS TCP 持续缺失（内核 Socket 观察）";
        if (state == State.DISCONNECTED && "gms_socket_stalled".equals(source))
            return "GMS MCS TCP 已卡死（持续重传/长时间无数据）";
        return state.label;
    }
    static State resolve(boolean authorized, boolean enabled, boolean running,
                         long age, boolean failed, boolean stateEvidence, String raw) {
        if (!authorized) return State.AUTH_REQUIRED;
        if (!enabled) return State.DISABLED;
        if (!running) return State.NOT_RUNNING;
        if (failed) return State.FAILED;
        if (age < 0 || age > 90) return State.WAITING;
        if (!stateEvidence) return State.UNKNOWN;
        if ("connected".equals(raw)) return State.CONNECTED;
        if ("connecting".equals(raw)) return State.CONNECTING;
        if ("disconnected".equals(raw)) return State.DISCONNECTED;
        return State.UNKNOWN;
    }
    static String connectedDuration(long nativeSeconds, long observedSeconds) {
        if (nativeSeconds > 0) return "GMS 计时：" + duration(nativeSeconds);
        if (observedSeconds > 0) {
            return "已观察在线：" + duration(observedSeconds)
                    + (nativeSeconds == 0 ? "（GMS 计时仍为 0，非实际总时长）"
                                          : "（非实际连接总时长）");
        }
        return nativeSeconds == 0 ? "GMS 计时：0 秒（待后续采样确认）"
                : "连接时长：无法确认";
    }

    static String notificationDuration(long seconds) {
        long minutes = seconds / 60;
        if (minutes == 0) return "不足1分钟";
        if (minutes < 60) return minutes + "分钟";
        return minutes / 60 + "小时" + minutes % 60 + "分钟";
    }

    static String duration(long seconds) {
        if (seconds < 0) return "未知";
        long days = seconds / 86400, hours = seconds / 3600 % 24;
        long minutes = seconds / 60 % 60, secs = seconds % 60;
        StringBuilder out = new StringBuilder();
        if (days > 0) out.append(days).append("天 ");
        if (hours > 0) out.append(hours).append("小时 ");
        if (minutes > 0) out.append(minutes).append("分 ");
        out.append(secs).append("秒");
        return out.toString();
    }
}
