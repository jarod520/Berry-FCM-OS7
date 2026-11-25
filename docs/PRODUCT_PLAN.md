# Berry-FCM-OS7：产品目标与边界

> 更新：2026-11-25。本文件只记录不随每次提交变化的产品定位、原则和边界；具体版本状态、
> 已验证事实、未解决事项见 [HANDOFF.md](HANDOFF.md)。

## 产品定位

**BerryFCM Guardian** 是面向 Android / OriginOS 的 FCM 连接状态观察、受控重连、应用停止
状态守护、后台运行诊断工具。不是通用"无障碍管理器"，不声称永久不死的后台进程，不修改
DNS、代理、VPN、路由、hosts，不强制停止/重启 Google Play 服务。

两条产品线：
- **KernelSU 模块**（`module/`）：Root 环境下的 Shell 实现，当前是功能更完整、已在真机
  验证断联判定和多步恢复序列的一侧。
- **APK**（`app/`）：面向无 Root 用户，通过无线 ADB / Shizuku / Priv Kit 等方式获取受限
  Shell 权限；功能模块已实现，真机授权与后台保活验证仍在进行。

两线各自独立编译发布（`.github/workflows/build-ksu.yml` / `build-apk.yml`），KSU 端稳定
验证过的判定逻辑和回收策略之后再回移到 APK，不互相阻塞。

## 核心原则

- **观察和修复分开**：TCP 连接只是传输层证据，不等于应用层已认证或推送必达；广播被系统
  接受只代表"已请求"，不代表 GMS 已恢复。恢复动作之后必须用新的内核 Socket 采样确认。
- **状态分四种**：已连接（有证据）、缺失/连接中（有证据）、未知（权限/网络/采样缺失）、
  过期（样本太旧）。没有新样本时不延续"仍然在线"的计时，也不把未知当作断联。
- **漏检必须可见**：轮询间隔无法保证捕获秒级断联，不得虚构断开时刻；对照 Google 原生
  FCM Diagnostics 和真实推送效果，而不是只看自身日志。
- **权限最小化、可撤销**：先回读系统设置原值再修改；只撤销本应用自己添加的白名单/策略，
  不覆盖外部或系统已有配置。
- **后台保活是尽力而为**：前台服务、开机广播、厂商授权组合能提高可靠性，但不能承诺任意
  厂商限制/Doze/强制停止下永远运行。
- **不需要 AccessibilityService**：所有功能通过标准 Android API、Root 或用户主动授权的
  ADB Shell 完成；项目历史上存在过的第三方无障碍服务管理功能已被确认移除，不再恢复。

## 权限边界（按能力分级）

| 功能 | 最小所需能力 | 边界 |
| --- | --- | --- |
| 页面、状态、日志、历史、主题 | Android API + 本地持久化 | 采样源失效显示未知，不外推 |
| 应用名单搜索/多选 | PackageManager 可见性查询 | 按 Android 11+ 包可见性限制声明 `queries` |
| FCM Socket/UID、应用 stopped 检测与修复 | Root 或已授权 ADB Shell | 不满足时显示未知，不显示假成功 |
| Doze 白名单、AppOps 后台网络 | ADB/Root，先回读后再写 | 只能撤销本应用自己添加的项目 |
| 无线 ADB 配对 | Android RemoteInput + mDNS + AndroidKeyStore | 用户必须在系统设置里显式开启；不静默开启 |
| 后台持续采样与自动恢复 | Foreground Service + 开机/更新广播 | 厂商限制/Doze 可能阻止恢复，必须记录空档 |
| OriginOS 厂商自启/关联启动/高耗电 | 无可靠私有 API 时只能跳转系统页 | 不伪造已生效的开关状态 |
| 下拉快捷磁贴 | Android `TileService` | 用户主动添加，默认不开启，不自动添加 |
| GitHub Release 在线更新 | 网络 + 系统安装器 | 下载文件的包名/版本/签名三项校验是安全边界，不可因"简化代码"删除 |

## 开源参考（仅借鉴思路，不复制代码/界面/资源）

- [Shizuku](https://github.com/RikkaApps/Shizuku)：无线 ADB 的 RemoteInput 通知栏配对、
  mDNS 发现流程。
- [GKD](https://github.com/gkd-kit/gkd)：设置页分组与状态呈现；`Priv Kit` 依赖集成方式。
- [Priv Kit](https://github.com/priv-kit/priv-kit)：免 ADB 常驻通知的独立特权 Binder 服务。
- [FCMFix ColorOS](https://github.com/ByteJuno/fcmfix-coloros)：mtalk :443 候选判定思路。
- [HeartbeatFixerForFCM](https://github.com/grimseraph/HeartbeatFixerForFCM)：
  `GTALK_HEARTBEAT`/`MCS_HEARTBEAT` 等 GMS 内部广播动作的用法参考（均为未公开稳定契约，
  广播被接受不代表 GMS 处理成功）。

## 当前状态

KernelSU 端已完成"内核 Socket 唯一判据 + 多步有界恢复序列"的重构并在真机验证过核心路径
（断联判定、Root 广播被系统接受、守护名单修复）。APK 端功能模块齐备，但无线调试配对的
TLS 握手、后台保活、在线升级等真机验证尚未完成，仍使用旧的 dumpsys 判定方案，未与 KSU
同步。详见 [HANDOFF.md](HANDOFF.md) 的"未解决事项"。

## 变更管理

- 不擅自删除已实现的产品功能；有分歧先列证据、成本和替代方案再改。
- 具体开发进展、构建证据、commit/Actions 记录只写入 HANDOFF.md，不写入本文件。
- 签名密钥、P12、密码不写入任何文档或提交历史。
