# Berry-FCM KSU v1.0-rc.15

KernelSU Root（UID 0）模块。模块 ID 仍为 `berry_fcm_ksu`，升级保留守护名单、开关和旧 TCP 监控历史。新 GMS 监控写入单独的 `mcs-*` 文件。

## 监控与恢复

- 「设置 → 后台保活」可选随系统唤醒（默认，约每 30 秒尝试巡检）或定时巡检（1–10 分钟，默认 3 分钟）。后者保留常规巡检，并由独立的 ARM64 Root 定时器增加检查机会。定时器失败或迟到时，常规巡检继续运行。两种方式都没有持续 CPU 唤醒锁。
- 后台每轮巡检都读取精确 GMS UID 的 MCS TCP Socket；`GcmService` 原生 dumpsys 默认每 60 秒刷新一次，手动恢复及原生状态的二次确认会立即强制刷新。原生状态采样优先于同轮 Socket 结果；两次原生采样之间，最近一次有效 connected 状态不会因 Socket 缺失/所有权不可读而被误判断联，最近一次有效断开/连接中状态也不会因 Socket 缺失/不可读或暂时 ESTABLISHED 而被覆盖；须等下一次原生采样或独立 Socket 缺失阈值确认状态变化。两次原生刷新之间，Socket 用于提供实时传输层证据。TCP ESTABLISHED 不等同于心跳 ACK，因此仍定期刷新原生状态；原生字段缺失时，连续 30 秒未看到精确 MCS TCP 并经二次采样后才按断联恢复，持续缺失超过 15 分钟不会清零计时，只有超过 90 秒的采样空档才重置连续性。持续 SYN-SENT 保留首次观察时间。Socket 所有权不可读时，最近 Close 事件（30–900 秒、且没有更新的 Connected 事件）仅作为有限期辅助证据。普通或不可见的 443 Socket 不作正向连接证据。
- 明确断开通常等 15 秒，连接中通常等 60 秒。达到条件后在同一执行窗口二次确认。跨采样空档仅将此前断联当作复查线索。
- 若 GMS 原生仍报告已连接，但精确原生连接时长连续 5 分钟不增长，自动守护会再采样确认，然后定向请求一次 `GCM_RECONNECT`；连接时长恢复增长后取消。此操作请求 GMS 重建 MCS 连接，不会强制停止 Google Play 服务。
- 二次确认断联后，同一轮依次尝试 `GCM_RECONNECT`、`MCS_HEARTBEAT`、`ACTION_HEARTBEAT_NOW`、`GMS_INITIALIZE`、`GCM_SERVICE_START`。每次命令被系统接受后复采 Socket，观察到连接恢复就结束本轮。自动重试退避按连续轮次为 30 / 45 / 60 / 90 秒，手动请求至少间隔 60 秒。
- 广播完成只记为已请求。WebUI 用后续 GMS 原生采样确认连接，实际推送送达需单测。
- GMS UID Socket 缺失期间若 mtalk DNS 解析失败，失败结果缓存 10 分钟，避免每轮巡检重复执行最长 6 秒的 DNS 等待。
- 每轮巡检有 25 秒上限，优先使用 Toybox / KernelSU BusyBox / 系统 `timeout`。若系统没有 `timeout` applet，则使用 watchdog；可用 `setsid` 与 `kill` applet 时按进程组清理 monitor 及其子进程。超时记为 `rc=124`，不刷新成功样本心跳，下一轮仍继续巡检。

热安装时，如果 Root 服务继承了管理器的应用冻结组，服务仅迁移自身到 cgroup v2 根组，子进程继承该组。迁移失败会在 WebUI 和后台日志中显示。

## 安装与升级

1. 确认 KernelSU 已授予本模块 Root。
2. 从 KernelSU「模块」安装 `BerryFCM-KSU-v1.0-rc.15.zip`。
3. KernelSU 支持热安装时，BerryFCM 会先停止旧监控服务，再按自动守护开关启动新服务；更新本模块不需要重启设备。卸载时由卸载脚本停止服务，服务也会在模块目录/disable 标记消失时自行退出。若当前 KernelSU 未执行热安装流程，管理器可能仍要求重启。
4. 从 KernelSU 模块 WebUI 打开页面，先点“立即检测”，再核对 Google 原生 Diagnostics 的 `Connected` / `Close` 记录。
5. 自动守护默认沿用原配置。先观察事件时间线和真实推送，再决定是否开启。

## 手动诊断

```sh
su -c 'sh /data/adb/modules/berry_fcm_ksu/bin/fcm-monitor.sh status'
su -c 'sh /data/adb/modules/berry_fcm_ksu/bin/fcm-monitor.sh events'
su -c 'sh /data/adb/modules/berry_fcm_ksu/bin/fcm-monitor.sh native-events'
su -c 'sh /data/adb/modules/berry_fcm_ksu/bin/fcm-monitor.sh reconnect'
su -c 'sh /data/adb/modules/berry_fcm_ksu/bin/ctl.sh check'
su -c 'sh /data/adb/modules/berry_fcm_ksu/bin/ctl.sh guard on'
su -c 'sh /data/adb/modules/berry_fcm_ksu/bin/ctl.sh guard off'
```

运行时数据：

- `/data/adb/berry_fcm_ksu/targets.txt`：守护应用名单
- `/data/adb/berry_fcm_ksu/enabled`：自动守护开关
- `/data/adb/berry_fcm_ksu/mcs-monitor.state`：当前连接状态与时间戳
- `/data/adb/berry_fcm_ksu/mcs-monitor-events.log`：巡检空档 / 断联 / 重连事件
- `/data/adb/berry_fcm_ksu/mcs-native-events.log`：筛选和去重后的 GMS 原生事件
- `/data/adb/berry_fcm_ksu/guard.log`：守护巡检日志
- `/data/adb/berry_fcm_ksu/patrol.heartbeat`：patrol 循环心跳；`patrol.sample.heartbeat`：最近一次成功完成的 FCM 样本时间，两者用途不同。
- `/data/adb/berry_fcm_ksu/mcs-monitor.lock.owner`：当前持锁的 monitor PID/starttime，正常退出会自动清理；样本长期无更新时 service 会先核验身份再终止卡住的 monitor。
- `guard.log` 中的 `fcm_check_start` / `fcm_check_end`：逐次巡检开始/结束、耗时、采样状态和恢复决策；只有监控命令成功返回才刷新 `patrol.sample.heartbeat`。service 同时监督 patrol 循环心跳与成功样本心跳，若循环仍活着但连续 90 秒没有成功样本，会记录 `reason=monitor_sample`，先按 PID/starttime 校验并终止卡住的 monitor 锁所有者，再重启巡检进程；清理 worker 未确认退出时保留 service 锁，下一次启动会先回收并核验遗留 patrol，无法确认退出则拒绝启动重复巡检；`maintenance_start` / `maintenance_end` 记录守护修复命令。`wake-timer.log` 还记录 timer worker 的启动/退出、armed/fired、迟到和 suspend 时长。三者对照可判断空档发生在哪一阶段。
- 导出这两类记录：`su -c 'sh /data/adb/modules/berry_fcm_ksu/bin/ctl.sh log'`。巡检有开始没有结束，表示检查调用未返回；修复命令有开始没有结束，表示守护修复未返回；定时器只看到 `wake_timer_armed` 没有 `wake_timer_fired`，表示定时器未按期完成。以上情况都要结合后续日志判断，不能仅凭一条记录推断进程已退出。

## 保留功能

- GMS / 指定应用 stopped 状态检查和修复、广播心跳。
- 应用守护名单增删、连续多选、已选置顶、分批加载全部应用。
- GMS Doze 白名单、Android 数据节省模式和后台计量网络状态诊断及手动放行/撤销。
- Google FCM Diagnostics 原生页面跳转、只读 TCP 可达性测试。
- 浅色 / 深色主题；不依赖 Shizuku、LSPosed。

## 安全与限制

- 不修改 hosts、DNS、VPN、代理、路由或系统分区。
- 不强制停止 / 重启 GMS，不清除数据，不声称永久保活。
- TCP ESTABLISHED 只证明采样时观察到 GMS UID Socket；mtalk 地址匹配的 443 只是候选，不等于 MCS 已认证或消息一定送达。
- 普通 GMS 443 不计为 FCM；若原生状态与 UID Socket 元信息都无法读取，页面会报告未取得有效样本，不会凭空推断断联。
- 仅监控 Android 用户 0 的 GMS 主包 UID；厂商私有冻结、网络限制不保证可解除。
- Doze 白名单和后台数据放行可能增加待机耗电 / 流量。
