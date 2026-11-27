# Berry-FCM-OS7 交接（现状快照）

## 2026-11-27 SU rc.17 实测与修正

- V2505A 的 rc.17 在约 15 小时 21 分内记录 169 次看门狗超时、47 次监控锁占用，最长两次正常巡检结束之间隔了 16 分 41 秒。定时器按已保存的 1 分钟间隔正常触发，日志在 08:00 左右正常轮转。
- SU rc.19 为进行中的巡检记录启动时间和独立截止时间。已有采样过期时，仅允许在有效期内已经启动的巡检用完本轮时限。默认预算 98 秒，含监控命令、结束宽限、前后快照和状态处理。看门狗准备中止巡检时记录对应的启动和截止时间。进程身份检查和清理确认继续生效。
- SU 和 APK 都移除 `GMS_INITIALIZE`，恢复序列减为 4 个动作。V2505A 当前没有该广播的接收器，系统保留的两条该广播历史均未派发。SU 日志明确区分命令提交、实际投递和 TCP 复采结果。
- SU WebUI 将手动恢复交给后台进程，并轮询结果。恢复期间可继续滚动和查看页面，重复点击由按钮状态和后台锁拦截。
- 在 V2505A 的隔离目录中通过 SU 和 APK 恢复脚本回归、48 小时归档边界、看门狗提前中止复现及手动恢复后台启动、去重和结果回传测试。模块待覆盖安装后检查实际 WebUI 滚动和熄屏长跑表现。

## 2026-11-26 恢复命令与诊断日志

从 SU 1.0-rc.18 起，新恢复决策事件直接记录中文原因、连接状态和连续恢复尝试次数，APK 源码也已同步。WebUI 和 APK 监控页可将旧版 `decision=… state=…` 事件显示为中文，已有日志文件及供脚本读取的状态代码保留原格式。

APK 1.0-rc.6 修复 1.0-rc.5 在无诊断历史时打开「监控详情」闪退的问题。V2505A 的异常堆栈指向 `DiagnosticHistory.read`。APK 构建流程新增空历史、空归档、单条历史和截取最近记录的回归检查。

这一轮日志和恢复命令调整最初随 KernelSU 1.0-rc.17、APK 1.0-rc.5 引入。

APK 调试构建和 KernelSU ARM64 定时器构建通过。V2505A 已安装并冷启动独立包名的 APK 1.0-rc.5。脚本回归和真实只读采样在隔离目录中执行，手机上的正式 APK 和 KernelSU 守护服务继续使用原部署版本。

- KernelSU 与 APK 均移除 `GTALK_HEARTBEAT` 和 `GTALK_RECONNECT`。V2505A 当次动态广播登记未出现这两个接收器，记录中两种命令各出现 4 次，共 7 次下一次采样仍未连接，1 次缺少后续结果。恢复序列保留 5 种动作。APK 权限为 ADB Shell 时先尝试心跳，证据连续不可用的保活路径只发送两种心跳。
- 两端按 UTC 日期轮转诊断日志。保留至少 48 小时，归档最近一次写入满 48 小时后才清理，默认界面仍只显示最近一部分。KernelSU 可用 `ctl.sh log all` 和 `fcm-monitor.sh events all` 读取所有归档。APK 可从「诊断 → 高级 → 导出完整诊断日志」保存文本。导出跨权限模式时以当前授权模式的 FCM 事件为准。
- KernelSU 和 APK 的启动记录新增版本。老版本没有版本字段的记录只按已核对的安装时间和服务 PID 辅助归属。历史累计计数跨版本共享，旧版已截断的日志无法从当前文件恢复。
- FCM 恢复日志区分系统接受命令、复采仍未连接、证据不可用、复采已连接。保留事件代码、返回码和系统原文以便检索。APK 补齐手动恢复结果提示，移除分享报告中重复的 FCM 事件段。
- APK 在发送保活心跳前先保存 15 分钟退避时间，保存失败时不发送。两条均未被系统接受时记录失败，连接状态仍为未知。巡检写入证据失败会向上层返回失败。真机隔离回归覆盖 Root 与 ADB Shell 的完整触发顺序、双心跳保活和退避。
- V2505A 无线 ADB 验证了两端脚本的恢复序列和 48 小时轮转边界。真实内核只读采样均识别到 GMS 已建立 TCP 5228 长连接。JVM 验证了 APK 运行日志迁移、排序与清理边界。模拟轮转通过推进测试时间完成。

> 更新：2026-11-25。本文件只记录当前状态、已验证事实和未解决事项；不保留逐次迭代的过程记录
> （历史记录可在 git log 中查到）。唯一产品基线：[PRODUCT_PLAN.md](PRODUCT_PLAN.md)。

## 当前版本

- KernelSU 模块：`v1.0-rc.15`（`module/module.prop`）。已在一台 OriginOS 7 真机
  （vivo PD2505 / V2505A）实际安装运行，经 `adb` 连接验证 Root 可用、数据目录和日志存在。
- APK：`v1.0-rc.3 / versionCode 10003`（`app/build.gradle`）。尚无 GitHub Release，仅有
  Actions Artifact；OriginOS 真机的无线调试配对、后台保活等均未完成验证。
- 仓库只保留 `main` 一个分支；`fix/rc5-mcs-patrol-20261122` 的内容已合并进 `main` 并删除。

## KernelSU 端当前判定逻辑（已读代码确认，非转述文档）

- **判定依据**：`module/bin/fcm-monitor.sh` 完全不调用 `dumpsys`。唯一证据来源是 GMS UID
  归属的内核 TCP 表：优先 `ss -tinpe`（含 TCP_INFO），不可用时降级 `ss -tnpe`，仍无法确认
  UID 归属时回退 `/proc/net/tcp` / `/proc/net/tcp6`（`scan_sockets()`）。
- **状态来源**：`connected`（已验证 MCS 端口 5228-5230 或已验证 mtalk :443 建立）、
  `connecting`（SYN-SENT）、`stalled`→归并为 disconnected（TCP_INFO 显示 unacked 且连续
  重传 ≥3，或 30 分钟无收包）、`absent`→归并为 disconnected（未观察到任何 MCS socket）、
  `unknown`（证据不可用，不当断联也不当恢复）。
- **断联确认阈值**（`auto_recovery()`，按 `source`/`state` 分支，不是统一的单一数字）：
  `source=gms_socket_absence`（完全没看到 socket）45 秒；`state=disconnected` 的其他来源
  （如 `gms_socket_stalled`）15 秒；`state=connecting` 60 秒。达到阈值后二次采样
  （`confirm_recovery()`，间隔 2 秒）仍保持断联/连接中才进入恢复。
- **采样空档**：超过 90 秒未成功采样，重置连续性锚点，不把空档当作连续断联证据
  （`observe()` 的 `sample_gap_age` 检查）。
- **恢复序列**（`recovery_actions()`，共 4 个动作）：
  - Root（UID 0）：`GCM_RECONNECT → MCS_HEARTBEAT → ACTION_HEARTBEAT_NOW → GCM_SERVICE_START`
  - ADB shell（UID 2000）：顺序不同，`GCM_RECONNECT` 挪到倒数第二位（因为该广播在
    OriginOS 7 上对 UID 2000 可能不导出；对 Root 广播已实测确认可被系统接受，见下）。
  - 每个动作被系统接受后等待最多 5 秒复采（`settle_wait`），`connected` 立即停止整个序列；
    `connecting`/`disconnected` 继续下一动作；`unknown`（证据暂不可用）不当断联也不当恢复，
    同样继续下一动作。全部 4 个动作执行完仍未恢复才记为 `recovery_exhausted`，按退避重试。
  - 退避间隔由 `retry_streak` 驱动：第 1-2 次 30 秒，第 3 次 45 秒，第 4 次 60 秒，之后
    固定 90 秒；恢复后清零。
- **`ctl.sh`**：仍调用 `dumpsys` 读取应用 `stopped`/`suspended`/`hidden` 状态和广播接收者
  列表，但只用于 `check` 子命令的只读诊断展示，不参与上述任何判定或恢复决策。`fix()`
  直接对已安装目标执行 `cmd package unstop`，不依赖 dump 结果；已去掉"最多处理 10 个应用"
  的硬限制（原因见下）。

## 2026-11-25 实机验证记录

- **Root 下的 `GCM_RECONNECT`/`MCS_HEARTBEAT` 广播均被系统接受**（`am broadcast` 返回
  `result=0`，无 `Permission Denial`/`SecurityException`）。说明 KernelSU（Root，UID 0）
  的重连广播路径本身没有被这台 OriginOS 7 设备拒绝；APK 端 UID 2000 之前报告的广播拒绝是
  另一条独立路径的问题，不能互相引用来下结论。
- **`ctl.sh fix()` 的 10 个应用硬限制在真机上确实会截断**：当时设备 `targets.txt` 有
  12 个目标，每轮巡检日志都精确停在第 10 个（`"本轮最多修复 10 个应用"`）。已移除该限制
  （去掉 `count` 计数器和对应的 `break`），并用设备上真实的 12 个目标名单重新跑过
  `fix`，确认 11 个已安装目标全部被处理。
- **`scan_sockets()` 曾把整段 socket 表通过外部 `printf` 二进制传递三次**，设备日志里
  反复出现 `/system/bin/printf: Argument list too long`。已改为 here-doc 输入，避免依赖
  `execve()` 的 argv 大小。**但这次在设备上未能复现该报错**：实测 socket 表约 90KB、
  `mcs-monitor.state` 207 字节、日志单行最长 162 字节、当前 shell 环境变量约 7KB，均远
  低于设备 `ARG_MAX`（2MB）。因此这项改动是防御性加固，不能确认已解决真正触发条件。
- **这台 Windows 开发机的 `git config core.autocrlf` 曾为 `true`**，导致 clone 下来的
  shell 脚本在工作区被转成 CRLF，在 Android `sh` 下解析报 `unexpected 'newline'` 等错误。
  已设为 `false` 并重新 checkout 干净的 LF 文件。**在这台机器上编辑 shell 脚本后，应先
  用 `git diff --stat` 确认改动行数接近预期，若显示整文件行数变化，先检查换行符。**
- 修复代码已在设备的 `/data/local/tmp` 沙箱路径下用真实 Root 权限和真实 socket/应用
  列表验证过（语法检查 + 真实执行），未污染 `/data/adb/berry_fcm_ksu` 下的生产数据。

## 未解决事项

1. **"Argument list too long" 真实触发条件未定位**。已排除的候选：socket 表大小、state
   文件大小、日志单行长度、当前环境变量大小。下次复现时需要在报错发生的同一进程里直接
   dump 当时的 `ps`/`/proc/<pid>/environ` 等信息，而不是事后用干净环境重放。
2. **一次真实的采样空档**：设备日志显示 `fcm_check_start` 于某次 18:51:58 发起后卡住，
   直到约 57 秒后被 `patrol_watchdog_stale` 检测到、18 秒后由 `patrol_supervisor_start`
   重启服务，期间约 75 秒无新采样。`patrol.sh` 的看门狗机制确实生效了，但这次具体是哪条
   命令挂起仍未定位。
3. **APK 端真机验证**（无线调试配对、TLS 握手、Priv Kit 独立服务启动、后台保活、GitHub
   Release 覆盖升级）均未完成，进度以 [PRODUCT_PLAN.md](PRODUCT_PLAN.md) 为准。
4. **KSU 与 APK 的 FCM 判定逻辑尚未统一**：APK 端 `app/src/main/assets/fcm-monitor.sh`
   仍是基于 dumpsys 的旧方案，没有跟进 KSU 端已经完成的"内核 Socket 唯一判据 + 七步恢复
   序列"重构。按既定范围，这次只处理 KSU 端，APK 的同步留待 APK 真机验证完成后再排期。

## 下一步（建议顺序）

1. 下次复现 `Argument list too long` 时先采集触发瞬间的真实进程状态，再决定要不要进一步
   收紧 `fcm-monitor.sh` 里其他尚未改动的 `printf`/`awk` 调用。
2. 定位 `patrol_watchdog_stale` 对应的具体挂起命令（最可能是某次 Shell 调用缺少超时保护）。
3. APK 端按 `PRODUCT_PLAN.md` 的 G2/G3 阶段继续推进真机授权与监控验证。
4. KSU 端的内核 Socket 判据与七步恢复序列稳定后，再评估回移到 APK。
