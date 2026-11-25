# Berry-FCM-OS7 · BerryFCM

面向 Android / OriginOS 的 FCM 连接观察、受控重连、应用 stopped 状态守护与后台设置诊断。
同一个仓库维护两个独立交付物：

- **APK**（`app/`）：面向无 Root 用户，无线 ADB / Root / Shizuku 任选一种方式获取受限
  Shell 权限。当前版本 `v1.0-rc.4`（见 [version.properties](version.properties)）。
- **KernelSU 模块**（`module/`）：Root 环境下的 Shell 实现，功能更完整、已在真机验证
  断联判定和多步恢复序列。当前版本 `v1.0-rc.16`（见 [module/module.prop](module/module.prop)）。

两线各自独立编译，互不阻塞；KSU 端验证过的判定逻辑会逐步回移到 APK。

## 文档导航

- [产品目标、权限边界、开源参考](docs/PRODUCT_PLAN.md) — 不常变化的产品定位
- [当前版本、已验证事实、未解决事项](docs/HANDOFF.md) — 开发现状快照
- [APK 架构、无线配对操作](app/README.md) · [固定签名与 Release 约定](docs/SIGNING.md)
- [KernelSU 模块功能与手动诊断命令](module/README.md)

## 构建

GitHub Actions 中手动触发（均为 `workflow_dispatch`，不自动运行）：
- [Build Android APK](.github/workflows/build-apk.yml) — 编译并用固定签名打包 APK
- [Build KernelSU ZIP](.github/workflows/build-ksu.yml) — 编译 ARM64 唤醒定时器并打包模块 ZIP

普通 push 不会自动构建或发布；GitHub Release 需要手动批准后才会创建。

## 设计原则

Android API 优先，Root/ADB Shell 只用于确有权限需求的功能，不使用 AccessibilityService。
无法验证时显示未知，不误报连接恢复；不重启/杀死 GMS；不修改 DNS/VPN/代理/路由。厂商私有
设置（OriginOS 自启动、关联启动、高耗电、任务锁定）没有可靠 API 时跳转系统设置页，不提供
虚假的"已生效"开关。固定签名材料只存在 GitHub Secrets，不提交私钥或密码到仓库。
