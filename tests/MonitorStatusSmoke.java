package top.zesun.berryfcm;
public final class MonitorStatusSmoke {
    private static void expect(MonitorStatus.State expected, boolean auth, boolean enabled,
            boolean running, long age, boolean failed, boolean nativeState, String raw) {
        MonitorStatus.State actual = MonitorStatus.resolve(auth, enabled, running, age, failed, nativeState, raw);
        if (actual != expected) throw new AssertionError(expected + " != " + actual);
    }
    public static void main(String[] args) {
        expect(MonitorStatus.State.AUTH_REQUIRED, false,true,true,0,false,true,"connected");
        expect(MonitorStatus.State.DISABLED,true,false,true,0,false,true,"connected");
        expect(MonitorStatus.State.NOT_RUNNING,true,true,false,0,false,true,"connected");
        expect(MonitorStatus.State.FAILED,true,true,true,0,true,true,"connected");
        expect(MonitorStatus.State.WAITING,true,true,true,-1,false,true,"connected");
        expect(MonitorStatus.State.WAITING,true,true,true,91,false,true,"connected");
        expect(MonitorStatus.State.UNKNOWN,true,true,true,0,false,false,"connected");
        expect(MonitorStatus.State.CONNECTED,true,true,true,90,false,true,"connected");
        expect(MonitorStatus.State.CONNECTING,true,true,true,10,false,true,"connecting");
        expect(MonitorStatus.State.DISCONNECTED,true,true,true,10,false,true,"disconnected");
        expect(MonitorStatus.State.UNKNOWN,true,true,true,10,false,true,"unknown");
        if (!MonitorStatus.hasStateEvidence("gms_socket")
                || !MonitorStatus.hasStateEvidence("gms_socket_absence")
                || !MonitorStatus.hasStateEvidence("gms_socket_stalled")
                || !MonitorStatus.hasStateEvidence("gms_socket_stalled")
                || MonitorStatus.hasStateEvidence("gms")
                || MonitorStatus.hasStateEvidence("unavailable"))
            throw new AssertionError("state evidence sources");
        if (!"GMS 已连接（MCS TCP 已建立）".equals(
                MonitorStatus.label(MonitorStatus.State.CONNECTED, "gms_socket")))
            throw new AssertionError("socket evidence label");
        if (!"6分 40秒".equals(MonitorStatus.duration(400))) throw new AssertionError("duration");
        if (!"1天 1小时 1分 1秒".equals(MonitorStatus.duration(90061))) throw new AssertionError("duration days");
        long[] notificationSeconds = {0, 59, 60, 3599, 3600, 5794};
        String[] notificationLabels = {"不足1分钟", "不足1分钟", "1分钟", "59分钟", "1小时0分钟", "1小时36分钟"};
        for (int i = 0; i < notificationSeconds.length; i++) {
            if (!notificationLabels[i].equals(MonitorStatus.notificationDuration(notificationSeconds[i])))
                throw new AssertionError("notification duration: " + notificationSeconds[i]);
        }
        if (!"已连接：刚建立".equals(MonitorStatus.connectedDuration(0)))
            throw new AssertionError("zero duration");
        if (!"已连接：2分 0秒".equals(MonitorStatus.connectedDuration(120)))
            throw new AssertionError("nonzero duration");
        System.out.println("PASS: shared monitor truth table and qualified duration formatting");
    }
}
