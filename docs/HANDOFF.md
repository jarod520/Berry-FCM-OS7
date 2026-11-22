## 2026-11-22 DNS timeout applet fallback修复

- 发现 `resolve_mtalk()` 只判断 `/system/bin/toybox` 文件存在，就直接调用 `toybox timeout`；如果设备 Toybox 编译时未包含 timeout applet，即使 PATH 中存在可用的 `timeout`，DNS 查询仍会失败并把失败缓存 10 分钟，导致 mtalk DNS :443 辅助证据无法建立。
- 已新增 `BERRY_TOYBOX_BIN`（默认 `/system/bin/toybox`）并按 applet 清单检测 `timeout`；Toybox 缺少该 applet 时回退 PATH 的 `timeout`，两者均不可用时安全跳过 DNS 查询，不执行无超时 nslookup。
- 新增 FCM smoke 场景：模拟 Toybox 存在但 `--list` 不含 timeout，同时 PATH 有 timeout，确认两个 mtalk 主机均会查询并通过 DNS 地址识别 GMS UID :443 连接。
- 在容器中按修改后的分支条件执行了独立行为模拟：Toybox mock 不提供 timeout，PATH timeout 成功运行两次 nslookup，结果通过。该模拟只验证 DNS fallback 代码路径，不代表完整 smoke 套件已执行。
- 当前完整 `fcm-monitor-smoke.sh`、`ksu-wake-smoke.sh` 和完整 Shell syntax gate 仍未执行；未触发 workflow、构建、打包或发布；PR 未合并。
## 2026-11-22 KSU lifecycle smoke 重复块清理与 Toybox timeout 核实

- 复核 `tests/ksu-wake-smoke.sh` 发现测试主体从 hotinstall 顺序断言开始被重复追加 4 次；每个重复块前还有一条裸执行 `"$ROOT/module/bin/patrol.sh"` 的孤立命令，且后续重复块缺少 `hot_stop_line` 赋值。原脚本会在 `set -e` 下提前失败，不能作为有效验收。
- 已保留第一份完整测试主体（312 行），删除后续三份重复主体和孤立命令。源码复核确认 `hot_enabled_line`、`hot_stop_line`、hung monitor、orphan patrol、no-timeout fallback 等核心场景现在各保留一份。
- 与前一项 FCM smoke 修复合并核对：学习 IP TTL 区块只有一份；不存在将 learned-IP 数据文件当命令执行的行；TTL 区块单独 `sh -n` 通过。
- **Toybox 方案核实**：上游 Toybox `timeout` 默认创建独立进程组，并对负 PID 发送 TERM/KILL，因此该 applet 能将超时信号传给命令的进程组及其子进程；当前 patrol 在检测到 Toybox timeout 时优先使用它。来源： https://github.com/landley/toybox/blob/master/toys/other/timeout.c 。这证明上游实现的行为，但尚不能证明用户设备上的具体 Toybox 构建包含该 applet。
- 无 timeout 时，当前脚本检测 setsid + kill 后自行创建会话并按进程组清理；同时缺少 timeout 与 setsid 时只能直接终止 monitor PID，不能保证所有后代退出。暂不添加复杂递归杀进程实现。
- **验证状态**：本轮只做源码结构检查与修复后 TTL 片段 `sh -n`；两个完整 smoke 套件尚未运行，完整 Shell 语法检查、实际 Android/KernelSU 运行均未完成。不得标记测试通过或允许构建。
- 未触发任何 workflow、编译、打包或发布；PR 未合并。
## 2026-11-22 smoke 测试脚本修复：学习 IP TTL 用例

- 复核 `tests/fcm-monitor-smoke.sh` 末尾发现学习 IP TTL 用例存在实际脚本错误：一条 `grep -q` 命令缺少闭合引号和文件参数；第一次输出 PASS 后又残留一行将数据文件路径当作命令执行，并重复了整段 TTL 用例。
- 该错误会使整个 smoke 脚本无法通过 shell 解析，或在执行到残留路径命令时因 `set -e` 提前退出；此前不能把这组用例视为有效测试。
- 已将 TTL 用例重写为单一完整区块：检查刷新后只保留最新的 `IP|epoch` 记录、旧 plain-IP/非法/未来时间戳被丢弃、120 秒内允许已学习 MCS 对端的 443 辅助证据，以及 121 秒时过期后回到 unknown。
- 对修复后的 TTL 区块单独执行 `sh -n`，语法检查通过；通过 GitHub 源码复核确认重复标记和将数据路径作为命令执行的残留行已消失。
- **限制**：完整 `fcm-monitor-smoke.sh`、`ksu-wake-smoke.sh` 尚未实际执行；也未执行完整仓库 Shell 语法检查。不能据此宣称 smoke 通过。
- `patrol.sh` 的无 timeout 兜底在存在 setsid 时尝试按独立进程组清理；当目标环境同时缺少 timeout 与 setsid 时，只能确认终止 monitor 主进程，不能保证所有后代进程退出。当前不加入复杂的递归 `/proc` 杀进程逻辑，需在目标设备确认 Toybox applet 清单后再决定。
- 本轮未触发 workflow、编译、打包或发布；PR 仍未合并。


## 2026-11-22 历史自动 Smoke 失败复核

- 查询 Actions 历史发现旧工作流 `.github/workflows/validate-fcm.yml` 在提交 `e18b90d` 上曾由 push / pull_request 自动触发（run `45014447855` / `45014452369`）。Shell syntax 步骤通过；`fcm-monitor-smoke.sh` 在“suspend gap / double confirmation / native restoration”用例之后退出，后续用例被跳过。该失败发生在本轮学习 IP TTL 修改之前。
- 对比失败提交与当前测试脚本，确认旧“stopped GMS”夹具互相矛盾：同时给出 `Not connected` 原生状态和 `stopped=true`，但测试又要求不能发送重连。现版本改为 `No services match` + Socket ownership unknown + `stopped=true`，先测试停止服务时不恢复；在广播失败用例前再显式恢复 `Not connected`，保证失败广播路径有真实断联输入。
- 当前 PR 分支的 `.github/workflows/` 仅有 `build-ksu.yml`、`build-apk.yml`、`verify-prebuild.yml`，三者均只允许 `workflow_dispatch`；因此推送此功能分支不会自动触发构建。`main` 分支仍保留三个 workflow 对 `main` / `release/1.0-rc.1` 的 `push` 触发规则；PR 尚未合并，因此这些主分支触发器没有被触发。历史 `validate-fcm.yml` 已不在 main 与 PR 分支目录。本轮新提交没有触发 workflow，也没有编译/打包。
- 历史失败已找到对应夹具修正，但**当前完整 smoke 尚未执行**；不得将历史失败视为当前版本通过，也不得将夹具修正等同于实测通过。
- 另查到更早的旧分支自动 KSU workflow run `45013860365`：Shell 语法通过，但 smoke 首个原生时长断言得到 `fcm_native_duration=-1`，预期 `202`，随后 workflow 在 `Validate shell scripts and FCM lifecycle monitor` 步骤失败，Go ARM64 编译与 ZIP 打包步骤均被跳过。该记录对应旧提交 `af2f014`，不是当前 HEAD；当前测试保留 `202` 断言，当前解析器实现也已迭代。历史自动运行没有真正消耗后续 Go 构建步骤。

## 2026-11-22 KSU RC7：学习到的 MCS 对端 IP 有效期

- 复核发现 `LEARNED_IPS` 原先只追加并去重，没有过期机制。若某个 Google IP 后续被 GMS 用于普通 HTTPS :443，旧学习记录可能让该连接被误识别为 MCS。
- 已改为 `IP|epoch` 格式，只有从 GMS UID 的 ESTABLISHED 5228/5229/5230 Socket 学到的地址才可进入记录；每轮刷新时清理超过 **120 秒**、时间戳在未来、格式不合法的条目，并按 IP 去重保留最新时间。旧版单纯 IP 行不会迁移，避免把没有时间依据的历史记录重新当成新鲜证据。
- DNS 地址与学习地址继续分开保存；DNS 解析刷新失败仍清空过期 DNS 集合。学习地址只参与 :443 弱证据判定，不覆盖原生 GMS 状态，也不改变精确 MCS 端口判断。
- 新增 `tests/fcm-monitor-smoke.sh` 回归场景：5228 学习后短时间同 IP :443 可识别；旧 plain-IP 记录被丢弃；超过 120 秒后相同 :443 不再判 connected。
- **尚未执行 smoke 测试或构建**。GitHub connector 只能读写仓库，当前没有本地可运行 Shell 的 checkout；不能把测试脚本已添加说成测试通过。下一步继续检查 shell 兼容性、生命周期与回归夹具，再安排一次完整 smoke。
- 本轮提交：`c13536b`（加入时间戳学习记录与清理）；`518ca01`（TTL 收紧至 120 秒）；`71b67c6`（增加过期回归用例）。当前分支 HEAD 以本段后续更新提交为准。
- 追加防御：读取 `LEARNED_IPS` 时再次按当前时间过滤 `0 <= age <= 120`，即使临时文件写入/原子替换失败，也不会把已经过期的磁盘记录重新用于 :443 判定。对应提交 `67b649b`。
- 后续审查补充：学习记录写入前要求系统 epoch 有效；读取端再次独立执行年龄校验，避免清理写入失败时旧记录继续生效。回归夹具同时覆盖重复地址、非法 IPv4、未来时间戳和旧 plain-IP 格式。提交 `9aba0da`、`a8efe82`。本地只对提取出的 TTL helper 执行了 `sh -n` 与行为模拟；完整仓库的两个 smoke 套件仍未执行。
- 读取端也增加独立 IP 格式校验，并要求 epoch 大于 0；即使磁盘中存在格式错误的带时间戳记录，或清理原子替换失败，也不会用于 :443 证据。提交 `369f13e`。



## 2026-11-22 KSU RC7 追加审查：维护锁身份校验

- 本轮继续审查 `module/bin/patrol.sh` 的后台维护任务锁。原实现只用 `kill -0 PID` 判断 `maintenance.lock` 是否仍被占用：PID 被系统复用时，可能把无关进程误认为维护任务仍在运行；旧维护子进程退出时也可能误删后来创建的新锁。
- 已修正：维护子进程从 `/proc/self/stat` 读取自身 PID，并记录 PID + `/proc/<pid>/stat` starttime 到原子替换的 `maintenance.lock/owner`；巡检只在 PID、starttime 匹配且进程不是 zombie 时认定维护任务存活。清理时再次核对 owner 身份，只允许当前维护进程删除自己持有的锁。发现刚创建但尚未写入 owner 的锁时，先等待 1 秒再判定，避免直接清理启动中的任务。
- 已为 `tests/ksu-wake-smoke.sh` 增加维护任务身份登记、starttime 校验和 owner 限定清理的静态断言。**本轮没有执行 smoke 脚本**，因此只记录代码与测试用例已更新，不记录测试通过。
- 本轮提交：`550d06a52c7efcc3fe4207728d319ee9e0b51ce8`（维护锁实现）；`bcab9f5ff1b10c9d3164798fc7f873bd04660ff2`、`7d5e41afc4da8e486ecc7622063f1340d67c6fd2`（修正新增日志换行与 Shell 行续接转义）；`a5033a0bee2e01ea5990e1f00a300983bcbe68da`（忽略已退出的 zombie 维护进程）；`d3127447cc7a524d9738e1809d25d04225939e33`、`81b282c01991daf2dc847f5ef659a943e0ed47ba`（patrol 自身身份登记及 PID 安全读取）；`70c6e8e50de3aebd940dd714369c459357bf5c70`、`d37092975554881831b4ae5595435da3f87201c2`、`10e7637d3e58253231326e2c9146aeed3d423eb8`、`0eca923a7e5f066e8e86d92aab4a34a95926c114`、`2c32ed69a9ebb6b3f45fdc3dc5c398ae323299d3`（维护锁、登记竞态、Shell 转义与 hotinstall 顺序静态断言）。当前分支以本次交接文档提交后的 HEAD 为准。
- 本轮追加修复 patrol 启动登记竞态：`patrol.sh` 启动后先校验 `service.lock/pid` 与 `starttime` 确实属于其父 service，再从 `/proc/self/stat` 读取自身 PID、计算 starttime，并原子写入 `service.lock/patrol`。原 service 侧登记仍保留，父子两侧写入同一身份，覆盖 service 在 fork 后、登记前意外退出的窗口。测试增加对应静态断言。另修正上一轮测试脚本中被错误覆盖的 `hot_stop_line` 计算，恢复 hotinstall 停止旧服务必须早于读取 enabled 状态的顺序检查。
- `run_bounded` 的无 timeout 兜底：存在 `setsid` 时可按独立进程组清理 monitor 及子进程；目标系统同时缺少 timeout 与 setsid 时，只能确认终止 monitor 主进程，无法证明所有后代均退出。暂不引入依赖 `/proc` 递归枚举的复杂杀进程逻辑，后续结合目标设备实际 Toybox applet 清单确认是否需要调整。`LEARNED_IPS` 同一启动周期内长期保留，仍存在远端 IP 后续复用时将普通 GMS HTTPS :443 误识别为 MCS 的理论风险；需先完善有 TTL 的回归样例再改动，当前不把理论风险当作已发生故障。
- 当前仍未运行两个完整 smoke 套件、未触发构建/打包、未合并 PR、未发布 Release，也未进行 OriginOS 7 实机验证。工作流保持仅 `workflow_dispatch`；按用户要求，全部代码修改与检查结束后再告知用户可以进行一次完整构建，不提前触发。

## 2026-11-22 KSU RC7：原生 Close 辅助判据、分阶段恢复与卸载清理

- 基于 RC6 提交 `d9312e44a6b0c4110a6dbc383c39def40bde131b`；本轮候选版本 `1.0-rc.7 / 10007`，仍属于测试候选，不合并 main、不发布正式 Release。
- GMS dump 只有 ActivityManager wrapper 时仍保留 unknown；Root 可见的精确 GMS UID MCS TCP 缺失连续 30 秒后才转为断联，并经第二次采样确认。连续巡检超过 15 分钟不会清零断联计时；只有采样空档超过 90 秒才重置连续性锚点。持续 SYN-SENT 会保留首次观察时间，达到 60 秒进入恢复判断。最近 Close 事件在 Socket 所有权不可读、持续 30–900 秒且没有更新的 Connected 事件时，作为有限期辅助证据；单次 Close 不直接触发重连。
- 自动恢复按连续未恢复轮次依次尝试 `GCM_RECONNECT`、`MCS_HEARTBEAT`、`ACTION_HEARTBEAT_NOW`、`GTALK_HEARTBEAT`；每轮只发送一种动作，后续轮次必须由新采样再次确认仍断联并经过退避。广播返回成功只记录为已请求，不等于 GMS 已恢复；恢复必须由后续原生状态或精确 MCS Socket 证据确认。
- service 独立监督 patrol：PID/starttime/cmdline 身份校验；同时监控 patrol 进程心跳和成功完成的 FCM 样本心跳，避免 patrol 循环仍在运行、但监控锁长期被占用时被误判为健康；记录 monitor 锁所有者 PID/starttime，样本超时后只终止身份核验通过的卡死 monitor。service 清理 worker 未确认退出时保留锁；新 service 回收旧锁前先核验并终止遗留 patrol，无法确认退出则拒绝启动重复巡检。首次心跳缺失也有 90 秒兜底。停止 monitor/timer/patrol 使用有界 TERM/KILL 等待，未确认退出时不启动重复 worker。热安装/卸载等待旧 service 最长 24 秒，KILL 后再复核；热安装若旧进程仍存活则取消新启动。保留数据目录配置与历史，不强制重启。
- 开源参考：继续参考 microG GmsCore 的 MCS 连接/心跳恢复模型及 AOSP Toybox `timeout` 的进程组超时清理。本项目当前第四阶段使用 `GTALK_HEARTBEAT`；未将 HyperOS 专用 Chimera Provider 查询直接移植到 OriginOS。DNS 解析失败也缓存 10 分钟，避免每轮重复等待。
- 本轮巡检兜底修复：没有可用 `timeout` applet 时不再返回 125 并跳过采样；改用 watchdog 限时，若 Toybox / KernelSU BusyBox 同时提供 `setsid` 与 `kill`，按独立进程组清理 monitor 子进程。后台每轮读取 Socket，原生 `GcmService` dumpsys 默认每 60 秒刷新一次；手动恢复及原生二次确认强制刷新，`no_current_state` 额外重试也限制为每 60 秒最多一次。两次原生采样之间，最近一次有效 connected 状态不会因 Socket 缺失/所有权不可读而被误判断联；最近一次有效断开/连接中状态也不会因 Socket 缺失/不可读或暂时 ESTABLISHED 而被覆盖，须等下一次原生采样或独立 Socket 缺失阈值确认状态变化。新增对应 smoke 用例；目前尚未执行整套 smoke 或完整构建，不能记为测试通过。
- 当前进度：源码与回归用例仍在集中修复，尚未执行本轮完整 smoke 套件、完整构建或 OriginOS 7 实机验证。`.github/workflows/` 下所有工作流已改为仅 `workflow_dispatch`，不再由 push/PR 自动触发。按用户要求，全部代码修改与静态检查完成后，只手动触发一次完整构建；不自动编译、不自动打包、不合并、不发布。

# Berry-FCM-OS7 开发进度与接续交接

## 2026-11-22 KSU RC5 巡检与状态解析修复候选

- 修复分支：`fix/rc5-mcs-patrol-20261122`，从当前 main 建立，避免旧 RC3/RC4 分支的版本与文档冲突。
- GMS 状态解析：参考开源项目 `XXhaos/OriginOS-FCM-Fix` 的 `GcmServiceParser`，补充严格识别 GMS 服务块中的 `Is client connected: true/false`。仅在目标 GMS 服务范围内接受；与其它状态冲突时仍返回 unknown。false 不把 connected 时长误当断联时长。
- 巡检隔离：原 `service.sh` 在主巡检循环中同步执行 `ctl.sh fix`，其多包查询/广播可能阻塞下一轮 MCS 采样。改为独立后台维护事务，以 `maintenance.lock` 防重入；主循环不等待维护完成。保留开始/结束、退出码和耗时日志。
- 测试新增：GMS client true/false 真实格式解析与 false 自动恢复；仅 unknown + 连续 Root GMS UID MCS socket 缺失达到阈值后恢复；慢速 stopped 维护期间 MCS 巡检继续运行。
- 模块候选版本：`1.0-rc.5 / 10005`。当前尚未取得 CI 成功记录或 OriginOS 7 真机验收，不可宣称修复完成或发布。


## 2026-11-22 本地 KSU RC4 测试包

- 用户要求先提供本地 SU/KernelSU 测试包；本轮仅将 KSU 模块版本升至 `1.0-rc.4 / 10004`，APK 版本仍为 `1.0-rc.3 / 10003`。
- RC4 使用 `71e6ba4` 的巡检诊断和恢复逻辑，构建 ARM64 `wake-timer` 后打包。此包用于设备测试，不代表 GitHub Actions、回归套件或手机验收通过，也不创建 Release。
- 模块安装脚本请求 KernelSU 官方热安装。模块内没有设备重启命令；`reboot` 只用于记录启动周期变化。若管理器仍提示重启，先以安装输出确认当前管理器是否支持模块热安装。

> 最近整理：2026-11-22。**唯一产品基线：** [PRODUCT_PLAN.md](PRODUCT_PLAN.md)。本文件只记录当前真实状态、构建证据、未验证项目和接续动作。全部代码和文档在 GitHub；不跳转 Work。用户电脑文件仅允许存放 D:\Codex，未获许可不触碰 C 盘。

## 0. 2026-11-22 接续：SU/KSU 原生状态与长采样空档

- 用户确认这次检查的是 SU/KSU 版本；手机持续亮屏，后台模式设为定时巡检 1 分钟。现有记录中的空档为 128、162、512 秒。**不能用熄屏 Doze 解释，也不能从旧日志判定是定时器、GMS 检查调用、守护修复命令还是服务进程造成**；旧版没有逐次调用的开始/结束证据。
- `v1.0-rc.4` KSU 测试包在 `guard.log` 记录 `service_started`、每次 `fcm_check_start/end` 及每轮 `maintenance_start/end`；`wake-timer.log` 自带 `wake_timer_armed/fired`、迟到和 suspend 时长。以后可按最后一条完整记录定位空档所在阶段。**这些字段不会补写旧空档。**
- 当 `dumpsys` 只有 ActivityManager wrapper 行时，SU/KSU 将读取 Root 可见的精确 GMS UID MCS TCP：连接/连接中作为正证据；连续缺失至少 60 秒并复核后才可判定断开并进入原有恢复判断。普通 443、UID 表读取失败不当作断联。APK UID2000 不使用 Root 才能观察到的缺失判断。
- 若原生仍报 Connected 且 `connectTime` 正数连续 5 分钟不增长，SU/KSU 会二次采样；自动守护开启时仅发定向 `GCM_RECONNECT`，不会 force-stop GMS。计时恢复则取消。
- 更新和安装：保留 KernelSU 官方 hot-install 入口，启动新服务替代旧服务；源码没有发出设备 reboot 命令。`reboot` 事件只是观察到启动周期变化。
- 诊断与恢复源码在 `71e6ba4` 已推送 `main`；其最近一次 GitHub Actions 未通过，RC4 不宣称 CI 验证完成。本地 KSU 包基于该提交，仅升级模块版本号并编译 ARM64 定时器；本轮未推送版本号更新、未创建 Release、未运行回归、未在手机实测。后续根据手机日志和失败 CI 定位修复，再走云端完整验证与测试 Release。

## 1. 不可变更的产品目标

- **APK 优先**：完整迁移 KernelSU 版有价值的 FCM Socket 监控/重连、事件历史、应用 stopped 守护、GMS Doze/后台网络策略与诊断。APK 稳定后再将可靠改进回移 KernelSU，**两条线保留**。
- **先做完整可操作的 UI 和功能，再请求用户测试**。首页只显示概览和授权入口；独立授权、FCM 监控、应用守护、后台保活、诊断、设置、在线更新模块。不得恢复旧的堆叠长表单。
- **无线 ADB 配对码必须从系统通知栏 RemoteInput 输入**，用户在 OriginOS 的“无线调试”界面下拉通知提交，不能切回首页输入。自动 mDNS 发现端口，手动端口仅备用。
- Android API 可做的不用 ADB，ADB/Root 可做的不用无障碍；**不管理其它应用的无障碍服务，也不申请 AccessibilityService**。FGS 自动恢复和 FCM Tile 是正常 Android 服务，不需要无障碍。
- 标准 Android 策略尽力通过 ADB/Root 配置并回读；OriginOS 厂商自启、关联启动、高耗电、任务锁定如无可信私有 API，只能跳转系统页面手动授权，**不能伪造状态开关**。
- Android 可能停止普通 APK，ADB Shell 配对身份不等于永久权限。Socket 缺失/不可读/样本中断要区分；TCP 连接不等于 FCM 已认证/推送必达。任何重连广播不等于实际恢复。
- 新安装包必须使用现有固定签名证书，GitHub Actions 编译、签名、验签和制品上传。GitHub Release 升级从**手动批准的正式 prerelease**获取，不自动发布半成品。

## 2. 已合入的新版 APK 模块

首个模块化重构提交：[ecd20cde](https://github.com/jarod360/Berry-FCM-OS7/commit/ecd20cdefd81854c432e8565783ab3cc0f2abd7d)。第二次增强：[ed18989f](https://github.com/jarod360/Berry-FCM-OS7/commit/ed18989fb216ea9118ca8a7a2503799000f13c86)。

| 页面 / 组件 | 已合入代码 | 关键约束 |
| --- | --- | --- |
| 首页 \`MainActivity\`, 共用 \`Ui\` | 监控概览、授权单按钮、各模块导航、WindowInsets 状态栏/导航栏安全区域、主题底色 | 首页无配对码输入/无障碍服务列表 |
| \`AuthActivity\` + \`AdbPairingService\` | Root / 无线 ADB / 静态端口、通知栏 RemoteInput 六位码、mDNS 自动发现、配对状态、权限申请 | 必须在目标 OriginOS 真机验证配对是否可用；不会保存配对码 |
| \`FcmMonitorService\` + \`MonitorActivity\` | 前台服务 15s 采样目标、事件历史、未知/过期/断联区分、受控手动重连、服务退出后按系统规则尽力恢复 | 启动和 Shell 失效均需显示诊断；不宣称永久保活 |
| \`GuardActivity\` + \`GuardOps\` | 包名/名称搜索、系统应用过滤、已选置顶、多选、GMS 核心目标、stopped 检测/受控修复、后台约 5 分钟检查 | 与旧第三方无障碍服务扫描完全不同 |
| \`BackgroundActivity\` + \`BackgroundSettings\` | 监控/守护/开机恢复开关、应用电池豁免、标准 Android AppOps、GMS Doze、OriginOS 厂商页面、最近任务隐藏恢复 | 厂商私有开关跳页手动；已存在的 GMS 白名单不能冒充自己添加 |
| \`DiagnosticsActivity\` | Google 原生 FCM Diagnostics、mtalk TCP 可达性、监控事件分享 | Root/ADB 测试路由和 GMS UID 路由可能不同 |
| \`SettingsActivity\`, \`UpdateActivity\` | 跟随系统/浅/深主题、FCM 磁贴添加、项目主页、GitHub Release 检查/下载/包名+签名校验/系统安装 | 还没有正式 Release；更新页应显示无可用 Release |
| \`BootReceiver\`, \`FcmTileService\` | 开机/更新后恢复**用户开启的 FCM 监控与应用守护**，磁贴执行 FCM 即时检查或打开监控 | 不启停、恢复其它应用无障碍 |

**已删除**：\`AccessibilityOps.java\`、\`RestoreService.java\`、\`RestoreTileService.java\`，及其 Manifest 注册和无关 \`WRITE_SECURE_SETTINGS\` 授权。原有“已勾选第三方无障碍服务”历史配置不自动映射为“守护应用”。

## 3. 确认过的构建事实

- 固定签名证书 SHA256：\`BB328497280F72FE6662E84D7D0D0B15BAF425872B9B360287ED120529D97615\`。同一 keystore GitHub Actions Secrets **已经配置且实际签名成功**；不再重新生成、不再索要或修改四项 Secrets。
- **新版首轮 APK 构建**：[Actions #44138228340](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44138228340) 成功，Gradle Debug/Release、keytool、apksigner、Artifact 上传全部通过；\`BerryFCM-Guardian-v0.1.0-alpha.29\`。
- **最新已验证的 APK 构建**：[Actions #44139303543](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44139303543) 成功，\`tests/fcm-monitor-smoke.sh\` 和 \`tests/apk-module-smoke.sh\`、编译、签名、验签、Artifact 上传均通过；\`BerryFCM-Guardian-v0.1.0-alpha.30\`。
- **同次 KSU 构建**：[Actions #44139303661](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44139303661) 成功。KSU 模块仍为 \`0.5.4-test\`，数据目录 \`/data/adb/berry_fcm_ksu\` 沿用旧配置。
- **KSU 追平增量已经通过 CI**：[commit 615121d7](https://github.com/jarod360/Berry-FCM-OS7/commit/615121d72494887d1b251d34cf45ac76ef24c367) / [APK Actions #44140579529](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44140579529)，FCM/结构模拟测试、Gradle、固定签名和 Artifact 上传全部成功，APK `BerryFCM-Guardian-v0.1.0-alpha.31`。新增 90 秒巡检、受控 GMS 心跳、Doze 与计量网络、策略/通知诊断代码均在该版本中；**手机权限和效果尚未验收**。
- GitHub **Releases 列表仍为空**；工作流 \`workflow_dispatch.publish_release\` 默认 false，仅手动选择发布且签名 APK 构建成功时才创建 Release，尚未执行发布。应用内升级是否正常需首次 Release 后实测。

以上 CI 证明源代码和签名链路有效，**不表示手机已成功完成 mDNS 配对、锁屏过夜监测、stopped 恢复或覆盖升级**。

## 4. 本轮最后一次需求定案与截图问题

用户提供的 alpha.26 截图确认：旧主界面“可管理无障碍服务”不属于项目目标；在旧主界面输入 ADB 配对码，无法与系统无线调试页面同时操作；标题顶住状态栏；长页面难以使用。**修复方向不是继续让用户测试旧版，而是先交付完整模块、通知栏配对、系统安全区域布局和原有 KernelSU 功能迁移**。最新版原生代码已包含解决这些问题的实现，仍要真机确认效果。

## 5. 待验证事项（只陈述事实，不填成功）

1. 在 Android 17 / OriginOS 实机测试：从授权页开启监听 → 系统无线调试配对 → 下拉通知栏输入六位码 → mDNS 识别本机配对端口 → Shell UID 读回。未知 ROM 行为不得推断。
2. 运行态下 ADB \`ss -tnpe\` 能否读取 GMS UID：如果权限限制/UID 元信息被隐藏，要显示 unknown；需要 Root 时明确说明。
3. 监控是否在未打开主界面时持续采样，CPU suspend/Doze、系统后台管控、无线调试关闭后的错误/恢复是否明确；真实 FCM Diagnostics 的几秒断联可能被 15s 轮询漏掉。
4. OriginOS 自启、关联启动、后台高耗电、最近任务锁定只能手动页面确认；隐藏最近任务卡片可能被 ROM 禁止，不能误称隐藏进程。
5. 应用 stopped 修复（\`cmd package unstop\`）、心跳广播及 90 秒巡检在 ADB Shell 与 Root 的实际权限区别。
6. GitHub Release 首次发布、应用内下载、SHA256/签名/包名/版本回读和覆盖升级；目前 **没有已发布 Release**。
7. GitHub Actions 的静态检查不等于 UI 自动化测试。界面样式和状态栏空间仍需手机截图确认。

## 6. 下一步严格顺序

1. **当前正在做**：KSU 追平增量、更新页面旧 Android 兼容性均已通过 [APK Actions #44141173241](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44141173241)（alpha.32，固定签名验签成功）。已完成 **mDNS 失败时通知栏输入“端口:配对码”**兜底且 [APK Actions #44141729186](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44141729186) 编译/签名通过。之后才提供第一个可操作的模块化 APK 实机验收步骤。
2. **只有新增 Actions 全部通过、功能代码入口完整后**，再提供安装测试版和一套最小验证步骤；先测试授权/模块导航，随后后台状态/守护，不要让用户在旧版浪费时间。
3. 发现实机问题就针对性修复并更新这里；设备确认可覆盖升级后，再人工发布第一个 GitHub prerelease，验证 APP 在线升级。
4. APK 稳定后双线回移 KernelSU；保持独立编译和版本记录。

**每次提交同步 \`docs/PRODUCT_PLAN.md\` 和本文件。** 不为新需求重新移除既有功能，不转 Work，不要求用户重新生成密钥。日志不得上传六位配对码、签名私钥、密码或完整敏感通知内容。

## 7.1 最终测试门槛与试用范围

- **源码模块已齐**：概览、授权、FCM、应用守护、后台保活、诊断、设置和 Release 更新均有真实实现；Shizuku 式通知栏配对和正常 Android FCM Tile 已存在。
- **云端阶段证据**：APK alpha.29、alpha.30、alpha.31 的源码编译及签名均通过；最后兼容性微调仍需单独 Actions 通过才作为最新版本推荐。
- **待实机的不能在 CI 验证**：OriginOS mDNS/通知栏配对、后台保活、Root/ADB 读取 GMS Socket、运行态 UI 截图及在线覆盖升级。由于无连接的真机，不能宣称“配对已成功”或“永不被杀”。
- **测试顺序**：① 看首页布局及页面导航，② 系统无线调试界面下拉通知输入配对码并验证 Shell，③ 开启 FCM 监控查最新样本，④ 守护名单/后台权限/任务隐藏/磁贴，⑤ 锁屏与 Wi-Fi 切换对照 Google Diagnostics，⑥ 正式 Release 发布后覆盖升级。

## 7.2 无需切回 APK 的配对兜底（已通过 CI，待实机）

- 系统无线调试页面如果 mDNS 自动发现到端口，通知栏只输入六位码。
- 如果 OriginOS 屏蔽 mDNS，通知栏仍可以输入 `37123:123456`（实际配对端口:六位码），不必回到 BerryFCM 应用输入端口，保持在系统配对页面即可。
- 不记录或保存配对码，输入来自 Android `RemoteInput` 的 mutable PendingIntent；PairingService 仅连接本机配对地址。
- **代码/签名已通过** [APK Actions #44141729186](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44141729186)，产物 `BerryFCM-Guardian-v0.1.0-alpha.33`；Android/OriginOS 通知栏 RemoteInput 真实呈现仍需真机验收。

## 7.3 最后一轮界面外观修正（正在提交，待 CI）

- 深色模式采用完整 Android Material Dark 系统控件主题 `AppThemeDark`，而非仅改变文本/卡片颜色；修改 `Ui.java` 和 `styles.xml`。
- 首页返回时重新读取 Root/ADB 模式与配对状态，消除静态授权卡片的旧状态；修改 `MainActivity.java`。
- 扩展 `tests/apk-module-smoke.sh`，校验深色原生主题存在；变更提交并编译后再将对应 Actions Run/Artifact 写回。
- 这不会修改包名、签名证书、GitHub Secrets 或 KernelSU 模块。**所有 APK 运行效果仍需要用户在目标机验证**。

## 7.4 极简启动图标（本次改动，待构建）

用户明确反馈现有图标过度装饰。新版采用 Android 自适应图标：纯蓝背景、白色两条信号弧线与一个圆点，无渐变、阴影、叠层、文字；附 Android 13+ 单色主题图标。图标由 XML Vector Drawable 源码实现，分辨率无关，避免图片尺寸失真。原旧 WebP 图标资源清理。Manifest 中圆形图标和标准图标使用同一个自适应资源。

**当前功能状态**：APK 八个模块已接入，最近一次 UI 主题版 [Actions #44142556439](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44142556439) 已成功，固定签名 Artifact `BerryFCM-Guardian-v0.1.0-alpha.34` 已上传；此图标改动需要新的 GitHub Actions 构建/签名验证。尚未开展目标 OriginOS 实机验证，不发布 GitHub Release。

## 8. 按用户图片四条代码原则的审查（2026-11-18）

基于当前 GitHub main 代码审查，结论见 [PRODUCT_PLAN.md §14](PRODUCT_PLAN.md)：

- 确认真实问题：`GuardOps.command` 有无需求依据的**最多 10 个应用**截断，排序后 GMS 也可能漏巡检；删除限制，并通过 `tests/GuardOpsSmoke.java` 检查 25 个守护目标 + GMS 全覆盖。
- 去掉 `FcmMonitorService` 三处 `catch(Throwable)`，保留真正的 I/O、Shell、系统异常捕获（`Exception`）。
- 不动下载安装的包名/版本/签名安全验证、不动 ADB 配对码与端口入口验证、不动策略回读与自有白名单归属校验；它们是必要边界。
- 可能的 ADB 共享连接互相干扰、输出上限，**未实机复现，不为理论风险增加新会话层**；列入后续实机检查。

**状态：已通过 [APK Actions #44143876578](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44143876578)：守护名单回归测试、Gradle Debug/Release、固定签名、apksigner 及上传全部成功，产物 `BerryFCM-Guardian-v0.1.0-alpha.36`。** 这不是手机实机验收。下一步继续确认新 UI 和 OriginOS ADB 通知栏配对，不要求用户测试旧版。


## 9. 2026-11-18 后续版本：OriginOS 真实报错、UI 与升级兼容

- 用户新截图：原无线配对报 `Read error: ssl=... RSA routines:OPENSSL_internal:internal error`；首页授权状态和 FCM 展示顺序错误，授权页纵向展示四种模式的全部表单且验证按钮在配对之前。
- 修复基于源码的高概率 TLSv1.3/RSA-PSS 不兼容：新 AndroidKeyStore RSA 身份 `berry_fcm_adb_identity_v3` 同时允许 PKCS1、PSS，按 Google Conscrypt #718 补充 DIGEST_NONE 和 ENCRYPTION_PADDING_NONE；保留旧 alias；**新身份需要重新进行系统无线配对**。暂未实机验证不宣称修复成功。
- UI：授权卡先行、Shell 状态新鲜度/错误、无权限时历史数据不误报；授权方式横向单选、只显示所选操作，USB 为说明非 Shell 模式；自动配对后通过 `id` 验证 uid；重要功能按钮无授权时引导授权。底部导航和功能行引入 Google Material Icons（Apache-2.0）；启动器由 Wi-Fi 弧线换成 FCM 消息通知图形。
- 确认了库与监控共用 ADB 会话的冲突：Shell wrapper 不再擅自断开共享会话，静态/无线会话明确区分；服务真正执行 Shell 后更新验证时间。
- 应用显示名及新 APK 文件名为 `BerryFCM`，包名 `top.zesun.berryfcm` 和固定证书保持不变。为使旧 alpha.36 内置更新器仍能在线检测，**首个新 GitHub prerelease 必须同时上传旧名称兼容 APK 资产和新短名称 APK 资产**（二者相同签名内容）；本轮 Actions 工作流已做准备。旧版更新器只识别旧名称是有源码证据的限制。
- **发布约束**：普通 push 产生 Actions Artifact；不会自动成为 Release。必须在 CI 完成且得到真实设备准入后手动发起 `publish_release=true` 的 workflow_dispatch。用户现在没有 Release 可供在线更新；首版正式发布前仍需从 Actions 手动安装一次或通过首次发布的旧名称资产更新。
- 本轮只通过 GitHub 修改仓库与 Actions 验证，不改用户电脑 C 盘。APK 真机 TLS、OriginOS mDNS、通知栏行为、锁屏后台、旧版覆盖安装尚待逐项核实。

**TLS 二次复核**：检查 Shizuku `AdbKey.kt` / `AdbPairingClient.kt`，确认上游优先以软件 RSA + AndroidKeyStore AES-GCM 保存密钥，避免 TLS 原生调用与硬件 RSA 不兼容。查到 [Google Conscrypt #718](https://github.com/google/conscrypt/issues/718) 中相同的 OpenSSL_internal RSA 错误与已证实的 `ENCRYPTION_PADDING_NONE` 补丁，因此在前述 PSS 修复外增补 `DIGEST_NONE` 与 `ENCRYPTION_PADDING_NONE`，密钥升级至 `berry_fcm_adb_identity_v3`，以确保旧不兼容密钥不复用。此变更待下一轮 Actions 与手机配对实测；如失败再评估软件 RSA，而不是盲目清理系统所有授权。

## 10. 2026-11-18 最新编译证据与状态新鲜度

- [APK Actions #44151060176](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44151060176)：alpha.37 首轮 UI/图标/新名字与签名 APK 编译、模块和 FCM 模拟测试全部成功，Artifact 已上传。
- [APK Actions #44151785615](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44151785615)：alpha.38 补齐 Google Conscrypt #718 所需密钥参数后，模块测试、编译、固定签名及 APK 上传全部成功。
- 新增 UI 错误摘要长度限制，技术细节仍在监控错误/诊断保留。Shell 验证记录采用 `currentTimeMillis` 与 `SystemClock.elapsedRealtime` 双时钟：可检测突然改时钟或设备重启后旧记录过期，避免只靠持久化时间误判。
- 下一次源码提交后仍必须重新验证 Actions。**两个 CI 成功均不是 Android 17/OriginOS 的实际 TLS 配对成功证据**。

## 11. 2026-11-18 最终 alpha.39 CI 结果

- **成功**：[Actions #44152371697](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44152371697) / 源码 [299539cd](https://github.com/jarod360/Berry-FCM-OS7/commit/299539cd25983ef2fa221ab78dc6db0309bdc64b)。
- 所有门槛通过：FCM 模拟监控、APK 模块与权限检查、Java/Android Debug 编译、固定签名 Release 编译、apksigner、Artifact 上传。签名 Artifact **`BerryFCM-v0.1.0-alpha.39`**，不是正式 Release；GitHub Releases 当前仍为空。
- 本版包含 TLS AndroidKeyStore v3 密钥参数、需要用户首次重新配对；首页授权和错误摘要、按权限类型切换的独立操作页、模块图标与新 FCM 消息通知图标、短桌面/文件名、旧版更新器兼容旧资产名称。
- **下一步真机首要验证**：在“无线调试”系统页面保持配对码可见，在 BerryFCM 通知栏 RemoteInput 提交六位码，返回后查看是否 `uid=2000(shell)`。若仍有 TLS 错误，检查原生 Conscrypt 私钥调用；按 [Shizuku](https://github.com/RikkaApps/Shizuku) 的软件 RSA + AndroidKeyStore AES-GCM 路线备选，不再改 APK 签名。其后测试 GMS Socket 读取、锁屏和服务恢复。
- **在线升级门槛**：已有 alpha.36 只有识别旧文件名的内置更新器，因此本仓库的首次 `publish_release=true` 手动构建将同时上传新短名称和旧兼容名称资产，确保用户可以从旧版在 APP 内升级；发布前必须先确认测试接受该 prerelease 机制。普通 Actions push 不等于 Release。
- 用户本机所有新开发资料如果落盘只允许 `D:\\Codex`；此次全部通过云端 GitHub 仓库和 Actions 进行，没有触及用户 C 盘。

## 12. alpha.39 后续源码复核与 CI 待验收

- **代码问题（已验证原因）**：`FcmMonitorService` 的 `adbConnected` 可能因 UI 模式切换/共享连接复用而指向旧授权方式；`AdbPairingService` 返回 `START_REDELIVER_INTENT` 对一次性通知栏配对码不合适。两者不是新手机实测结果，而是可由源码路径直接复核。
- **修复**：每次后台 Shell 执行先通过共享 `AdbConnectionManager` 确定无线 TLS 或静态 TCP 模式，避免私有布尔缓存；服务结束时不抢占断开 UI 共用会话。配对服务所有分支改用 `START_NOT_STICKY`，null Intent 不重新开始配对。开启新配对时使旧 Shell 验证记录失效。
- **视觉与命名**：系统配对通知 `ic_bf_auth`，FCM 前台通知、系统快捷磁贴和添加请求 `ic_bf_fcm`。不更改 APK 显示名 BerryFCM、不更新安装签名或包名。
- **需要确认**：GitHub Actions 新一轮模块测试/Gradle/签名结果；真机无线 ADB 配对 uid、切换授权方式后检查、后台监控是否持续记录、在线更新从正式 GitHub prerelease 是否可用。仅 CI 完成不能声称上述实机测试通过。
- **发布策略**：仍只有 Actions 测试 Artifact，尚无已确认可用的 GitHub Release；保留旧名称兼容资产以便未来启用应用内更新，正式发布必须显式批准并满足实机验收。

## 13. alpha.40 固定签名构建验证结果

- **基线提交**：[f587b60](https://github.com/jarod360/Berry-FCM-OS7/commit/f587b601b7aa4b94db6da19e5d806233bf602def)。
- **APK Actions #44196211389**：[查看构建](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44196211389)，七项关键步骤均成功：FCM 模拟测试、模块与权限检查、源码编译、固定签名证书准备、Release 编译、apksigner 验签、Artifact 上传。
- **测试包**：`BerryFCM-v0.1.0-alpha.40`，Artifact id `14379855865`，ZIP 大小 7,357,296 字节。签名基线、`top.zesun.berryfcm` 包名和用户配置保持不变，可走覆盖安装流程，但目标 ROM 行为未验证。
- **发布状态**：再次核对 GitHub Releases 列表为空。为遵循已确认的真机验收门槛，本轮**未执行** `publish_release=true`；当前旧版本仍不能从 App 内在线找到本次 Actions 测试 Artifact。正式 prerelease 发布时工作流会携带短/旧两种文件名以供过渡。
- **最小真机验证**：首次打开检查授权卡和横向模式切换；无线调试系统页面下拉通知输入六位码；核对是否报告 `uid=2000(shell)`；再启用 FCM 监控并核对实际 Socket 证据。若新的 RSA/TLS 失败仍复现，保留原始错误与对应动作，优先审查 libadb-android/Conscrypt 的硬件 KeyStore 私钥路径，必要时参考 Shizuku 软件 RSA+AndroidKeyStore AES，不无依据重建 APK 签名。


## 14. 按产品计划核对整体进度与本轮新增功能

- 截至上一次已验签构建为 APK `alpha.40`：[Actions #44196211389](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44196211389)，FCM 模拟、模块结构检查、Gradle、固定签名及 Artifact 均通过；源码基线为 `f587b60`，后续只更新过文档。
- **源码完成度估算约 75%**：七大 APK 页面及 K01–K09 多数有功能代码，但距离产品完成还有至少四类未闭环：OriginOS 真实授权/FCM UID 可见性；后台权限逐项回读与失败解释；首次安全 Release 在线覆盖升级；实测稳定后回移 KernelSU。不把源码覆盖率理解为实机通过率。
- 用户明确由其负责实机验证，开发端继续独立推进未阻塞模块。不要每修一项都停下要求手机截图。
- **本次修复**：`DiagnosticsActivity` 的三端口 TCP 基础连通性不再调用 Root/ADB Shell，直接以 Java Socket 连 `mtalk.google.com:5228/5229/5230`；保留 GMS 策略/UID 等特权诊断在 Shell 通道。运行结果不是推送送达证明。
- **本次修复**：`BackgroundSettings.optimize(context,shell)` 先读并记录可识别的 Doze 与两个 AppOps 原值，执行后复查；新增 `restoreSelf` 与“撤销本版 BerryFCM 添加的后台策略”。禁止撤销未持有所有权的旧/外部设置，旧版未记录原值的变更不能凭猜测还原；权限不可读即不盲写。保活页面标准状态增加通知授权与 Root/ADB 近期验证，并明确厂商私有开关需手工确认。
- **后续唯一开发优先级**：继续核对应用守护/后台 UI 的逐项状态及错误反馈；待 CI 构建成功后记录 Run、Artifact 和 commit。不要擅自创建 GitHub Release；首次 Release 必须保留旧文件名兼容包。

## 15. alpha.41 编译验签通过与后续入口整理

- [Actions #44197295228](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44197295228) / commit `a8a351e`：`BerryFCM-v0.1.0-alpha.41` Artifact 已上传（ID `14379252792`），六项关键门槛：FCM Shell 模拟、模块检查、APK Java/Android 编译、固定签名 Release 编译、apksigner、上传均成功。仅验证 CI，不代表 OriginOS 实测通过。
- 在此基础上继续修复 OriginOS 自启动和关联启动按钮重复指向同一 Activity 的误导行为；新版本以一个入口和明确说明替代重复入口。仍保持与 Shizuku/GKD/Traccar 等开源项目交互取舍一致，不捏造 ROM 私有 Activity。
- 不产生 GitHub Release，等待用户自行实机验收并确认进入发布阶段。

## 16. 当前已签名 APK：alpha.42（本轮最终构建）

- APK 源码 commit：[879b5db](https://github.com/jarod360/Berry-FCM-OS7/commit/879b5db4d2ae239e376eeeb418953392971a2a1d)；固定签名构建 [Actions #44197684568](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44197684568) 全部成功。
- 测试 Artifact：`BerryFCM-v0.1.0-alpha.42`，Artifact ID `14380091886`，压缩文件大小 7,357,687 字节。Shell 监测模拟、模块测试、Java/Android 编译、固定证书准备、Release 构建、签名验证、上传均通过。
- 本轮相较 alpha.40：原生 APP 无 Root/ADB 的 mtalk 三端口 TCP 检测；BerryFCM 自身 Doze 与后台 AppOps 更改先记录原状态、回读、可撤销；后台页面增加通知权限和 Shell 新鲜度提示；修正 OriginOS 自启动/关联启动重复跳页的误导。
- **未验收**：OriginOS 真机 TLS 配对、Shell UID Socket 权限、后台过夜/开机自动恢复、原始 AppOps 命令厂商兼容、完整 Release 在线覆盖升级；不以 CI 成功代替。
- 未执行正式 Release；用户负责真机验证，开发继续按第 19 节优先级推进。未经实测不要回移不确定的 Shell 规则到 KernelSU。

## 17. 2026-11-18 集中 UI/授权/守护改版交接

- **核心纠错**：旧 `shellRecentlyVerified()` 的 120 秒 TTL 只是短时 Shell 成功证据，不能作为“无线 ADB 是否配对过”的依据；用户已成功配对后不再反复要求手动授权/连接。持久记录 `adb_paired`，旧版配对成功文本兼容；配对成功立刻启用并启动 FCM 监控，UID/采样由后台自动回读、重试，不以配对成功冒充实际已采样。
- **配对流程**：主按钮“开始配对并打开无线调试”同时启动前台配对通知、mDNS 发现与系统无线调试界面；系统直达组件可能被 OriginOS 隐藏，按 Shizuku 方案回退到带无线选项提示的开发者选项。六位码只通过通知栏提交；重配操作在“配对已完成”状态下折叠隐藏。
- **主页**：FCM 状态第一、服务开关与最近采样证据在主屏；权限卡仅首次未配对或明确采样错误时出现。未采样首次显示尝试中，不再静态展示空旧快照误导。
- **守护页面**：已选目标含 GMS 固定显示名称/图标；列表候选只在打开选择器时才加载，已选置于列表外，勾选后立刻进入已选区；系统应用手动开启选项才显示，且对系统候选过滤非普通 UID、未启用/未安装、持久进程、无 Launcher 入口；最终能否 unstop 仍由实际回读决定。
- **设计**：参考 Shizuku/GKD/Hail/Shelter 的状态优先、渐进披露和系统应用筛选；仅修改原生 Android Java UI，不切换 Compose；桌面自适应图标更新成原创的盾牌+心跳电路、通知/导航一致。
- **CI 使用约束**：本次各模块 UI/后端与回归测试先全部暂存 GitHub blobs，最后只发布一个 main 提交，触发一次 Actions；不产生中间测试版本、不自动发布 GitHub Release。CI 通过后才确认构建版本。
- **未实测**：OriginOS 私有无线调试入口是否直达、系统是否禁止通知/新 FGS、GMS Socket 对 uid=2000 可见性、完整长期保活以及旧版本直接覆盖安装。实机验证由用户负责。

## 2026-11-18 实机纠错：GMS MCS 原生状态优先（未合并、未编译）

alpha.43 的用户截图证明 TCP Socket 观测不能代表 FCM MCS 应用层状态。Google FCM Diagnostics 在 Wi-Fi 无 GFW 限制的环境下显示 Connecting、alt7-mtalk.google.com:5228、Time disconnected 55:15、ERR_IO_RST_HB；此前约 06:46 起长时间重连失败。后续 08:05 起 Wi-Fi/Cell 交替是用户出门造成的网络变化，不能混入之前的稳定网络异常分析。心跳调度延迟在截图中为 68～143 秒量级，仅为诊断线索，不确定根因。

用户在 Termux Root 下验证了 `dumpsys -t 5 activity service com.google.android.gms/.gcm.GcmService`：真实返回 `connected=mtalk.google.com/... ,port=5228`（实际逗号之前无空格）、`connectTime=03:22/00:00` 以及历史 Close err、Connecting 事件。因此主状态改读 GMS MCS 服务当前块，参考 [fcm-keep-alive](https://github.com/AndyYuenOk/fcm-keep-alive) 的 dumpsys 入口及公开旧版 GMS 字段结构。连接、重连、pending 未连接、未知区分；TCP ESTAB 只能作为不可读取 GMS 时的辅助证据，不能升级为已连接。原生时长以快照为准；当前状态过期或失败时不继续外推。

仅提取获准的状态字段和 MCS 连接关闭、成功、失败、WiFi/Cell 尝试、Heartbeat alarm delay 等事件，不持久化完整 dumpsys/DeviceID/消息会计/应用数据。事件按原始时间戳和内容去重，保留最近 600 条；关闭事件数不等同于整体独立断联次数。原来 TCP 统计的文件保留，使用新 mcs-* 文件避免混算。自动重连以 GMS 原生未连接状态及原生时长为主，继续遵守间隔和 GMS stopped 回读；不因单次网络切换立即发广播，不自动改网络或强杀 GMS。

APK 新增独立原生状态模拟回归脚本：已登录、TCP 已建立但 MCS Connecting、pending、旧历史不可当作当前连接、权限拒绝、重复历史、限频重连。KernelSU 原算法及测试保持不变，等待 APK 验收后迁移。当前只在开发分支暂存，不触发 main 的 CI，不发布 Release。

尚未验证：目标设备 ADB uid=2000 是否同样允许读取 GcmService（现有证据为 Root）；GMS ROM 版本差异、原生历史缓冲限制、休眠中实际恢复行为。后续还需执行脚本回归及统一 APK 构建。本次不把根因推测标为结论。

### 原生 MCS 恢复机制与 ADB 命令执行（开发分支，2026-11-18）

源码实现提交：[3e43c1a](https://github.com/jarod360/Berry-FCM-OS7/commit/3e43c1a2b39947b93b63f5748753ff0e7d809abc)，仍位于 `dev/native-fcm-state`，未合并 main，未构建 APK 或 KernelSU 安装包。

- 原生 MCS 状态为唯一在线判据；区分 `permission_denied`、`timeout`、`service_unavailable`、`gms_stopped`、`empty` 等具体读取异常。部分 dumpsys 超时不接受为当前在线证据。
- 默认允许自动恢复（可单独关闭而继续监测）。应用默认网络变化后观察 45 秒，无活动网络或网络信息不可读时暂停自动干预；应用默认网络只是保守门槛，不证明 GMS 具体路由。原生未连接达到 120 秒、持续观测至少 15 秒后才请求 GCM_RECONNECT；连续重试间隔为 5、10、15 分钟，上限 15 分钟，恢复后清除连续重试级别。手动请求也先读取原生状态并作 60 秒防重复限制。
- 广播退出码及拒绝/异常文本共同判断请求是否得到提交确认；只有后续原生状态恢复才记录观察到恢复，不能证明广播造成恢复。
- ADB 命令改为直接命令流、随机完成标记、45 秒等待上限及取消处理，规避交互 Shell 回显、EOF 时序与无限阻塞；保留调用方原有结果解析约定。脚本安装先写临时文件并 `sh -n`，成功后替换并校验安装完成标记；合并重复采样和重连请求。
- 首页/监控页显示原生读取原因、实际状态、限频策略；原生事件和 BerryFCM 恢复/采样事件分别保存、显示。诊断分享包含两类事件，策略只读检查补充当前 Doze 深/浅状态及 GMS 后台 AppOps。
- 边界：不强杀 GMS、不修改 DNS/代理/路由、不擅自改变权限或电池策略；不新增运行权限。GMS 真实恢复取决于设备和系统，禁止把 CI 模拟当成设备实测。
- **专项回归结果**：[Native FCM shell verification #44207074830](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44207074830) 全部成功，约 11 秒；实际测试基于该开发源码提交加独立验证工作流。检查 APK Shell 语法、原生状态与历史去重、网络等待、自动恢复关闭、连续重试、权限/超时、手动重连保护，并执行既有 KernelSU 脚本语法与生命周期测试。未执行 Gradle、签名、APK 或 KSU 打包，Java/Android 编译和实机验收仍待下一批集中构建。
- 下一阶段优先核验目标机 adb shell uid=2000 的 GMS dump 权限、真实 GCM_RECONNECT 效果和长时间休眠后采样连续性。只有有证据再考虑 OriginOS 私有策略，不凭心跳延迟直接认定根因。

### 监控后台连续性与连接切换修正（2026-11-18）

本批次继续参考 Shizuku 的本机 ADB mDNS 发现、Termux 的 wake lock 使用方式。不同于 Termux 持续唤醒方案，BerryFCM 仅在实际采样运行期间使用超时上限 90 秒的 PARTIAL_WAKE_LOCK，并在 finally 释放；新增正常权限 WAKE_LOCK，不持有常驻唤醒锁、不请求精确闹钟、不保证系统深睡期间 15 秒必然执行。

- `FcmMonitorService` 记录每次服务运行 session、连接配置 key、单调时间采样锚点。旧 session、换模式/静态端点、超过 90 秒等情况下，不把历史快照当当前连接。开关偏好与实际运行状态分离；首页、监控、后台设置、磁贴使用实际服务状态。
- 已启用任务在用户重新打开 APP 且服务未运行/采样过期时请求恢复；运行中的服务注册默认网络变化、屏幕唤醒/解锁、退出 device idle 的事件触发，合并重复检查，onDestroy 注销。前台服务按系统 START_STICKY 及已有开机/更新接收器恢复；不能绕过用户强行停止或厂商限制。
- 采样/连接失败后 15/30/60/120 秒退避；手动采样和网络恢复触发可提前检查。实际原生 FCM 自动恢复仍遵守前一批的 45 秒网络稳定、120 秒断联及 5/10/15 分钟限频策略。
- Root Shell 统一使用有界进程、45 秒超时、身份检查、输出上限与临时文件清理。ADB 保留已配对 v3 密钥；已配对的无线调试失败不自动重新配对，传统 TCP 首次授权仍允许正常系统公钥确认。
- 授权标签仅浏览候选。Root/TCP 或已配对无线候选须实际验证通过才提交新连接配置，失败保留旧设置。手动操作与监控的 ADB 连接+命令按共享 manager 串行，避免切换时命令误用其他 transport。
- Java/Android 编译、真机休眠与广播效果尚待验证。本批与此前 native MCS 检测和恢复机制合并为一轮 APK 构建；不发布 Release，不更新 KernelSU。

### alpha.44 集中构建与后续 GMS 兼容性/运行环境诊断

- alpha.44 的源码基线为 `deba445363de958fb10e652e88b1b3f06decdc5f`。独立构建分支 `build/native-fcm-batch` 的提交 `4bbc19f` 仅在该分支增加 APK 构建触发条件，未更新 main；[Actions #44208154338](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44208154338) 已成功。固定签名 Artifact `BerryFCM-v0.1.0-alpha.44`（ID 14384467571，压缩文件 7374465 字节）；原生 Shell 回归、模块检查、Android 编译、固定签名、APK 验签、上传均通过。无 Release、无 KSU 打包。真机验证尚未完成，不宣布实际恢复成功。
- 构建期间继续推进 `dev/native-fcm-state`：提交 [1543b79](https://github.com/jarod360/Berry-FCM-OS7/commit/1543b79e7ae37d5935f021503c5696a2ac807723) 支持 GMS 标题存在差异时，通过精确当前态字段与有效 connectTime/disconnectTime 或 streamId 的相互佐证进行解析。无标题且只有孤立的 connected= 字段不视为可靠；拒绝和当前状态冲突的时长、历史列表中的伪当前状态以及不完整 dump。增加对应模拟测试与服务会话、唤醒锁、授权切换的静态断言。[仅 Shell/模块检查 #44208517040](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44208517040) 已全部通过，不打包 APK。
- 再次继续开发：在原有采样结果内记录本应用默认网络 transport（WiFi/Cell/VPN/Ethernet）、Android 网络验证标记、屏幕状态、Doze 及省电模式、GMS Doze 白名单读取结果；变化时写入最近 80 条环境事件，在监控页高级区域和分享诊断中展示。只读取公开 Android 状态、不记录 SSID、账户、地址等附加标识，不新增网络探测。网络 capability 中 transport 类型变化也触发合并检查。应用默认网络不代表 GMS UID 实际路由、Android validated 也不代表 FCM 可达。采样环境只是相关线索，不证明断联原因。
- **版本边界**：最后两个开发批次不包含于 alpha.44。GMS 标题兼容性有 Shell/模块回归证据；新加入的环境事件 Java 代码仍需下一次集中 Android 编译和实机测试。保持独立开发分支、不逐项重打包；未迁移到 KSU。

### 无线调试常驻通知与独立 Shell 服务（下一批开发）

用户实机反馈：BerryFCM 启用后 Android 系统一直显示“已连接到无线调试”。原因是当前内置 ADB 监控在执行完成后仍然保持 TLS transport，并不是 FCM 通知本身。不能将关闭系统通知或取消配对当作修复。

- 内置无线 ADB / ADB TCP 的配对与执行连接分开；`AdbConnectionManager.executeOnce` 串行完成连接、实时校验 uid=2000、执行和 finally 断开。配对本身也在 finally 关闭连接，保留原 AndroidKeyStore v3 身份。监控、手动策略操作、授权验证共用此入口；没有删除或重新生成已配对密钥。直接 ADB 模式仍需在采样时连接，因此**可能短暂显示系统无线调试通知**，不能声称彻底无通知。
- 增加可选的 [Shizuku 官方 UserService](https://github.com/RikkaApps/Shizuku-API) 实现，固定 SDK 13.1.5，需要用户已安装并启动 Shizuku v13+（或兼容 Sui）并明确授权 BerryFCM。使用官方受权限保护的 ShizukuProvider、Binder AIDL 和进程级 UserService，不开放任意 TCP/HTTP Shell 服务；服务端校验调用者就是 BerryFCM 应用 UID，命令 45 秒超时、输出 200 KB 上限，并清理临时文件。不使用已准备废弃的 newProcess API。
- 授权页新增 Shizuku 选项，确认实际 uid=0/2000 后才切换运行方式；后台采样、守护与策略通过同一 UserService；原生 Root、无线 ADB、ADB TCP 保留。Shizuku 服务未启动或权限撤销时显示真实异常，不偷偷切换权限方式。Root 模式仍是已 Root 手机无 ADB 通知的最直接路径。
- **边界**：Shizuku 选项复用已安装的独立权限服务，并非已经在 BerryFCM 内独立实现 Shizuku 服务端。无外部服务的内置无线 ADB 仍是短连接；要进一步实现首次配对后完全脱离 ADB 的自包含 daemon，需要单独验证 Android app_process / Binder 启动、授权与回收的兼容性。Shizuku 通过 ADB 启动时重启后也可能需重新启动服务，不能保证自行跨重启保持。
- 采用现有固定签名与 APK 包名；本次只更新开发分支和源码回归规则，不触发 APK 构建或发布。待下一批集中编译确认 AIDL、SDK 集成及实机通知行为。

### 2026-11-18：采用 GKD 同款 Priv Kit 独立服务（开发分支）

- 用户明确纠正：正常监控期间不能反复连接无线 ADB，即使每次执行后断开、短暂弹出系统通知，也不符合目标。
- 依据 [GKD 的依赖配置](https://github.com/gkd-kit/gkd/blob/main/gradle/libs.versions.toml) 与 [Priv Kit v0.20.0](https://github.com/priv-kit/priv-kit/tree/v0.20.0)，接入正式 Maven Central `io.github.priv-kit:priv-core:0.20.0`。不再自制 app_process 服务、不通过 socket 暴露执行接口。
- 保留原有 AndroidKeyStore v3 配对身份，通过现有 ADB executeOnce 启动 Priv Kit 正式 nativeStarterCommand，之后断开 ADB。等待真实 UID 2000 Binder，日常采样、守护、策略、手动命令及授权验证均经官方 startCommand/awaitResult；命令超时 45 秒，输出有界。禁止自动 fallback 到 ADB 短连接执行普通命令。
- 服务失效时先等待现有 Binder 回传。自动启动失败后不逐次采样重开 ADB；之前启动成功但服务随后死亡时，至少间隔 5 分钟才允许自动启动；显式启动及成功的新配对可恢复尝试。Binder 存活与配对保存是两个不同状态。重新启动服务不等于重新配对。系统重启/服务真的退出可能仍需要一次 ADB 启动，不能声称所有场景永远没有通知。
- 保留独立 Root、ADB TCP 和可选 Shizuku 路径；不要求安装 Shizuku。切换到其他方式后停止本项目的 Priv Kit 服务。
- 构建配置与上游匹配：compileSdk 37、AGP 9.4.1、Gradle 9.6.1、JDK 21；targetSdk 35、minSdk 26、applicationId 及固定签名保持不变。原生启动器兼容 Android 8/9 的提取式打包。通过 manifest 合并 remove 排除 WRITE_SECURE_SETTINGS，CI 检查最终 APK。
- 本批代码完成后仍需实际 Android 编译、依赖解析及真机验证，包括首次启动后 ADB 断开、关无线调试后 Binder 命令、网络切换、服务死亡、旧版本覆盖升级以及权限范围。不发布 Release；不迁移到 KSU。


### 独立服务状态显示
首页与监控页直接检查 UID 2000 Binder 是否存活。服务未运行时不会呈现历史 FCM 在线快照为实时状态；已配对用户只显示启动独立服务的入口，不要求重新授权。

构建记录：alpha.45（#44228012040）在 Android 工具安装阶段失败，尚未编译，旧的 `platforms;android-37` 包 ID 不存在。Flutter 的 SDK 配置和 Android API 37.0 工具要求确认正式包 ID 为 `platforms;android-37.0`。CI 已改为该包并固定 Build Tools 37.0.0；签名配置不变。

alpha.46（#44228259741）已通过 API 37.0 SDK 安装、依赖解析、原生脚本及模块回归；Java 编译仅报告可选 Shizuku BerryShellUserService.java 的隐藏 API `ServiceSpecificException` 不可见。更换为 Binder 支持传输的公开 `IllegalStateException`，不变更权限范围、配对密钥或 Priv Kit 运行路径。
### alpha.47 已构建成功；后续独立服务重连生命周期

- [alpha.47 #44228547705](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44228547705) 已完整成功：SDK 37.0、Android 编译、原生脚本与模块测试、合并权限清单检查、固定签名、验签及 Artifact 14394306272（8,158,195 字节 ZIP）。测试 APK 源码为 ccf9c9f，构建提交 23fc50c；开发分支随后修改的文档与本节生命周期改动不包含于这个包。未发布 Release，未更新 main/KSU。
- 参考 [GKD OwnerLifecycle](https://github.com/gkd-kit/gkd/blob/main/gkd-app/src/androidMain/kotlin/li/gkd/app/priv/PrivilegeOwnerLifecycle.kt) 与 Priv Kit v0.20.0 PrivilegeConfig：启动 APP 时初始化回传监听，设独立服务在 owner 死亡后的**被动**接续窗口为一小时。activeReconnectOnOwnerDeath=false，不使用特权服务主动拉起 APP，不承诺进程常驻。现有服务回传等待从 1.5 秒延至 5 秒。
- ADB 启动之前同步持久化单调时间、墙钟和 boot_count，避免应用进程被回收导致五分钟冷却失效；同一次系统启动优先单调时间，boot_count 不可读时采用保守时间判断。原 Binder 优先，失败仍禁止逐次命令回退；显式重新启动服务不受自动冷却限制，成功新配对可清除启动记录。
- 配对通知明确区分配对成功、请求启动监控、系统拒绝启动监控；不再把 startForegroundService 请求当成运行成功。保留配对身份，打开 APP 可恢复监控。
- 增加纯 Java 冷却测试覆盖首次启动、应用重启、系统重启、时钟变化及 boot_count 不可读。此批源码尚未进入 alpha.47；依旧按集中修改再编译的原则，先执行轻量专项回归。


独立服务诊断：现有分享日志增加 Binder UID/PID 与 APP PID、累计 ADB 启动尝试、最新启动结果和冷却剩余。只读现有信息，不触发 ADB、启动或采样；计数在实际尝试之前记录，不代表成功连接。用于验证普通采样是否仍依赖 ADB。
### 2026-11-18 alpha.47 真机：配对成功但独立服务未启动
用户截图确认 prefs 已显示已保存配对身份；连接授权却提示“未发现本机无线 ADB 服务”。此错误来自旧版 libadb 的 connectTls mDNS 发现路径，发生在 Priv Kit native starter 执行之前，并非已证实的密钥错误。尚不能据此认定 ROM 的具体 mDNS 故障原因。
- 保留原 AndroidKeyStore v3 身份，连接端口发现改用 GKD 同款 Priv Kit v0.20.0 的公开 createAdbManager(...).discoverConnectPort(15000)。只使用其发现功能，不切换到 Priv Kit 自己的 ADB 密钥。连接本机 loopback、校验 uid=2000、启动独立服务后 finally 关闭 ADB；不扫描 LAN 端口、不恢复逐次 ADB 采样。
- 新增连接端口（不是配对端口）一次性手动备用入口，使用无线调试主页所显示的端口；不永久缓存会变化的端口。从“打开无线调试并自动启动”返回设置后尝试一次启动，无需再次配对。无本地配对标记时可显式检查已有身份，真实 ADB 认证和 UID 验证成功后保存配对标记；新建密钥必须清除旧标记。不同应用自己的 ADB 密钥不能共享配对。
- 配对通知等待实际 Priv Kit 握手及 uid 回读成功才报告独立服务运行，并区分前台监控请求是否提交；后续启动失败保留已配对身份，停止 mDNS 回调覆盖配对状态和重复通知输入。候选连接失败不强制切换已有模式。
- 仍需 OriginOS 实测 SDK 37 现代 NSD 是否能发现本机连接端口、loopback 是否可达以及 native starter 回传；不保证仅凭源码或编译成功就能启动。若发现失败，先读取系统无线调试主页端口进行一次启动。

### 实机失败后的授权重构：先发现配对服务，再输入码

用户已重新配对三次，但 alpha.49 独立服务仍未启动。此前的 CI 仅验证编译与脚本等，不能作为真机成功记录。本轮完整使用 Priv Kit v0.20.0 官方 manager 的 discoverPairingPort、pair、checkPairing 与 Privilege.startAdb，同一设备名/密钥，不再借用旧 libadb 的无线 TLS 或外部启动方式；旧 libadb 仅保留显式静态 TCP。参考 priv-ui 的 PrivilegeUiAdbPairingActions.kt：6 秒发现，500ms 重试/端口监听，找到真实本机端口才允许通知输入六位码，关闭服务即收回输入；PairingGate 防止过期及重复回复。正常流程无需输入端口。新身份首次迁移确实需一次配对，不能继承旧标记。checkPairing 遇 UNPAIRED 清除历史，UNAVAILABLE/ERROR 显示待验证。Binder 与 UID 回读成功才开始监控；启动日志包含发现、认证及握手阶段。没有手机连接权限，不能宣布真机测试成功。本批只在开发分支提交，未打包。

### 2026-11-18 后续：授权状态及长时间 FCM 断开恢复
- 上次授权优先界面和 Priv Kit 自动配对地址修正已进入独立构建分支（e0f86f3e），尚未获得新 APK 的实际认证结果。此次保留启动异常的具体原因，授权页可展开并复制；快捷设置磁贴也检查真实 Binder / 授权状态。
- 用户提供 Google 原生 FCM Diagnostics：06:25、06:29、06:39 多次关闭后恢复，06:46:15 起再次断开，06:54:26 失败并切换备用服务器；07:41 显示 Connecting、alt7-mtalk.google.com:5228、断开 55:15、ERR_IO_RST_HB。心跳调度延迟约 68–143 秒。该证据只证明 GMS 原生连接异常，不证明 OriginOS、网络或 BerryFCM 单独为根因。
- 原轮询在超过 90 秒间隔后重置连续观察，深睡间歇唤醒可能始终错过 15 秒确认条件。长时间原生断开、网络稳定、自动恢复开启、达到冷却期限时，新增同一次唤醒内相隔 2 秒的第二次原生检查；第二次恢复、未知或端点/断开时长不符合连续性时不发送广播。保留 5/10/15 分钟冷却、禁止强杀 GMS、禁止修改 DNS 等边界。第三次及后续交替尝试定向 MCS_HEARTBEAT，属于未公开 GMS 接口，只有原生 Connected 可证明恢复，不保证推送送达。
- Binder 失效且已有配对、无线调试开启时，原启动失败标志不再永久阻断恢复；仍按持久化 5 分钟冷却限频，不在正常 Binder 命令中启动 ADB。不自动重新配对。
- 已增补模拟回归测试，尚待实际构建和真机验收。先验证 ADB、FCM 原生状态，再验证锁屏期间断开日志与恢复请求。尚不创建 Release。

### 当前阶段统一交接（与 PRODUCT_PLAN 最新章节同步）
- G0 完成，G1 主体实现，G2 授权 P0 阻断，G3 主体实现仍修复，G4 更新未闭环，G5 最新代码尚无完整 CI 证据，G6 已开始但未达到最终验收，G7 未回移。不能说只剩真机。详见 PRODUCT_PLAN.md 最新统一表。
- 新源码提交 [55434d1](https://github.com/jarod360/Berry-FCM-OS7/commit/55434d18785f62461656ccd59bb084561de0c467)：各入口统一实际授权条件；守护结果改为准确的强制停止语义，保存检查时间；后台策略读取必须成功并排除权限失败后才写入，Doze 使用完整包名匹配。回滚记录先于 GMS 策略变更写入。未新增权限，尚未确认新 CI。
- 上一独立构建提交 [8b42663](https://github.com/jarod360/Berry-FCM-OS7/commit/8b426632f40bf761bd4c437412e56868ea033d4e) 已推送；此交接更新时尚未取得该批完成结果。历史 alpha.47 已有签名/Artifact 证据，alpha.49 的实机失败由用户反馈记录，不能混同最新版成功证据。
- 下一动作：将本轮完整代码同步到 build/native-fcm-batch，核对实际工作流和最新 Artifact；继续解决编译/回归失败及非阻塞模块，之后才提供实测包。未获设备通过不发布 Release，不修改 main/KSU。

**构建分支推进记录（本轮最后核对）**：代码批次对应 [8ba62c0](https://github.com/jarod360/Berry-FCM-OS7/commit/8ba62c04652597da23a158d59fd1ad40da317039)，已推送 `build/native-fcm-batch`；该提交与开发代码基线 1c878df 仅存在构建 workflow 触发配置差异。已实际查询历史 [#44228547705](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44228547705)：build 成功、签名与验签成功、Artifact alpha.47（14394306272）未过期，发布任务跳过。当前新提交尚无可确认的完成结果，不能推荐旧 alpha.47 作为已修复的授权版本。此后开发分支只追加文档记录，不因此重复触发构建。


### 最新执行约束：停止碎片化 APK 构建，集中完成研发

用户明确要求整体代码与功能基本完成后再统一编译，不再每次修改少量代码就触发 APK 构建或要求反复安装。即日起只在 dev/native-fcm-state 集中提交完整逻辑、回归用例及双文档，不更新 build/native-fcm-batch，不合并 main，不发布 Release。开发阶段可做源码检查、独立逻辑回归；集中完成授权、FCM、守护、保活、诊断、更新相关代码审查与修复后，才进行一次完整 Gradle 编译、固定签名与制品验签。构建错误需要针对性处理，不将新测试包的数量当作研发进度。

本批源码 [835e945](https://github.com/jarod360/Berry-FCM-OS7/commit/835e9458919c2adadf3a31f07fd40e193e38cdb9)：复核 Priv Kit v0.20.0 官方启动文档及 Android 局域网权限文档（https://developer.android.com/privacy-and-security/local-network-permission）。当前 targetSdk=35，Android 17 的 ACCESS_LOCAL_NETWORK 强制运行时授权只适用于 targetSdk>=37，先不增加多余授权，不把这项变化判为现有故障根因。配对通知渠道禁用时明确跳转对应设置；自动发现失败约 15 秒后才提供通知栏端口:配对码的显式备用入口，正常仅输入六位码（手动端口仍受上游本机 loopback 支持限制）；防旧通知/重复回复，新增门控回归用例；保存实际启动日志到本地应用私有存储；Binder 延迟回传时首页恢复用户之前开启的任务。没有获得真机成功证据，不标为已解决 ADB。当前仅源码提交，未触发完整 APK 构建。下一步重点对照上游启动阶段、状态切换和真实失败诊断，继续非阻塞模块。此前已推送的构建分支保留，停发新增测试构建。


### 下拉快捷磁贴与前台通知（本轮集中开发）
- 用户指出未授权时下拉仍显示 BerryFCM。区分系统快捷磁贴、配对通知和监控前台服务通知。快捷磁贴组件默认禁用，仅授权成功后由用户在设置中主动添加，提供移除入口；系统管理磁贴位置，已主动添加的磁贴在临时失去授权时显示不可用。取消添加恢复之前的组件状态。去掉 active tile 模式以在打开快捷栏时刷新状态。
- 监控前台服务入口、系统重启/更新恢复及执行前均检查授权资格；首次配对交换、历史开关不足以启动。已实际验证过 UID 2000 的用户在无线调试已开且未被拒绝时保留有限自动恢复能力，通知明确暂未监控；没有授权/资格时停止服务并移除前台通知，保留用户的任务偏好。配对通知只在主动配对期间展示，成功或失败结果不属于监控。正常 monitor 通知显示原生 FCM 状态或检查中，不以历史采样冒充实时连接。Android 前台服务通知仍遵循系统规定。
- 参考 Android 官方 Quick Settings 指南：https://developer.android.com/develop/ui/views/quicksettings-tiles 。没有触发 APK 构建，待集中回归及统一编译。
**用户再次定案：**即使 ADB/Root/Shizuku 已授权、服务启动成功、FCM 正在监控，也不得自动添加或显示快捷磁贴。默认禁用磁贴组件；仅“设置 → 添加 FCM 快捷磁贴”的显式操作可启用，系统确认添加后才进入快捷栏。移除磁贴独立于后台监控、守护和恢复。系统要求的前台服务通知不等于磁贴，不能承诺由应用绕过系统通知规则。增加静态回归约束，禁止授权、监控、开机路径启用磁贴。未触发 APK 构建。

### 后台权限统一入口与状态回读（用户最新要求）
- 磁贴、通知、系统电池优化、OriginOS 自启动/关联启动/高耗电/最近任务锁定统一归入后台保活页面；设置页仅保留导航入口。磁贴默认关闭，主动添加后读取系统添加/移除回调；不随服务启动添加。监控通知类别和总体通知权限分别读取，返回页面重新刷新。标准 Android 电池豁免、后台限制用系统 API 回读；不能将 Android 未限制等同于 OriginOS 允许高耗电。
- 参考 Oolong (https://github.com/HuanCheng65/Oolong/blob/ba4b1a074781679240c03dd837eb4a9be8649f1b/app/src/main/java/oolong/client/utils/BackgroundSettings.kt) 的 On/Off/Unknown 和厂商设置跳转，Smart-Edge (https://github.com/Imtiaz-Official/Smart-Edge/blob/04cbca29b4776985b9e0eee84161d5c23ee1e89e/app/src/main/java/com/imi/smartedge/sidebar/panel/Extensions.kt) 的 Vivo 私有 AppOps 10002 候选。仅当 ROM 自身返回明确 autoStart 操作名才尝试只读模式，且标注厂商开关需实机核对，异常/未知不标为关闭。未发现经过 OriginOS 7 验证的关联启动、高耗电、最近任务锁定读取接口；当前逐项显示需系统确认，后续必须以目标 ROM 开关前后差分验证读回，不伪造布尔值，不申请无障碍。未触发 APK 编译。

### 授权管理与辅助后台权限的最终分工（覆盖前面页面布局说明）
用户明确：自启动、关联启动、允许后台高耗电、锁定后台等全部在授权管理给出点击跳转，返回后检查真实状态。它们仅辅助系统稳定性，不作为 ADB/Root/Shizuku 已授权后的监控/守护门槛；通知或快捷磁贴未开启也不得停任务，更不自动添加磁贴。后台保活页面只管理用户任务开关、运行状态、已有高级策略及授权管理导航。没有核心授权才禁止执行特权命令；无线调试关闭但现有 UID 2000 Binder 仍活着时继续运行。
- 授权页直接列出辅助权限和显示选项，返回时立即读取系统状态。自启动沿用 ROM 名称校验的 AppOps 候选，关联启动、高耗电、最近任务锁定仍需目标设备差分验证，不冒充已授权。参考 HelloDaemon、YCAppTool、Smart-Edge 的 Vivo 高耗电页面入口，以及 Legado 的 PurviewTabActivity 权限管理入口；全部按可打开性逐级降级，不声称厂商页面必然直达。最近任务在用户确认且具备现有核心权限后仅发送 APP_SWITCH，锁定由用户亲自操作；未授权时给手动操作提示。隐藏卡片和锁定是不同选项。
- 低干扰显示仅刷新现有前台通知，不再借由显示开关启动/停止监控；不变更任务开关。回归约束检查监控/授权资格/开机恢复不引用辅助权限，避免后续引入硬门槛。当前源码提交，不编译。后续须验证 OriginOS 7 的真实权限状态映射。

### 应用内在线升级（集中研发）
现有更新器读取 GitHub Releases（包括命名匹配的 prerelease），Actions Artifact 不属于发布源；此前确认的构建发布任务跳过。用户不应手动下载 APK 再寻找文件安装。本批改为点击“立即更新”后，由系统下载管理器下载、展示进度、在更新页可见时自动校验包名、版本、SHA256（Release 提供时）和固定签名，自动打开系统安装器；首次安装来源权限由用户授予，返回自动继续。下载中离开页面，返回继续；失败可重试，不静默安装、不卸载旧版、不引入新权限。参考 GKD UpdateStatus 的独立检查/下载/安装状态管理。发布仍以实机验收后允许的固定签名 Release 为准，未发布新版本之前无法在线获取该版本。当前仅源码修改，不触发 APK 构建；在线升级实际覆盖安装尚未验证。

## 集中开发最新唯一执行清单（覆盖旧阶段/发布说明）
用户要求汇总最近全部问题，集中解决，不再碎片编译。当前仍非单纯验收阶段。P0：真实自动 ADB 配对/发现、启动 UID2000 Binder、保留有效配对、失败日志、平时不连接 ADB；P1：原生 FCM 状态、断联/深睡恢复、守护与保活不依赖辅助权限；P1：授权管理中自启动/关联启动/高耗电/锁定/电池/通知/磁贴逐项真实回读及跳转，磁贴仅显式添加；P1：在线更新发现、应用内下载、签名与版本校验、覆盖安装。最终完成 APK 真机验收后再回移 KSU。
本轮实际修改：
- 检查无线和静态 ADB 的实际 id 输出后才保存模式，拒绝假授权；启动结果异常但已收到有效 Binder 时接续该 Binder，不重复开 ADB。旧错误提示在恢复时清除。此前自动发现、启动及配对失败仍须目标机器验证，不声明已经解决。
- 原厂框架线索来自 https://github.com/imwangwang/vivo-apps/blob/6aff38cfa6133250fc58a2fdc5f6452c676440aa/main/java/com/vivo/services/security/client/VivoPermissionType.java 与同目录 VivoPermissionManager/VivoPermissionInfo：通过现有 ROM 自身类型名 AUTO_START、getVPTypeId、getAppPermission(self)、getPermissionResult、GRANTED/DENIED 常量读取自启动；不硬编码私有 ID，不修改权限，隐藏接口拒绝时仍为未知。另参考 https://github.com/Lokside/vivo-guardian/blob/579030d4a6d413bfe5a80424fa16e1b92300661d/docs/TECHNICAL.md，OriginOS 7 的最近任务锁定涉及 UserLockedAppFilter/LockedAppManager，但没有公开已验证的读取接口。新增只读本 APP AppOps 诊断以便开关前后比对；关联启动/高耗电/后台锁定的真实自动回读仍待目标 ROM 证据，不能用通用 Android 状态或访问页面记录冒充。
- 应用内更新：开始查更新时清旧下载候选。发布工作流由原“再次编译并发布”改为人工选择已成功构建的 accepted_run_id，跳过 build，校验原运行来源/状态、从该运行下载同一固定签名 Artifact、验签/包名/版本号后创建对应源提交的 prerelease。无需为同一份 APK 重新编译，禁止自动发布。以后可明确选择通过完整 CI 的测试 prerelease 供应用内升级，稳定发布仍须验收；不发布当前未验证代码。旧包原来没有新 Release 因而找不到更新，不能假定新源码已经在用户手机生效。
- 集中验收顺序：本地/轻量静态与脚本回归（不生成 APK）；完整批次一次 CI；选通过的同一产物受控发布测试 prerelease；当前旧固定签名 APK 在线升级；首次配对、真实 UID/Binder、无线调试关闭后仍监控、系统撤销与服务死亡；自启动/关联/高耗电/锁定各自开关前后真实差分；磁贴和通知独立；锁屏/断网/重连及应用守护；回移 KSU 与最终发布。
本轮只更新 dev/native-fcm-state；不触发 APK 构建，不推 build 分支、不合并 main、不发布 Release。尚无最新版 Android 编译或真实手机通过证据。

### 集中测试包准入修正（2026-11-18）
用户同意自检到可验证时发布测试 APK，供现有版本应用内在线升级；不要求等所有真机功能验证后才发布测试 prerelease，不得当稳定正式版。检查原厂 Priv Kit v0.20.0 manifest 与 NSD 实现：无 NEARBY_WIFI_DEVICES 依赖，移除本项目额外的强制附近 Wi-Fi 权限请求（保留上游自己的标准声明，targetSdk35）。授权配对通知回复复用已在前台的服务，不以过期回复创建新的前台服务；结束提示 15 秒后消失，可点击授权页。首次成功自动监控，但已有明确关闭偏好不因重新授权被重置。厂商自启动读取转后台线程；辅助权限继续未知时据实显示。守护目标以每批最多5个执行，避免25个应用的最坏情况超45秒单命令超时，检查未安装的目标不执行 unstop。在实际容器 JDK 中执行仓库原始 PairingGateSmoke、LaunchCooldownSmoke、GuardOpsSmoke，通过并比对六个源文件 Git blob SHA；更新的守护分批用例随完整 CI 执行。此前累计静态匹配不是完整CI证据。待一次集中 SDK/Gradle/脚本/模块/固定签名/验签后，才以同一个通过产物发布测试 Release；主分支与KSU不改。厂商关联启动、高耗电、锁定回读尚未有证据，仍需真机协同核对。

### 集中自检及测试发布准入记录

- 2026-11-18 用户已明确授权自检通过后发布一份可在线升级的测试 prerelease；不修改 main、不提前回移 KSU。开发基线 [898905d](https://github.com/jarod360/Berry-FCM-OS7/commit/898905dc2d446c158f0f0bee6f04c8662acaedbc)。
- 实际 JDK 执行 PairingGateSmoke、LaunchCooldownSmoke 与原始及新增的 GuardOpsSmoke，均 PASS；源码/用例 Git blob SHA 与仓库逐一一致。新增分批守护 25 个目标 + GMS（6 批，每批至多5个、GMS仅一次）PASS。纠正已迁移到 AuthActivity 的磁贴图标静态断言。
- 唯一集中构建提交 [e84dbb3](https://github.com/jarod360/Berry-FCM-OS7/commit/e84dbb342344d50e4c9e71604e8e84f3ca3dd241) 已推送 `build/native-fcm-batch`，与开发基线仅 workflow 不同。该提交的明确 [publish-test] 标识及分支限制代表本次用户授权；只有原生 Shell 回归、模块检查、完整 Gradle 编译、合并权限检查、固定签名和 Artifact 上传全部通过，发布 job 才会下载这一运行的同一 APK，再验签和包名/版本号，创建对应 commit 的 GitHub prerelease（双兼容 APK 名称，非 latest 稳定版）。发布不重新编译；不通过任何关卡就不发布。
- 当前已核对分支更新成功，但未获取 CI 最终状态或 Release URL。不标记构建或发布成功。可通过 [Actions](https://github.com/jarod360/Berry-FCM-OS7/actions/workflows/build-apk.yml?query=branch%3Abuild%2Fnative-fcm-batch) 或提交状态 berryfcm/build、berryfcm/test-release 核对真实结果。原厂私有权限尚未验证的项由目标手机实测；无需等待稳定版发布才做测试升级。

### 2026-11-18 集中构建失败修复
- [Actions #44242562721](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44242562721)：SDK、原生 FCM 模拟以及完整 APK 模块/权限 scope 回归均实际通过；`compileDebugJavaWithJavac` 唯一报错 `PrivKitShell.java:92`，官方 `createAdbManager` 声明 checked `PrivilegeStartupException`，Java 包装方法遗漏 throws。已查明所有三处调用方已声明 throws Exception，直接向上透传原始异常供现有诊断，无额外捕获或授权逻辑变动。签名/发布未执行。只针对已确认的完整构建失败修正，仍以同一个通过产物自动发布用户已批准的测试 prerelease。

### alpha.54 制品发布修复
- [Actions #44245895574](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44245895574) 完整 build 成功：原生 FCM、模块检查、Debug/Release 编译、合并权限范围、固定证书、公钥签名验签、上传全部通过。制品 14401338560，BerryFCM-v0.1.0-alpha.54，已确认原始签名 `V2 Signer: certificate SHA-256 digest` 与固定指纹一致且 Number of signers=1。发布 job 下载原制品且 ZIP digest 正确，但脚本只匹配旧 Signer #1 输出导致校验失败，并非签名错误。
- 发布/晋升统一支持 Build Tools 37 的 V2 Signer 和历史 Signer #n 输出，继续要求单签名、精确固定指纹、包名和原版本号。仅允许 build/native-fcm-batch 的显式 `[promote-test:<run_id>]` 触发仅发布 job（跳过 build）；校验指定 run 原 build 成功和八项必要门槛，允许发布 job 自身失败的旧 run，下载其同一制品。此轮只晋升原 #44245895574 / alpha.54，不重复编译、不生成新 APK，不改签名或版本。实际发布状态待 Actions 确认。

### alpha.54 发布阻断已精确定位
- [仅晋升任务 #44247523166](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44247523166) 已实际跳过 build，原 #44245895574 的八个必需步骤核对、原制品下载、apksigner 签名验证（单签名且固定指纹）、aapt 包名 top.zesun.berryfcm / versionCode 54 / versionName 0.1.0-alpha.54 全部通过。唯一失败是 gh release create HTTP403 Resource not accessible by integration，未发布。
- GitHub 官方 REST Release 文档 https://docs.github.com/en/rest/releases/releases#create-a-release 明确指出：target_commitish 与默认分支存在 .github/workflows 差异时，需要 Workflows:write，GITHUB_TOKEN 无法获得该权限。当前独立构建分支确实有 workflow 差异；不能将 tag 指向错误提交、不能为绕过限制而合并 main。保留用户授权的原制品版本和提交。
- 发布步骤（仅 gh release create）支持仓库级 Actions secret BERRYFCM_RELEASE_TOKEN，用户自行配置仅限 Berry-FCM-OS7 的 fine-grained PAT，Contents:Read and write、Workflows:Read and write；无需透露 token，不改 APK 签名密钥。其他步骤仍使用 GITHUB_TOKEN；没有此权限时不降低校验、不伪造发布结果。此凭据尚未配置/验证，未重触发构建或发布。配置后可只晋升原 run 44245895574；不需编译、不动 main/KSU。

### alpha.54 发布方案修正（不增加任何 Secret）
用户明确无需增加 Token。保留原四个签名 Secrets；删除未使用的 BERRYFCM_RELEASE_TOKEN 入口。发布源快照 `release/alpha.54` / `2b239ccbc0624b09e67143c86d3f69499205bc1b` 已由原实际构建提交 `bde6ff58263c55e7b283a387eb9b6625e3f2dbed` 派生并验证，唯一差异是 `.github/workflows/build-apk.yml` 恢复为当前 main 的版本；全部产品源码、测试、其他文件完全相同，两份 workflow 的 blob SHA 与 main 一致。GitHub Release tag 指向该快照，不冒充原始构建提交；Release 说明同时记录原始构建 SHA / run 44245895574 及快照 SHA。晋升流程使用默认 GITHUB_TOKEN，重新验证原 run 全部八项门槛、原 APK、包名、版本、固定签名、快照唯一 CI 差异和 main workflow 一致性，再发布原制品。不重新编译，不修改 main/KSU，不更改签名；如 GitHub 拒绝，不自动请求更多权限。实际发布结果仍待核实。

### alpha.54 测试发布成功
- 2026-11-18 已实际确认 [Release v0.1.0-alpha.54](https://github.com/jarod360/Berry-FCM-OS7/releases/tag/v0.1.0-alpha.54)，release ID 449600753，非草稿、prerelease=true。两个兼容文件名 APK 都是同一份已验签的原构建制品，大小均为 8244791 bytes，SHA256 `754ebf5adce2a5a768d279a487eda31f18337cdb67f135ce9e5343509de7f99c`。
- [仅发布任务 #44251045028](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44251045028) 已通过制品来源、源码快照一致性、固定证书、包名与版本校验，并成功创建 Release。build 跳过；无额外 token，四项签名 Secrets 不变，main 不变。下一步是用户在旧版 APP 内检查更新并覆盖安装，进行真实设备验收；不把 CI 通过等同于实机功能通过。

### alpha.54 后续界面与逻辑集中审计（不编译）
用户正在验证 alpha.54，研发并行完善原设计，不改变现有发布包、不增依赖，不改自动恢复阈值/广播。参考 GKD 的 GkHomeScaffold Material3 主导航及 AGENTS.md 生命周期状态/最小子树、Shizuku HomeActivity 的 onResume 状态回读与 SettingsFragment 原生分组。实际改动：
- 通用 Ui 统一页面导航（主页面切换不再累积每个 Activity，禁止自跳）、次级页面底部及横向系统栏 Insets、按钮自适应高度、暗色主按钮文本对比度、可聚焦入口与返回后主题重建。首页新增直接授权入口，监控页将实时状态前置，统一绿色/黄色/红色语义，持续时长按天/时/分/秒显示，原生日志倒序，过期/无授权证据标为历史；首页/监控/前台通知共用 MonitorStatus，拒绝用旧数据假报在线。
- 监控/守护/保活重复开关按同一 prefs 回读，程序同步用 syncChecked 阻止监听器重入，不因回滚把任务开关写成关闭。取消重复授权成功触发 checkNow；授权页辅助权限单独后台线程并合并重复回读，状态和操作分列，磁贴申请防重复、自页面不再跳自身。配对或独立服务正在启动时不允许切换另一种授权。
- 90秒交互守护巡检离开页面真正取消，手动检查/心跳防重复排队；诊断页先验证核心授权，再运行特权策略查询，防重复队列；更新器关闭页面后不再处理安装弹窗/过期校验结果。
- 服务恢复不由页面连续绕过失败退避，网络/亮屏触发尊重原退避，停止后排队检查不再执行；采样回写前核对当前连接 key、会话、任务开关；模式切换/守护关闭不再继续后续批次或心跳。实际 ADB 启动链、FCM 恢复算法保持 alpha.54 基线待实机反馈。Vivo 私有权限未确认不伪造状态。
- 新增纯 Java MonitorStatusSmoke（11个状态和2个时长断言）；增加相关静态回归。仅开发分支，完整 Android 编译/真机 UI 布局尚未执行，后续集中构建。alpha.54 Release 不动。

### 进一步收口页面布局、后台竞态与实测自检
- 授权方式改为三项核心 + 两项备用的两行布局，全部可见；辅助权限条目两行显示、操作箭头独立。Root/静态 TCP 统一表达“上次验证成功”，不再把两分钟 TTL 到期当作授权取消。磁贴申请期间禁止重复添加/移除；厂商查询只合并至多一个后续异步读取，不重建整个页面。
- 服务检查失败被归属当前会话与连接 key，旧授权/上次运行错误不再冒充当前状态。另发现 set/install 失败时模式变更判断会反复绕过退避，改为独立记录尝试 key。周期调度保留单一 Future，生命周期停止在主线程重新验证条件，stopSelfResult 防止过期停止请求，已取消任务不得继续手动重连。守护异常也不在旧模式/取消后发布。
- 守护报告改用可见期 SharedPreferences 监听，返回页面立即刷新，实际目标组/报告未改变时不重建列表；新报告不能覆盖正在操作的交互输出。监控/守护的核心阈值和广播仍不变。
- 已在容器实际运行 MonitorStatusSmoke，11 个状态、2 个时长断言 PASS；两个文件 SHA 分别 d065bca3b4097041df7a59715ccbb0faeefd6cfd 和 aeb72d520b45f0b5d80cb21abd4ed655030f580a，与仓库逐一一致。先前 alpha.54 已通过的原生脚本和完整编译不等同于新代码通过。当前仅源码优化，等待集中下一次编译，不修改 alpha.54 Release 或 build 分支。


### 2026-11-18 alpha.54 授权实机失败专项

- 实机错误：PrivilegeStartupException / NoSuchMethodError，平台 Conscrypt.exportKeyingMaterial。比对 Priv Kit v0.20.0 官方接入文档和 GKD 的 Application：BerryFCM 漏掉 HiddenApiBypass 6.2 依赖及 attachBaseContext 初始化，并全局注册了外部 Conscrypt，和 Priv Kit 使用平台 TLS 及平台 exporter 的方式不一致。已补齐官方接入，移除全局 provider 覆盖；显式静态 TCP 的 libadb 保留自己的 Conscrypt 依赖。保留原 Priv Kit 加密身份、包名、签名及数据。
- 首页面与授权页进入时共同尝试恢复已保存的 Priv Kit 身份（即使本地历史标记缺失），真实 Binder UID2000 和 id 验证后保存，拒绝才提示重新配对；无线调试关闭、发现不可用不当作撤销。共享并发门控及持久冷却，正常 Binder 采样不重新打开 ADB；不把文件存在当作认证成功。
- 自动端口仍采用上游本机 mDNS：正常只输入六位码，手动端口仅备用。未获取 OriginOS 7 真机成功证据，不宣称端口问题已解决。
- 加入完整接入及身份恢复静态回归。本次修改尚需单次完整构建和固定签名验签，随后只发布通过的测试 prerelease，实机验证后再按项目计划处理。main 与 KSU 不改。


### FCM 恢复缺陷专项回归（2026-11-18）

- 用户在第三方授权下提供 14:43:09 新鲜 GMS 采样：FCM 已断开，监控/自动恢复均开，但仍提示等待异常确认；最近历史关闭事件 14:19:44。截图不证明整个间隔持续断开，也不能单独证明路由/代理问题或广播未送达。
- 已修正无原生断开时长、休眠采样间隔重置、备用主机连接计时重置导致的恢复饥饿；显式 disconnected 观察满15秒或 connecting 观察满120秒可请求恢复，长 native 断开仍须确认；跨90秒采样间隔需两次新鲜读取。已修正休眠跨间隔后在线恢复事件漏记。冷却及明确 stopped、未知状态、无网络、用户关闭自动恢复等保护保留。改用定向 GCM_RECONNECT，不用 heartbeat 冒充断联重连；仍须原生 Connected 才确认恢复。
- 监控页面显示真实恢复决策、请求次数及最近结果，不再用一个笼统的等待提示掩盖不发广播的原因。
- 独立验证分支 verify/fcm-recovery 的 [Actions #44253848951](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44253848951) 实际完成全部回归：Shell 语法、原生 GMS 模拟、无时长断联、跨休眠后恢复和确认、连接计时重置、权限异常、停止状态、冷却、守护分批、配对门控、监控显示及接入静态检查。该运行没有构建 APK、签名或发布；不是第三方授权真机或网络可达性实测。对应开发代码 957fbb8。
- 上一构建 [#44253249415](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44253249415) 在 Ui.java:240 的 LinearLayout.setMinHeight 调用失败，未签名、未发布。已改为 View.setMinimumHeight，尚未执行完整 Android 编译。按用户要求继续集中审查，不触发新的 APK 构建或发布；不能依据模拟回归宣称 OriginOS 网络已修复，最终还需验证 GMS 实际路径、恢复请求是否生效及推送送达。


### OriginOS 7 真机对照：广播未投递（2026-11-18）

alpha.54 Shizuku UserService 实际 UID2000；前台 FcmMonitorService 正常，原生 GMS 状态为 Not connected。14:47:54 自动及 14:50:36 手动 GCM_RECONNECT 均写 requested，但系统广播摘要 enqueue=当时时间、dispatch=1970-01-01、finish=enqueue，无实际分发证据。14:55:02 Termux Root UID0 发同一 action，系统记录 DELIVERED 到 GMS UID10200，3ms 内投递，14:55:04 原生 connected=mtalk.google.com/108.177.98.188,port=5228，随后持续连接。确认当时网络可达，不能把 am result=0 当作接收成功。Shell 未分发的具体原因尚待检查动态接收器 requiredPermission/exported 及系统 Permission Denial/skip 日志；不能认定所有 Android 均需 Root，也不应绕过接收器安全边界。当前设备可通过现有 Root 模式（用户明确授权）验证闭环。另有 12841 秒及 136 秒采样间隔和 Vivo freeze 记录，应单独处理。当前未构建或发布新 APK。


### 2026-11-18 15:29 手机真实非 Root ADB 对照

Termux 本机无线 ADB 配对通过，id=2000(shell)，SELinux u:r:shell:s0，GMS 当前连接 mtalk:5228（初始 connectTime 18:50）。
- 15:29:12.499 GCM_RECONNECT：caller uid=2000，SKIPPED，Exported Denial，receiver not specifying RECEIVER_EXPORTED。result=0 不代表投递。
- 15:29:17.689 MCS_HEARTBEAT：caller uid=2000，DELIVERED，GMS UID10200。
- 15:29:22.850 ACTION_HEARTBEAT_NOW：caller uid=2000，DELIVERED，同一 BroadcastFilter 4558867。

三条请求前后 GMS 一直已连接；仅证实后两条投递，不证实断联恢复。后续须在真实断联下独立验证、读取原生连接，不使用 Root。开发分支 54b9e849 按真实 UID 分流：2000 首次 MCS_HEARTBEAT、后续交替 ACTION_HEARTBEAT_NOW；0 保留可选恢复。测试 cd1301bf 覆盖两条 Shell 指令、停止使用私有重连广播和避免虚假成功。验证分支 ea745402 已提交检查，不发布。非 Root 实机恢复结论仍待验证。

### alpha.58 SDK37 authorization repair
User device: NSD connect discovery code 7 (permission denied), manual pairing can exchange a key but independent UID2000 Binder does not start. Official Android 17 default access for target37 needs ACCESS_LOCAL_NETWORK runtime permission. targetSdk updated 35->37; request must precede normal NSD and connection. The system's service.adb.tls.port is the live ADB *connect* port, not the pairing port, and is a safe first candidate if readable; otherwise retain Priv Kit discovery. A zero adb_wifi_enabled read may be redacted on Android17; treat it as unknown. Add service-paused preference and manual restart/stop controls for both BerryFCM transports; do not stop global Shizuku daemon or erase saved ADB identity. Source: Android Developer Local Network Permission; Shizuku-Next EnvironmentUtils / StartTransport. No target-device successful authorization proof yet.

Authorization UI now has user-selected tab independent from verified active mode, one-click start/stop/restart of BerryFCM's own binder/user service for wireless ADB and Shizuku. Never stops Shizuku's global daemon, revokes pairing, or resets monitor/guard preferences. Android 17 local-network permission prompt precedes discovery/connection. Target device must verify whether TLS port system property is visible and the binder starts successfully.

Pairing discovery now stops after its first valid local service and reuses that port for the crypto exchange rather than rediscovering mDNS. On explicit NSD permission denied (code 7) it terminates with a precise permission explanation rather than looping forever and asking for a manual port. Android adbd may bind a LAN-only pairing socket on other OEMs; on such devices Priv Kit's explicit loopback port would still require a LAN endpoint API and must be diagnosed separately, not represented as guaranteed.

### 2026-11-18 Android 17 ADB launch null-port crash
alpha.60 device screenshot confirms automatic pairing discovery works but start fails with Java 'Cannot invoke java.lang.Integer.intValue()' due to nested ternary in PrivKitShell: `Integer port = manual > 0 ? manual : tls > 0 ? tls : null`; Java numeric conditional unboxes null if both manual/system TLS ports are unavailable. Fixed through AdbConnectPort.select() returning boxed Integer/null without unboxing; regression tests check default 0/0, absent system property, active TLS and manual port. This is a proven Java crash fix, not proof Binder starts successfully on OriginOS 7.

### Authorization UI simplification
Each actual runtime method (Wireless ADB, Root, Shizuku, ADB TCP) has one status and bold [启动][停止][重启]. No BerryFCM Shell/UserService/Binder technical names in the main UI; diagnostics, pairing and manual ports are under disclosures. Stopping root or explicit TCP only stops BerryFCM's use/background tasks, not system root or adbd; wireless stops the app's own privilege server, and Shizuku stops the app's bound user service without shutting down Shizuku itself. Inactive selected method is 未启动 rather than wrongly saying 当前使用 Shizuku. Paused state blocks background task gate.

### Compact authorization state and inline failure diagnostics
Auth page now shows a single large actual state (已启动/已停止/启动失败/处理中), small 来源：无线 ADB/Root/Shizuku/ADB TCP, and one play/pause icon toggling selected transport. On real startup failure, the summary appears directly below; full error + Priv Kit trace can be expanded/copied. Method chooser and pairing are collapsed. Wireless ADB crash null-unboxing fixed in previous commit; real device Binder start remains unverified.

### 2026-11-18 OEM permission UI clean-up
Removed the full `cmd appops get top.zesun.berryfcm` dump incorrectly labeled as vendor permissions diagnosis. Android AppOps are not reliable indicators of OriginOS 自启动、关联启动、高耗电. Kept separate user-actionable settings links and conservative '需在系统确认' when an OEM toggle cannot be read. Does not alter privileges, policies, or the already-released APK.

## 2026-11-19 Issue #1/#2 集中研发接续（未发布）
- 唯一分支：[dev/issues-1-2-wake-ui-20261119](https://github.com/jarod360/Berry-FCM-OS7/tree/dev/issues-1-2-wake-ui-20261119)，基于已发行 alpha.89 对应 SHA `150017898629e8b436909ee0213babbb02c22007`。不修改 alpha.89、main、KSU、签名及权限。
- **CPU 策略**：新装默认智能省电，已有 alpha.89 用户保留原持续持锁；手动再次选持续时弹窗确认，取消不写设置。仅开启守护不需要持续持锁。保留 15 秒机会性巡检、60 秒请求闹钟与原生 GMS 判断/恢复阈值，不承诺 Doze 下 60 秒硬唤醒。
- **有界持锁**：FCM 采样与手动恢复各最多 120 秒事务锁（考虑安装脚本与每命令45秒 Shell 等待）；守护分批每条 Shell 命令最多 60 秒，闹钟 PendingIntent → 前台服务 worker 交接最多 90 秒。可信原生 GMS 异常首次出现时可进入最长 90 秒的确认窗口，**同一异常绝不循环续约**，新原生 connected 才重置。停止、切换或服务销毁释放。累积锁时长分别统计，互相重叠时不得相加成耗电量。
- **UI**：四项胶囊导航、后台保活作为设置次级页面并保留首页入口、深浅模式公用圆角确认框、用户文字命名和折叠标题调整、智能/持续策略选择与锁状态可见。选定的 PNG 启动图标仍沿用；小通知图标维持单色矢量并显式着色。OriginOS 通知中心旧图标/缓存问题仍要真机对照。
- **静态审计**：在原 `tests/apk-module-smoke.sh` 增加模式迁移、锁寿命、异常窗口、闹钟交接、授权确认、页面链接、Manifest/快捷键检查；不借 Gradle 编译报错替代逻辑审查。**尚未运行完整 Android 编译和目标设备实测**。
- **保留用户跨夜证据**：19日03:14原生断开、03:15 UID2000 请求与原生重连，05:00–06:23 Doze 约16秒检查、约4分钟闹钟延迟。此证据不证明广播导致重连或设备物理深睡仍16秒；日志为滚动缓冲，非无损整夜每一条采样。
- **后续验收**：前置脚本/源码审查 → 一次完整固定签名 CI 编译 → 同一制品测试包；再同网络做智能省电与持续唤醒 A/B，测每小时电量、温度、P95/最长巡检空档、持续断联恢复、杀进程/UID2000 Binder 停止后的恢复、通知/图标和主题/覆盖安装。CI 成功不等于手机验收。

### 2026-11-19 Issue #1/#2 已签名测试版本（修订上述“未发布”状态）
- 最新开发分支和 PR：`dev/issues-1-2-wake-ui-20261119`，审查 PR [#3](https://github.com/jarod360/Berry-FCM-OS7/pull/3)，以 alpha.89 构建源码为基线，**仍待真机 A/B 与视觉验收，不自动合并 main**。
- 修正后的 [CI #94](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44419769428) 完整成功：原生 GMS Shell 回归、APK 跨文件/权限与 WakeLock 静态检查、Java/Android 37 编译、启动图标资源检查、合并权限、固定签名及单签名验签、上传制品。对应构建源码 `45550adc213f1de7606d3f0dfefe0ef6df4e773e`。CI 分支与开发分支在当时核对的 82 个文件中只差 `.github/workflows/build-apk.yml`。
- [晋升 #95](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44420397868) 跳过构建，直接重用上一个已验证的签名 APK。GitHub 测试 [Release v0.1.0-alpha.94](https://github.com/jarod360/Berry-FCM-OS7/releases/tag/v0.1.0-alpha.94) 已核实为 `prerelease=true`、`draft=false`，Release ID `450679392`，文件大小 `8275639` bytes，两份兼容文件名的 SHA-256 均为 `13f8ca1943e438c83e242581feacea074ff0e1db406a6fa68efcf9402d9ac301`。
- 发布 Tag 指向源快照 `087bc8febf9d3b51329227bfb454e156b272d507`，它比原始构建提交只多一个 CI 工作流修正提交，应用/测试源码完全一致；两份 workflow 与 main 相同。旧签名四项 Secret 保持不变，无新增 PAT；原 alpha.89 发布包和 KernelSU 均未改。
- 修正：关闭 FCM 但继续守护时，立即释放有界的 GMS 异常确认锁；`tests/apk-module-smoke.sh` 增加该组合断言。说明本期 alpha.94 才包含此安全修复；先前 alpha.91 构建不用于测试发布。
- 下阶段 **必须实机观察**：原地在线升级/授权身份保留；模式切换确认和取消，强制停止或 Binder 断开，15 秒巡检间隔分布、异常确认窗口/冷却、两种模式至少各两轮 1–2 小时的耗电和温度；通知中心图标与快捷磁贴、深浅主题和小屏字体。物理 CPU 深睡、60 秒内恢复和广播实际效果尚未有新版本的证据。不要将编译成功视为验收成功。


### 2026-11-19 Issue #2 独立休眠兜底恢复源码增量（未编译、未实机验证）
- 用户纠正：兜底恢复属于独立事务，与 MonitorWatchdog 定时器及正常巡检的自动恢复逻辑解耦；正常巡检继续调用原有 `monitor → auto_recovery`。兜底只在智能模式的相邻采样空档至少90秒（服务重建时读取上次本机单调采样时间）且最新 GMS 原生状态确认为 connecting/disconnected 时启动。
- 兜底采用现有授权 UID 的定向命令：UID2000 交替 MCS_HEARTBEAT / ACTION_HEARTBEAT_NOW；UID0 才使用 GCM_RECONNECT。每次新鲜原生状态两次确认，发广播后持锁最多12秒等待再查原生状态；GMS 已 connected 立即终止，否则仅尝试剩余次数，整轮最多三次；每轮之间至少300秒，失败或系统中断释放事务锁。Shell 单调用45秒最坏超时与120秒事务锁配合，总事务留15秒余量，必要时少于三次便退出。
- 非 Root 广播在2026-11-18的UID2000实验中仅证实可投递；实机断联恢复有效性未证实。应用网络路径的上次成功 GMS IPv4 端点最多1.5秒TCP探测只能做诊断，不能视为 GMS UID 真实路由，也不会阻断下一次受控恢复；无可靠IP时记录unknown，不臆测DNS与网络通畅。若Doze停止网络或限制持锁，仍可能只执行部分事务，不能保证确切唤醒/恢复时间。
- 本增量位于 `dev/issues-1-2-wake-ui-20261119`，含源码/单元模拟用例及静态约束。仅完成 GitHub 源码审阅与编辑时的静态核对，尚无 Shell 用例实际执行证据、Android Java编译、签名APK或目标OriginOS7实测；不能说已通过验收。待集中运行 `sh -n app/src/main/assets/fcm-monitor.sh`、`sh tests/apk-native-fcm-smoke.sh`、`sh tests/apk-module-smoke.sh`，再进行一次完整CI和真机断联对照后才考虑测试版发布。UI心跳保活图标与四项设置图标的改动也在同一开发分支。


### 2026-11-19 alpha.98 界面图标风格审计与下次统一修复待办

- 来源：用户提供的 alpha.98 首页截图（12:42）。截图中的顶部 BerryFCM / FCM 监控盾牌和“后台保活”心形心电波为**线框样式**；同一常用功能卡片的“应用守护”实心盾牌、“网络诊断”实心统计柱、“授权管理”实心钥匙明显不统一。该问题经开发分支 `app/src/main/res/drawable/ic_bf_*.xml` 与 `Ui.java` 源码对照确认，并非颜色主题本身异常。此条只登记，下次 UI 修复时一起处理；本次**不修改任何图标、代码、签名或 APK**。
- **完整资源盘点（14 个）**：当前 8 个**实心**图标为 `ic_bf_guard`、`ic_bf_diagnostics`、`ic_bf_auth`、`ic_bf_home`、`ic_bf_settings`、`ic_bf_update`、`ic_bf_battery`、`ic_bf_alert`；6 个**线框**图标为 `ic_bf_fcm`、`ic_bf_heartbeat`、`ic_bf_code`、`ic_bf_feedback`、`ic_bf_info`、`ic_bf_device`。实心旧图标主要来自 Material Icons，线框图标已使用 24dp 视窗、约 1.8–2dp 描边。应用标题、列表和底部导航使用相同 `symbol()` 着色入口，问题是 SVG 矢量造型混搭。
- **各页面复查结果**：①首页“应用守护/网络诊断/授权管理”三处确定不一致，需优先修；②底部导航的“概览/守护/设置”为实心，“监控”为线框，四项同级不一致；③应用守护、网络诊断、授权管理、设置、版本更新等页面标题经 `symbolFor()` 引用同一批实心图标，存在同类问题（次级页面标题没有独立头图标时以其列表入口/导航为准）；④旧电池、更新和提示图标仍为实心，需在实际使用位置统一，且电池仅表示电池设置，不得再映射“后台保活”；⑤设置页新增“项目主页/反馈问题/当前版本/适配范围”四枚已经是线框，继续保持独立语义，不要重新回退成同一枚 FCM 图标。
- **另外发现的图标语义错误**：`Ui.symbolFor(String label)` 依赖中文关键字匹配，未命中时默认返回 `ic_bf_fcm`。例如后台页的“添加休眠豁免/撤销休眠豁免”、更新页“查看 GitHub Releases”会错误地显示 FCM 盾牌；“允许后台计量流量/撤销后台流量放行”因包含“后台”而显示心电图。下次修复不应只替换三张 SVG，要逐项审核页面的图标语义；建议改为各入口显式指定资源（或严格映射表），避免修改文案时发生隐式图标变化。
- **下次修复的风格/范围标准**：以原生 BerryFCM 盾牌心电波和新的心跳图标为基准，统一应用内 UI 图标为 **24×24、线框、线宽约 1.8–2.0、圆端/圆角**，统一随浅色/深色主题 tint；同一底部导航不能部分实心部分线框，选中态通过统一胶囊底色和 tint 表示。使用已有 Android VectorDrawable 即可，不增加运行时图标依赖。**不触及**已选 launcher PNG、通知栏单色图标 `ic_berry_fcm_mono`、第三方 APP 自带图标、任何后台/FCM 功能代码。
- **下一轮验收**：逐页核对概览/监控/守护/设置、授权、诊断、保活、更新页；逐资源校验存在性、颜色由 tint 驱动、同尺寸描边以及导航风格一致；按标签语义核对无不当 `ic_bf_fcm` 兜底；实际对照浅色/深色界面截图并运行 `tests/apk-module-smoke.sh`、完整固定签名构建/覆盖安装验证。编译成功不能替代视觉对照。
- **版本状态补记**：同日开发分支构建 [Actions #44452714293](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44452714293) 已通过原生恢复模拟、模块/权限检查、Debug/稳定签名 Release 构建及签名验证，上传测试 Artifact `BerryFCM-v0.1.0-alpha.98`；**未正式发布 Release，未作 OriginOS 真机恢复与图标全面验收**。历史上方“未编译”标记记录的是该构建之前的阶段，不代表当前状态。


### 2026-11-19 alpha.98 通知中心 GMS 连接计时（下一版待办）

- **用户截图与目标**：OriginOS 7 通知中心中 BerryFCM 前台服务通知当前文案为“后台监控运行中（连接详情请在应用内查看）”。下一版将该位置改为直接展示**当前 GMS 原生连接状态与计时**，例如 `FCM 已连接 · GMS 计时：10分0秒`；不是新增第二条通知，不改通知渠道的重要性、常驻服务的启动/停止原则，也不代表心跳或收信成功。
- **实现入口**：`app/src/main/java/top/zesun/berryfcm/FcmMonitorService.java` 的 `notificationText()` / `refreshNotification()`；目前返回固定文字，且 `lastNotificationText` 去重使它不会因采样自动变化。复用 `MonitorStatus.resolve()`、`MonitorStatus.connectedDuration()` 和原有 `lastSnapshot()` / `sampleAgeSeconds()`，不得为通知新增独立 GMS dumpsys、定时 WakeLock、常驻秒级线程或网络请求。
- **状态约束**：仅在监控开启、授权有效、采样属于当前会话且足够新鲜、`fcm_source=gms`、`fcm_state=connected` 时显示 `GMS 计时`。如果 GMS 原生 `fcm_native_duration` 为 0 或 -1，则遵照 `MonitorStatus.connectedDuration()` 的判定显示“已观察在线”或“计时待确认”，不得把观察在线长度冒充精确连接总时长。断开/连接中显示对应状态（可展示原生断开时长），Shell 授权失效、后台监控关闭、检查失败、数据超过 90 秒等分别显示明确非实时状态，不沿用旧“已连接”倒计时。
- **刷新与功耗**：仅复用已有采样成功、状态改变和现有通知更新时机；避免因每秒增长而持续 `NotificationManager.notify()`、导致通知横幅/耗电/闪动。优先分钟级文字精度或 Android 系统时间展示能力，具体实现需在 OriginOS 7 真机确认系统通知中心样式和实际计时行为；不能在停止监控时显示持续累加的 GMS 时间。
- **验收**：同一签名升级后验证亮屏/息屏、智能省电/持续唤醒、在线/断开/连接中/unknown、原生时长0、采样停滞、服务重启/授权失效、深浅主题、通知折叠/展开；对照应用内“GMS 计时”来源一致；不增加额外高频后台唤醒。与此前“14个矢量图标风格统一”一起排入下一版集中 UI 改造，但分别测试。
- **本次处理范围**：只在开发分支的交接文档登记，不修改 App Java/XML 或测试 APK、不触发构建/发布；当前 alpha.98 通知行为保持不变。

### 2026-11-19 通知图标需求澄清：正文增加心跳，应用图标不动
- 用户明确纠正此前“替换通知图标”的理解：**保留现有 BerryFCM 通知应用图标、通知栏小图标 `ic_berry_fcm_mono`、应用启动图标及通知标题“BerryFCM”全部不变**。
- 下次改造的是**通知正文**：在“FCM 已连接 · GMS 计时：10分0秒”这类状态/计时文案**前方增加现有后台保活心跳图标 `ic_bf_heartbeat`**，形成“[心跳图标] FCM 已连接 · GMS 计时：10分0秒”的视觉效果；断开、连接中、未知等状态亦保持相同图标位置与风格。
- 技术约束：`Notification.Builder.setContentText()` 只能接受文本，不能在文案中直接嵌入 VectorDrawable。下次应优先核实 Android/OriginOS 原生通知布局是否有保持原通知样式同时增加正文前置图标的可靠方案；如需 `RemoteViews`，必须验证折叠/展开、暗色/浅色、系统字体缩放、前台服务显示与后台耗电，不应擅自替换 `setSmallIcon` 或强行插入不一致的心形 Unicode/emoji 充数。若受系统通知模板限制，应明确反馈适配限制再选择替代显示位置。
- 与此前通知 GMS 计时及全部应用内图标统一一起列入下一版需求，**当前仅记录，不修改代码、不构建、不发布**。

### 2026-11-19 alpha.99+ 汇总 UI / 通知改造实施与验收
- 基于 alpha.98 的恢复逻辑保持不变，统一 ic_bf 系列实心图标为与原 FCM/心跳图标相同的 24dp、1.8–2dp 线框样式，保留独立语义的 GitHub/反馈/版本/设备图标；补充网络、休眠、刷新、添加、折叠箭头；关键按钮选择性显示同主题图标。卡片统一圆角与内间距，列表触摸区、折叠箭头、守护应用搜索框做小幅统一。**不更改 launcher、通知系统图标或 app icon**。
- GMS 通知：保留 `setSmallIcon(ic_berry_fcm_mono)`、标题 BerryFCM 和原有静音渠道；利用 Android `Notification.DecoratedCustomViewStyle` 的内嵌 `RemoteViews` 在通知正文放 `ic_bf_heartbeat`，折叠/展开复用。仅用现有当前会话 GMS 原生采样与 `MonitorStatus.resolve()`，计时按分钟量化以减少频繁通知更新；状态未知、采样过期、未授权不延续在线计时。OriginOS7 能否在通知中心正确渲染装饰式布局**必须真机验证**，系统可能改变其展示。
- 发布前约束：新 `tests/apk-module-smoke.sh` 视觉/通知静态门禁及原有 Shell 模拟全部通过，Android Debug + 固定证书 Release 编译、签名校验后才产生测试 prerelease。主分支与 KernelSU 不动；真机再核验深浅主题、小屏横屏、通知 icon 原样、计时更新频率、折叠展开与 FCM 恢复行为。

### 2026-11-19 alpha.101 预发布与严格前置验证结果
- 发布页面：[v0.1.0-alpha.101](https://github.com/jarod360/Berry-FCM-OS7/releases/tag/v0.1.0-alpha.101)，`prerelease=true`，`draft=false`。固定签名 APK `BerryFCM-v0.1.0-alpha.101.apk` 和旧版兼容别名均为 8,284,459 bytes，SHA-256 为 `1559504b284f7d5539e3ea0ab7c1420eb9e22e9815b66326fe1499abe0c986af`；原始构建源码 SHA `77f4bcae41459719aa3a342b155320e0a53dcb8d`，没有修改 main/KSU。
- 独立前置门禁：[Actions #44485453484](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44485453484) `success`；包含原生 GMS/Root/UID2000 模拟、休眠独立兜底及冷却、Shell 语法、权限与生命周期、19枚矢量图标及布局、通知 app icon 保留与正文心跳、XML 解析和源码差异空白审查。为保证**编译前**真正完成测试，将 dev 分支暂时移出构建 workflow push 触发器，仅由独立门禁运行；门禁全绿后再恢复构建触发器。
- 后续 [Actions #44485709324](https://github.com/jarod360/Berry-FCM-OS7/actions/runs/44485709324) `success`：重跑原生/模块门禁，Android Debug 编译、实际编译产物的启动及心跳图标/通知布局资源验证、合并权限、固定证书 SHA-256 核验、Release 编译、apksigner 验证、版本号/单证书核验、直接从该成功构建产物发布 prerelease（没有二次构建）。
- 本批功能：14个原先图标与5枚新增图标统一为 24dp 线框，改正休眠/网络等图标语义；卡片/按钮间距与导航箭头协调；通知标题仍为 BerryFCM、系统原小图标/程序 launcher 均不动，仅通知正文通过 DecoratedCustomViewStyle + RemoteViews 增加原后台保活心跳图标和带采样鲜度保护的 GMS 分钟级计时；alpha.98 已有的正常巡检和独立最多三次休眠兜底恢复算法保留。
- **未完成的真机验证，不得写成已通过**：OriginOS7 折叠/展开通知及深浅模式对比、心跳图标可见与字体对比、计时是否随采样刷新且过期后清除、主题对比/小屏字体、ADB UID2000 在真实断网后触发与连续恢复、断联恢复时 CPU 持锁上限和耗电。用户将在晚间实测。建议仅从 GitHub Release 的签名 APK 覆盖安装，保留原有数据与授权，出现异常导出完整 BerryFCM 状态诊断日志。

### 2026-11-19 alpha.101 网络诊断页面图标语义遗漏（下一批修复）
- 用户 16:26 的 OriginOS7 alpha.101 截图：网络诊断页面“更多诊断”中的 `Google FCM Diagnostics` 与 `监控记录` 两行仍为**相同的 FCM 心电盾牌**，而非对应功能图标。此前版本已把 19 枚 UI VectorDrawable 统一为线框，截图反映的是**语义选图遗漏**，并非图标资源没有更新或覆盖安装失败。
- 已按源码确认：`DiagnosticsActivity.java` 通过公共 `line(...)` 绘制两行，`Ui.symbolFor(String label)` 只匹配中文“诊断”，英文 `Google FCM Diagnostics` 会因包含 `FCM` 落入 `ic_bf_fcm`；`监控记录` 会因包含“监控”进入相同分支。因此这两行产生完全一致的盾牌。这不是用户误操作，也不是浅色/深色主题着色问题。
- **下次统一改，不在本次立即打包**：`Google FCM Diagnostics` 明确显示诊断/分析的线框图标（可复用 `ic_bf_diagnostics`）；`监控记录` 使用单独“历史/列表/时间轴”线框图标（必要时只新增一个 24dp VectorDrawable）。避免靠文案 `contains("FCM")` 等宽泛规则分配；可为关键列表入口显式传递资源 ID，其他页面沿用当前图标语义。复查 `Ui.java` 其他 `line()`、导航、二级页面中英文混排，避免同级不同功能入口仍共享默认 FCM 图标。
- **预构建验收补充**：在 `tests/apk-module-smoke.sh` 增加网络诊断页面的入口图标映射与两枚资源确实不同的约束；复核浅色/深色状态、尺寸/线宽、触摸与折叠区、OriginOS7 真机截图。保留现有固定签名和 UID2000/GMS 恢复测试。等用户集中指示下一次 UI 修复时合并处理，不因为单个图标问题单独编译/发布。
- **本次只追加待办文档**，保持已发布 `v0.1.0-alpha.101` 和现有开发源码不变，不启动 Actions、构建或 Release。

### 2026-11-19 alpha.101 通知 GMS 计时移除秒数（下次合并修复）
- 用户在夜间长时间熄屏测试前反馈：通知中心 GMS 连接计时的“秒”总是 `0`，没有实际信息量。下版通知**只显示小时和分钟，不出现秒字段**：例如 `FCM 已连接 · GMS 计时：1小时36分钟`，不足一小时为 `FCM 已连接 · GMS 计时：36分钟`，不足一分钟继续显示 `不足1分钟`；连接中/断开状态如展示持续时长也同样不显示秒。
- **源码核实**：`FcmMonitorService.notificationText()` 当前使用 `MonitorStatus.duration(seconds / 60 * 60)` 格式化通知，虽然分钟级截断后减少刷新，但共享的 `MonitorStatus.duration()` 仍追加 `0秒`。下次新增一个**仅用于通知**的“小时/分钟”格式化方法，避免修改应用内详细页面的秒级原生计时与既有测试契约；不增加秒级 `notify()`、后台定时器或独立采样任务。
- 下一轮和“Google FCM Diagnostics / 监控记录”图标映射一起完成。回归测试覆盖 0、59、60、3599、3600、5794 秒与断联/未知/采样过期状态，确保通知没有“0秒”、应用内秒级原样、通知系统图标与心跳正文图标不变。
- 本次只更新 `docs/HANDOFF.md`，不修改代码、不编译或发布，保持 `alpha.101` 用于今晚熄屏测试。

### 2026-11-20 alpha.101 夜间约 9 小时熄屏实测——首次独立 rescue 请求证据
- **来源与范围**：用户晨间导出的完整 BerryFCM 状态诊断，约 2026-11-19 23:45 至 2026-11-20 08:42（北京时间）覆盖 Wi-Fi / screen=off / idle=yes 的长时间 Doze 场景。当前无线授权模式 `wireless`；Binder UID=2000 PID=16156 存活；无监控错误；最新 GMS `connected`、源 `gms`、`tcp5228`，`fcm_native_duration=127s`（08:42 采样），不要误称整夜保持单一 TCP 连接。
- **首次独立救援实机证据 05:39**：`1795124394|sample_gap|301秒`、`1795124398|rescue_confirmed|两次原生状态仍未连接`、`1795124399|reconnect_requested|rescue UID=2000 MCS_HEARTBEAT exit=0 ...（第20次）`，GMS 原生日志：05:34:54 primary 重连开始，05:40:04 primary 失败 err:24 后 fallback，05:40:05.817 connected；BerryFCM 05:40:12 `connection_restored`。GMS 约 5分12秒未成功连上，故这次是有意义的真实断联场景；**不能从时间相关性断言请求必然促成恢复**。
- **第二次独立救援实机证据 06:34**：`1795127693|sample_gap|300秒`、`1795127698|rescue_confirmed` 同秒 `reconnect_requested|rescue UID=2000 MCS_HEARTBEAT ...（第21次）`；GMS 06:34:43 close 后 06:35:13 primary 失败、06:35:15 fallback 连上，BerryFCM 06:35:31 `connection_restored`。`source=rescue_followup` 在 06:35:10，`wake_confirmation_finished|held_ms=36580` 在 06:35:31。两次都是**不同救援轮次各一次请求**，没有出现同一轮三次重连未成功的实机覆盖；`fcm_attempts=21` 是累计请求计数，不是夜间请求次数。
- **Doze 调度与唤醒**：大量 `screen=off; idle=true; wake_mode=smart`，监控 `gap_ms` 常见 100k–300k，`suspend_ms` 近似对应，说明 CPU 实际长时间挂起。看门狗虽申请 60s，`alarm_late_ms` 常约 240,000ms，实际约 5min 后执行并检查 `sample_age_s>60`；这与 Android `AlarmManager.setAndAllowWhileIdle` 在 Doze 下可能延迟和节流相符，不能宣称每分钟准确巡检。执行时 `transaction_lock=true` 代表任务期间持有短锁，不是全夜持锁。确认锁有 36.58s、32.31s、11.43s 等结束记录，未见直接持续锁泄漏证据；没有整夜电量数据，**不能宣称省电/耗电验收通过**。
- **GMS 自身恢复情况**：05:29、05:34、05:59、06:09、06:14、06:24、07:24、08:14、08:34 等见 heartbeat delay / close err:28，常常 1–3 秒重新 connected；日志中最大可见延迟 298,550ms（08:14:52），是心跳定时器迟到，并非直接等于断联持续时间；err:20/24/28 不应在无 GMS 源码佐证时强行译成固定网络错误含义。累计 GMS native close=126、connected=127，不能当作当夜次数或单条推送送达证据。
- **未通过/尚无证据的事项**：任一轮 3 次救援仍未恢复后的完整退出与 CPU 锁释放、动作真正导致恢复的因果、夜间 FCM 消息端到端送达与耗时、整体耗电/待机电量损耗。快照 `fcm_last_result=requested` 是最后命令状态，不等于当前 GMS 未连接；当前为 `connected`。历史“ADB 认证已通过·当前待验证”与 Binder 可运行不能混同。
- **下一批改进建议（只登记）**：(1) `sample_gap` 日志拆分“预期 Doze 延迟”和“可能异常停摆”，降低每 90s 以上反复报错的误导；(2) 统计每轮 `rescue_started` / `rescue_request` / `rescue_restored` / `rescue_finished` 及每次请求后原生连接时间，确保脚本与 Java 重名 `rescue_finished` 在诊断界面不混淆；(3) 继续以 GMS 原生连接证据为门槛，切勿仅因 watchdog 延迟就发心跳；(4) 连同已登记的诊断页图标和通知计时去秒一次处理。本次**只保存诊断结论，不改代码、不构建、不发布新 Release**。


### 2026-11-22 RC7 后续静态审查：GMS 状态解析与 monitor/service 生命周期
- **GMS 原生状态解析**：目标 `SERVICE com.google.android.gms/.gcm.GcmService` 区块本身作为当前状态作用域；即使没有前置 `DeviceID:`、`disconnectTime` 等字段，区块内精确的裸 `Not connected` 也不再被误判为 `unknown`。增加了该格式的回归样例。未知状态仍不等于断联，不允许仅凭未知直接重连。
- **重复 GMS service 区块**：若同一份 dumpsys 中出现多个目标 GMS `SERVICE` 区块，解析器保守返回 `unknown`，不沿用前一个区块的 Connected/Disconnected 字段；新增“前块 Connected、后块无状态”和“前后块状态矛盾”两项回归夹具。
- **monitor 进程组身份**：Toybox timeout 使用其原生独立组；BusyBox/PATH timeout 只有经 setsid 建立私有会话后才传递隔离标记，无隔离能力时明确标记为非隔离。`fcm-monitor.sh` 原子记录五字段：monitor PID/starttime、PGID、隔离标记、PGID leader starttime；PGID 可以等于或不同于 monitor PID。
- **service 清理**：`service.sh` 在清理 monitor 时核验 PGID leader 的 starttime/PGID/cmdline，并再次核验 monitor PID/starttime/PGID，再对隔离组发送 TERM/KILL。兼容旧版两/四字段 owner 时，只在 monitor 自身就是组 leader 且 PID/starttime/PGID 可验证时推断；不能安全验证时不按未知 PGID 发信号。
- **启动顺序**：service 从 `/proc/self/stat` 读取自身 PID，先发布 PID/starttime 锁，再清理残留 monitor owner，最后启动 patrol。这样既防止并发 supervisor，也避免旧 monitor 的 flock 阻塞新巡检。新增测试核对锁 PID/starttime 与实际 service 进程一致，并覆盖新格式和旧格式 monitor owner 的进程组清理。
- **巡检 worker 回收**：patrol 每轮检查已结束的 maintenance worker，并调用 `wait` 回收，避免正常结束的后台 worker 长期残留 zombie PID。
- **当前验证边界**：静态核对了 KSU smoke 中的源码断言：正向断言均能在源码中找到对应实现；负向断言用于防止双重转义、残留 shell PID 展开和 service PID 写入回归；检查了新增回归用例没有重复主体。容器中分别模拟了 `/proc/self/stat` PID 读取、setsid 进程组身份与组内子进程清理。**完整 `fcm-monitor-smoke.sh`、`ksu-wake-smoke.sh`、所有 Shell 文件的 `sh -n`、目标 Android/KernelSU/GMS 实机测试尚未执行**；上述模拟不能替代 Android 实机验证。
- **构建约束**：本轮未触发 workflow、编译、打包或 Release；PR #1 仍保持 open / not merged。待代码与静态审查全部结束后，再由用户手动触发完整构建。


### 2026-11-22 退出竞态复审补充
- 发现 service 原先先清理 monitor owner、再停止 patrol 的竞态：monitor 正在启动但尚未发布 owner 文件时，第一次清理可能看不到它；之后 patrol 退出可能遗留 monitor。
- 已将 `service_cleanup()` 顺序调整为：停止 timer → 停止 patrol → 清理 monitor owner → 清理 maintenance owner。patrol 停止后不再产生新的 monitor 检查，再读取 owner 锁清理在停止窗口内发布的 monitor 身份。
- KSU smoke 增加静态顺序断言，要求 `stop_patrol` 必须位于 `stop_monitor_owner` 之前。
- 此项目前完成源码和断言静态核对；尚未执行完整 KSU smoke，因此退出竞态的动态回归仍待完整测试验证。


### 2026-11-22 RC7 进程组隔离复审：timeout 实现差异与退出清理

- **上游源码核实**：
  - Toybox `timeout` 默认通过 `setpgid(0, 0)` 将被执行命令放入独立进程组；`--foreground` 才不创建新组。源码：[Toybox timeout.c](https://github.com/landley/toybox/blob/master/toys/other/timeout.c)。
  - BusyBox `timeout` 的实现是建立 watchdog 子进程并在主进程中 `exec` 被监控命令，超时信号发给直接 PID；它本身不创建独立进程组。源码：[BusyBox timeout.c](https://github.com/mirror/busybox/blob/master/coreutils/timeout.c)。
  - BusyBox/Toybox `setsid` 在调用者已经是进程组 leader 时可能 fork；当前 `run_bounded()` 位于命令替换子 shell 中，外部 `setsid` 进程正常情况下不是该进程组 leader。源码：[BusyBox setsid.c](https://github.com/mirror/busybox/blob/master/util-linux/setsid.c)、[Toybox setsid.c](https://github.com/landley/toybox/blob/master/toys/other/setsid.c)。
- **发现的实际风险**：原 `patrol.sh` 将 BusyBox `timeout` 也设置 `BERRY_FCM_ISOLATED_GROUP=1`。BusyBox 不创建独立组时，monitor 会继承 service 所在进程组；`service.sh` 若按该标记对负 PGID 发信号，可能误杀整个 service 进程组。与此同时，Toybox/coreutils timeout 的进程组 leader 可能与 monitor PID 不同，旧逻辑只接受 `PGID == monitor PID`，导致实际独立组被降级为只杀 monitor shell，探测子进程可能遗留。
- **本次修正**：
  - Toybox timeout 保留其原生独立进程组标记。
  - BusyBox timeout 与 PATH 来源不确定的 timeout，优先通过 Toybox/BusyBox `setsid` 建立私有会话后才标记为 isolated；没有可用 `setsid` 时明确标记 `BERRY_FCM_ISOLATED_GROUP=0`，禁止把继承的 service 组当作 monitor 组。 无 timeout/setsid 的最后 watchdog 兜底也显式设置为 0，防止外部环境变量残留造成误标。 如果设备同时缺少 timeout 与 setsid，watchdog 只能保证结束 monitor 主进程，不能证明所有后代均退出；此时不按继承 PGID 发信号，需记录为目标设备能力限制。
  - `fcm-monitor.sh` 的 owner 文件扩展为五字段：monitor PID、monitor starttime、PGID、isolated 标记、PGID leader starttime。这样兼容 PGID 与 monitor PID 相同或不同的隔离方式。
  - `service.sh` 在组信号前核验 PGID leader 的 starttime/PGID/cmdline，并再次核验 monitor PID/starttime/PGID；旧四字段 isolated owner 仅在 monitor 自身就是组 leader 时兼容推断，不能把旧的未知组号当作安全组。
  - 正常 `service_cleanup()` 和巡检 watchdog 回收都改为先停止 patrol，再读取并清理 monitor owner，避免 patrol 在 owner 检查后才发布新的 monitor。
  - `hotinstall.sh` / `uninstall.sh` 等待旧 service 退出的上限从 24 秒延长到 45 秒。按当前有界清理路径估算，timer(7s)+patrol(7s)+monitor group(6s)+maintenance owner/child(最多约16s) 总计约36s；原24秒可能在维护 worker 清理中途强杀 service，45秒为其留出余量。 `uninstall.sh` 结束时若 `service.lock` 仍存在，会明确警告后台 worker 清理未确认，不擅自删除锁或伪称卸载清理完成。 另外，hotinstall/uninstall 现在兼容 RC5 缺少或无效 `starttime` 的旧锁：先核验 PID 对应的 service 命令行，再读取并固定当前 starttime，之后才发 TERM，避免旧版守护进程因缺字段而被误判为不存在。
  - `tests/ksu-wake-smoke.sh` 新增 timeout wrapper 作为 PGID leader 的 `PGID != monitor PID` 模拟退出用例、BusyBox timeout 经 setsid 隔离用例，以及 watchdog 清理顺序断言。
  - 另修正 monitor 内部 DNS 子查询：Toybox timeout 默认会再创建一层独立进程组，服务只清理外层 monitor 组时可能留下 nslookup；现对 Toybox/GNU timeout 使用 `--foreground`，让 DNS 子进程留在 monitor 组内。PATH timeout 先根据帮助信息识别支持 `--foreground` 的实现；BusyBox 的直接 PID timeout 已确认不创建新组，可在当前 monitor 组内使用；无法识别的实现跳过 DNS 查询，避免误创建不可追踪的子进程组。FCM smoke 增加对应静态断言，并增加 PATH GNU/Coreutils 与 BusyBox timeout 两种帮助信息/执行路径回归夹具。
- **已完成的验证**：核对了上述上游实现；在 Linux 容器模拟了 timeout wrapper 为组 leader、monitor PID 与 PGID 不同的情形，按新身份校验向该组发送信号后 wrapper 和 monitor 子进程均退出；另模拟 BusyBox timeout 经 setsid 后 monitor PID 即 PGID，组信号能终止 monitor 与子进程。静态核对了新增 owner 字段、服务端校验和 timeout 分支。 另外模拟 GNU/Coreutils `timeout --foreground` 与 BusyBox direct-PID timeout 的进程组继承，并执行了 PATH timeout 帮助信息识别分支；修改过的 patrol/service/DNS 代码片段及新增 KSU/FCM 测试 heredoc 片段通过 POSIX `sh -n`。这些仅是片段语法和 Linux 行为模拟，不等于完整 smoke 或 Android 实机通过。
- **尚未完成**：完整 `tests/ksu-wake-smoke.sh`、`tests/fcm-monitor-smoke.sh`、所有 Shell 文件 `sh -n` 以及 OriginOS/KernelSU/GMS 实机测试尚未执行。Linux 模拟不能替代 Android Toybox/BusyBox 版本和目标 shell 的实测。
- **构建约束**：本轮没有触发 GitHub Actions、编译、打包或 Release；PR #1 仍保持 open / not merged。待完整静态审查与 smoke 测试结束后，再通知用户手动构建测试。

### 2026-11-22 monitor flock 锁生命周期修正
- **发现的问题**：旧 `with_flock()` 通过命令替换单独执行 `flock -xn 9`，flock 子进程在检查后立即退出，文件锁没有覆盖后续 monitor/reconnect 操作；此前的并发用例只验证“外部持锁时请求被拒绝”，没有验证 BerryFCM 自己是否持锁到操作结束。
- **修正方式**：改为让 flock 以子命令方式启动同一脚本的 `--locked` 分支，锁由 flock 进程持有直到整个监控操作结束。子进程将真实命令退出码写入独立结果文件，避免 flock 的锁冲突退出码与 monitor 自身退出码混淆；临时文件 PID 从 `/proc/self/stat` 读取，不依赖 `$$` 展开。
- **回归用例**：FCM smoke 增加阻塞 dumpsys 的并发测试：第一个 monitor 正在执行时，第二个 reconnect 必须收到“后台正在检查 GMS”，且 dumpsys 只执行一次。测试清理钩子会在异常退出时终止尚未结束的第一条 monitor 进程。
- **局部验证**：KSU/FCM smoke 的源码字面断言均能匹配当前源码；两份 smoke、相关 Shell 文件及 HANDOFF 均无尾随空白和冲突标记。Linux 容器中用 util-linux flock 模拟了完整持锁子命令：并发请求返回锁冲突，包装逻辑返回 13；另验证子命令真实退出码 12 能被保留。BusyBox 上游 `flock` 实现同样支持 FD 加子命令形式（参考：[BusyBox flock.c](https://github.com/brgl/busybox/blob/master/util-linux/flock.c)）。
- **尚未完成**：完整 `tests/fcm-monitor-smoke.sh`、`tests/ksu-wake-smoke.sh` 和所有 Shell 文件 `sh -n` 尚未在完整仓库环境执行；Linux 模拟不替代设备上的 KernelSU BusyBox、Android mksh 和 GMS 实测。
- **构建纪律**：未触发任何 workflow、编译、打包、合并或 Release。PR #1 仍保持 open / not merged；继续审查完成后再通知用户手动构建。

### 2026-11-22 GMS client 状态字段空格兼容
- `parse_mcs()` 原先只接受 `Is client connected: true/false`（冒号后有空格）；为兼容 dumpsys 输出紧凑形式 `Is client connected:true/false`，现改为接受冒号后零个或多个空白字符，再严格匹配 true/false。
- FCM smoke 增加无空格 true/false 两个夹具；静态检查确认 parser 与两项夹具均已落地，独立 AWK 正则模拟对有空格、无空格和多空格三种输入均得到预期结果。
- 完整 FCM/KSU smoke、所有脚本 `sh -n` 和设备端 GMS dumpsys 样本仍未执行；不能据此宣布整套测试通过。

### 2026-11-22 GMS stopped 状态与 Socket absence 边界
- **发现的问题**：当原生 GMS service 返回 `No services match`，且 `dumpsys package` 明确报告 `stopped=true` 时，旧逻辑虽把原因标记为 `gms_stopped`，但后续仍可能把连续 Socket absent 升级成 disconnected；未知状态的自动/手动恢复确认也可能据此发广播。GMS 套件被用户停止时没有 MCS Socket 是预期状态，不应当作网络断联。
- **修正方式**：`gms_stopped` 时不再将 Socket absence 或历史 Close 提升为断联；自动恢复直接返回 `gms_stopped_unknown`；手动恢复二次采样后再次检查 stopped 原因，禁止发送重连。native poll 间隔内保留上一次确认的 `gms_stopped`，避免第二次确认恰好遇到 deferred poll 时丢失保护。
- **回归用例**：保留 stopped + Socket unknown 测试；新增 stopped + Socket absent 测试，检查状态保持 unknown、原因显示 gms_stopped、自动和手动请求次数均不增加，并覆盖第二次确认落在 deferred native poll 的路径。
- **尚未完成**：以上是源码与测试夹具修正，完整 FCM/KSU smoke、Shell 语法 gate 和设备验证尚未执行。
- **连续缺失计时边界**：确认 stopped 后同时清零 Socket absence 的连续计时锚点；否则 GMS 停止期间累计的长空档会在用户重新启动 GMS 后被误当作新一轮持续断联。新增状态文件字段断言，确保 stopped + absent 时 `outage_hint_mono=0`；手动重连在 stopped 状态下明确返回 `gms_stopped_unknown`。- 若 stopped 期间仍观察到真实 ESTABLISHED MCS Socket，Socket 的 connected 证据优先：不触发恢复，状态决策保持 `not_disconnected`；只有非 connected 状态才返回 `gms_stopped_unknown`，避免把仍存活的连接误报为不可用。
