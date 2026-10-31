# ChargeGuard

中文 · **[English](#introduction)**

ChargeGuard（充电守卫，简称 CG）是面向 iPhone 的充电控制工具：把电量停在你设定的值，避开高温满充，延长电池寿命。它不是硬件旁路充电，而是软件层充电策略控制：守护进程按配置接管充电状态，应用只负责展示与配置。仓库为 xstar68/ChargeGuard，应用、包、守护进程与数据标识均为 ChargeGuard；源码目录与类名前缀、URL Scheme `cl` 仍为技术内部标识，不影响使用。

## 界面介绍

<img src="docs/assets/chargeguard-icon-1024.png" alt="ChargeGuard 图标" width="120">

下图为**新界面设计预览**（按 v3 界面设计稿绘制，不是真机截图；真机截图待 v3.0 真机测试后补充）：

| 主界面 | 更多功能 | 历史统计 |
| --- | --- | --- |
| <img src="docs/assets/preview-main.png" alt="ChargeGuard v3 主界面设计预览" width="240"> | <img src="docs/assets/preview-entries.png" alt="ChargeGuard v3 更多功能设计预览" width="240"> | <img src="docs/assets/preview-history.png" alt="ChargeGuard v3 历史统计设计预览" width="240"> |

## v3.0 更新内容

v3.0 是对 v2.0 的全面重做，不是只改显示名。以下按界面、架构、功能、改名与设置版、修复优化、保持不变六组说明；凡是尚未在 Xcode 或真机上验证的项，见文末“尚未验证”一节，不作已完成宣称。

### 1. 全新界面

- **主界面**：顶部为渐变英雄卡，显示大电量百分比、当前充电状态，以及完整控制模式与适配器功率胶囊；下方为双列实时数据网格，分别为电流、电压、温度、健康度；原先单列的信息行（充电命令、系统停充抑制、系统优化充电、电池健康、温度、高温模拟、电流、电压、循环）已并入英雄卡状态区与数据网格，不再单列展示。
- **更多功能**：由单列小图标列表改为 2×2 大图标入口网格，分别为历史统计、电池兼容性测试、充电高级、软件设置。
- **历史统计页**：筛选改为圆角胶囊（5 分钟 / 小时 / 天 / 月），策略事件改为左侧彩色竖线时间线卡片，按状态、温控、接管、保持分类着色，时间、转变、原因与数值分行展示。
- **电池兼容性测试页**：结论改为卡片顶部大字，判定电流与耗时与结论同卡展示；未运行状态诚实显示“未运行”，不以默认值冒充结果；警告置顶。
- **充电高级页**：按停充控制、高温模拟与充电限流、系统优化充电、满充计划分组为卡片，开关统一放右侧，说明字缩小变灰；逻辑与默认值不变。
- **软件设置页**：改为版本卡、更新、诊断导出与自动化入口的分组布局；帮助页沿用 v2.0 的单链接设计，未重做。
- **旧版页保留**：每个新子页都保留“打开完整旧版页”入口，没有删掉任何原有功能；旧版主控制器仍在包内作回退，但打开软件默认是新主界面，不再是旧长列表。

### 2. 全新架构

- 新分层为 `CGConfig`（配置模型）→ `CGDaemonClient`（守护进程客户端）→ `CGBatteryViewModel`（视图模型）→ `CGViews` / `CGMainViewController` / `CGSubPages`（视图层），代码位于 `ChargeLimiter/UIKit/ChargeGuard/`。
- `CGDaemonClient` 是视图层访问守护进程的唯一接口，包装现有 `CLAPIClient` 的 `127.0.0.1:1230` `get_conf` / `set_conf` 协议；视图不再直接调用守护进程。
- `CGBatteryViewModel` 只做纯推导，不含 UIKit 调用与守护进程调用；所有写操作先经 `CGConfig` 校验，非法阈值在本地拒绝，不发给守护进程。
- 本版仍是 UIKit 分层架构，**不是 SwiftUI 迁移**。SwiftUI 迁移本次未做，因为在没有 Xcode 的环境下无法验证 SwiftUI 构建；新架构的模型与视图模型已与 UIKit 解耦，便于日后迁移。

### 3. 全新功能

以下功能全部基于守护进程已有数据，不发明硬件功能；只读功能自身不写配置：

- **充电历史趋势**：按 5 分钟 / 小时 / 天 / 月统计充电速度（%/小时）、最长连续充电时长与温度汇总；无数据时明确说明暂无样本。
- **智能满充建议**：按当前充电速度推算起床前开始充电的时间，仅作文字建议，不自动改配置。
- **温度与健康提醒、循环预测**：健康度低于 80% 时提醒；按当前循环推算到达 1000 次循环所需月数。
- **一键预设**：日常 80%、长寿 60%、出行 100%，点按即应用，且仅改停充值；应用失败时回滚到原值。
- **可导出诊断报告**：导出配置快照、电池数据、诊断信息与分析摘要的纯文本报告，可分享；导出本身不改配置，数据为空时不分享空报告。
- **自动化链接**：软件设置页可复制 `cl:///` 打开、`cl:///charge` 启用充电、`cl:///nocharge` 停用充电链接，用于快捷指令与自动化。

### 4. 全面改名与设置版

| 旧标识 | 新标识 |
| --- | --- |
| 包名 `com.chargelimiter.mod` | `com.chargeguard` |
| Bundle ID `com.chargelimiter.mod` | `com.chargeguard` |
| 应用文件夹 `ChargeLimiter.app` | `ChargeGuard.app` |
| 守护进程 `ChargeLimiterDaemon` | `ChargeGuardDaemon` |
| 数据目录 `/var/mobile/ChargeLimiter` | `/var/mobile/ChargeGuard` |
| 启动项 `com.chargelimiter.mod.plist` | `com.chargeguard.plist` |
| deb 内守护进程位置 | `/usr/libexec/ChargeGuardDaemon`（rootless 为 `/var/jb/usr/libexec`） |
| 下载文件名 `ChargeLimiter_<版本>_…` | `ChargeGuard_<版本>_…` |

- **deb 设置版真正可用**：deb 包不再安装 `.app` 到桌面，守护进程进 `libexec`，设置束进 `/Library/PreferenceBundles/ChargeGuardSettings.bundle`（rootless 与 roothide 按各自路径），并补上 PreferenceLoader 入口 `ChargeGuard.plist`，使系统设置里确实出现 ChargeGuard 入口；设置束控制器由骨架改为完整实现，以 POST JSON 方式 `get_conf` 建开关与滑块、`set_conf` 写回、失败回滚、离线不显示数值、不写 NSUserDefaults，并新增 Info.plist 与 Theos Makefile。Theos 编不出设置束时，deb 构建直接失败，不静默发出无界面的包。
- **TrollStore 的 tipa 仍留在桌面**，仅 deb 版只进设置。
- **升级迁移（deb）**：新包以 `Conflicts` / `Replaces: com.chargelimiter.mod` 替换旧包，不并存；安装时若旧数据目录存在且新目录缺失或为空，则把旧目录内容复制到新目录，旧配置文件若在新目录缺失则改名为新名，旧守护进程作业在新作业启动前显式停掉，复制后再次修复权限；**旧目录绝不删除**，作回退。TrollStore 用户因 Bundle ID 变化会得到新应用容器，配置需重新设置，这是改名本身的代价，deb 的目录迁移不适用于 tipa 容器。
- **仓库**：在线更新与帮助地址统一为 xstar68/ChargeGuard；Xcode 工程已由 `ChargeLimiter.xcodeproj` 改为 `ChargeGuard.xcodeproj`，目标与 Scheme 同步改名。

### 5. 修复与优化

以下均为报告中已核实并修复的项，按类别列出，不含未证实的宣称：

- **构建阻断修复**：rootful 应用目标的 `PRODUCT_NAME` 统一为 ChargeGuard；rootless 启动 plist 的守护进程路径由双写 `/var/jb/var/jb/…` 改为单前缀；rootful 守护进程目标的 entitlements 路径改为实际存在的文件；deb 补上 PreferenceLoader 入口，否则设置版装完找不到入口。
- **功能键修复**：高级页“智能停充”开关此前写入守护进程静默忽略的 `use_smart`（运行时检测值），现改为读写真正生效的 `adv_predictive_inhibit_charge`，`use_smart` 只作只读诊断。
- **历史页修复**：此前传空统计配置导致永远无数据，现显式请求 5 分钟 / 小时 / 天 / 月四档数据；胶囊筛选此前是装饰性的，现按选中桶计算速率与时长；温度原始值大于 200 时除以 100，避免显示约 2850°C；温度上限改用实时配置的 `tempAbove`，不再硬编码 40。
- **配置写入优化**：此前每次全量写 7 个键，可能触发守护进程对无关键的副作用，现改为与上一次配置对照、只写变化的键；无上一次配置时全写；失败时只回滚已写过的键。
- **写入诚实性与竞态**：新增写操作串行化，进行中忽略新手势；失败时按捕获的上一次配置重绘并显示真实错误原因，本地校验拒绝不再冒充守护进程拒绝；回滚失败时明确提示“回滚未完全成功，请重新进入页面核对”并重新拉取真实配置。
- **状态与刷新**：未插电时不再显示“已停充”与假适配器功率（以是否外接电源作为门控）；从子页返回主界面时立即刷新，不再沿用最长 60 秒的旧数据；`get_conf` 无已知键时视为失败，不把默认 80/20/40/35 当作已确认配置展示。
- **其他修复**：写配置按实时配置校验并加空键值保护；高级页开关在首次确认读取前禁用；诊断导出改用真实电池数据；进入旧版页时恢复导航栏以显示返回按钮，返回新版页时恢复隐藏；语言切换不再把“未读取”误标为“本地缓存”；应用内旧配置迁移补回旧配置文件名；设置束增加阈值对交叉校验（降温恢复须低于高温停充，开始充电须低于停止充电）；新界面滑块补 TouchCancel 处理；roothide 的 postinst/prerm 的 jbroot 路径解析与守护进程 bundle ID 统一修复；新目录已存在非空但缺新名配置时，也从旧目录补拷配置；卸载报错前缀、README 下载表、postinst 迁移缺口（旧配置改名、旧作业停掉、复制后二次修权限）均已按审阅意见修复。

### 6. 保持不变

- **守护进程停充核心不变**：`daemon.mm` 与旧版的差异仅为标识与路径字符串（通知名、launchctl 标签、plist 路径、二进制名），无逻辑改动。
- **定值与滑块语义不变**：停止充电 80%、开始充电 20%、高温停充 40°C、降温恢复 35°C；滑块范围为停止 15–100、开始 10–95、高温 30–50、降温 25–49；拖动滑块松手后写一次，拖动过程中不再每步写守护进程。
- **判定标准不变**：电池兼容性测试 5mA 严标准、守护进程日常 120mA 标准不变；软件停充不是物理断电，个别设备停充后仍有几十毫安（约 85mA）残留电流属于正常软停，不是本版 bug，也未宣称已修到 0mA。
- **其他不变项**：URL Scheme `cl` 不变；在线更新与帮助地址为 xstar68/ChargeGuard；停充、限流、温度、档位、满充计划、系统优化充电的逻辑与默认值不变。

### 尚未验证与已知限制

- Xcode 构建（3 个应用目标 + 3 个守护进程目标）、Theos 设置束构建、真机安装与设置入口、80% 停充与温度控制回归、兼容性测试、在线更新、迁移后配置仍在，均尚未在真机上验证；Linux 本地测试不能替代上述验证，发布前须逐项验收。
- 新界面页面字符串目前为硬编码中文，英文系统语言下新页面仍显示中文，旧页面仍为中英双语；英文本地化为后续任务。
- 旧版回退路径保留：若新主界面在真机上有问题，可把根内容换回旧版主控制器。

## 这是什么

- 打开就是新主界面：大电量状态卡、实时数据卡、一键预设、更多功能入口，不再是旧版长列表。
- 停充：电量达到设定值就停止充电；禁流、限流、插电保持、满充计划、温度控制、系统优化充电协调都在充电高级里。
- 默认值：停止充电 80%、高温停充 40°C、降温恢复 35°C、开始充电 20%。
- 注意：软件停充不是物理断电，个别设备停充后仍有几十毫安残留电流属于正常软停，不是 bug。
- 最低 iOS 13.0；需要 TrollStore 或越狱环境，无法上架 App Store，也无法用常规自签安装。

## 下载安装

下载：<https://github.com/xstar68/ChargeGuard/releases>

| 环境 | 产物 |
| --- | --- |
| TrollStore | `ChargeGuard_<版本>_TrollStore.tipa` |
| 越狱 rootful | `ChargeGuard_<版本>_rootful_arm.deb` |
| 越狱 rootless | `ChargeGuard_<版本>_rootless_arm64.deb` |
| 越狱 roothide | `ChargeGuard_<版本>_roothide_arm64e.deb` |

- deb 版只安装在系统设置里，桌面不留图标；TrollStore 的 tipa 仍留在桌面。
- deb 版安装新版会自动顶掉旧包（`com.chargelimiter.mod`），并把旧配置目录迁移到新目录，旧目录会保留作回退。
- TrollStore 环境安装新版前请先卸载旧版。
- 装完先做一件事：打开设置里的 ChargeGuard，确认 80% 停充、温度控制、高级开关都能正常打开和保存，再正常使用。

## 基本使用

1. 主界面确认当前状态：正在充电 / 已连接电源 · 停止充电 / 温控暂停充电 / 插电保持中。
2. 拖动“停止充电”滑块设上限，松手后写一次；温度控制开关打开后，设置高温停充和降温恢复。
3. 充电高级里按需开：智能停充、停充时禁流、插电保持、满充计划、高温模拟 / 充电限流。
4. 历史统计看 5 分钟 / 小时 / 天 / 月曲线；策略诊断看当前为什么停充或恢复充电。
5. 自动化可用 URL Scheme：`cl:///` 打开，`cl:///charge` 启用充电，`cl:///nocharge` 停用充电。

## 从源码构建

```bash
./scripts/build_packages.sh
```

产物在 `out/`，命名同上表。单独验证编译：

```bash
xcodebuild -project ChargeGuard.xcodeproj -scheme "ChargeGuard" -destination "generic/platform=iOS" -configuration Release -derivedDataPath build_rootful CODE_SIGNING_ALLOWED=NO ARCHS=arm64
xcodebuild -project ChargeGuard.xcodeproj -scheme "ChargeGuard rootless" -destination "generic/platform=iOS" -configuration Release -derivedDataPath build_rootless CODE_SIGNING_ALLOWED=NO ARCHS=arm64
xcodebuild -project ChargeGuard.xcodeproj -scheme "ChargeGuard roothide" -destination "generic/platform=iOS" -configuration Release -derivedDataPath build_roothide CODE_SIGNING_ALLOWED=NO ARCHS=arm64 THEOS_PACKAGE_SCHEME=roothide
```

详细构建说明见 [构建安装包.md](构建安装包.md)，版本历史见 [CHANGELOG.md](CHANGELOG.md)。

问题反馈请前往 [Issues](https://github.com/xstar68/ChargeGuard/issues)。

基于 lich4 与 tunecc 的工作更新维护。

---

## Introduction

**English · [中文](#chargeguard)**

ChargeGuard (CG for short) is a charging-control tool for iPhone: stop charging at the capacity you set, avoid hot full charges, and extend battery life. It is software-level charging-policy control, not hardware bypass charging. The repository is xstar68/ChargeGuard and the app, package, daemon, and data identifiers are all ChargeGuard; the source directory, class prefixes, and the URL scheme `cl` remain technical internal identifiers and do not affect use.

## What is new in v3.0

v3.0 is a full rebuild of v2.0, not a rename-only update. The items below are grouped the same way as the Chinese section; items not yet verified on Xcode or a real device are listed under “Not yet verified” and are not claimed as done.

### 1. New interface

- **Main screen**: a gradient hero card with large capacity percentage, charging state, and mode/adapter pills; a two-column live data grid for current, voltage, temperature, and health; the former single-column info rows are merged into the hero state area and the data grid.
- **More functions**: changed from a single-column list to a 2×2 grid of large entry cards for History, Compatibility Test, Advanced, and Software Settings.
- **History page**: capsule filters (5 minutes / hourly / daily / monthly) and a coloured strategy-event timeline, with time, transition, reason, and values on separate lines.
- **Compatibility test page**: conclusions as large cards at the top, with judgement current and elapsed time in the same card; an unrun test honestly shows “not run”.
- **Advanced page**: grouped cards for stop control, thermal simulation / charging limit, Optimized Battery Charging, and full-charge schedule, with switches on the right.
- **Software Settings page**: version card, update, diagnostics export, and automation entries. The Help page keeps the v2.0 single-link design. Every new sub-page keeps an “open full legacy page” entry; no existing function was removed, and the legacy main controller remains in the package as a fallback, but the new main screen is the default on open.

### 2. New architecture

- Layered as `CGConfig` (configuration model) → `CGDaemonClient` (daemon client) → `CGBatteryViewModel` (view model) → `CGViews` / `CGMainViewController` / `CGSubPages` (views), under `ChargeLimiter/UIKit/ChargeGuard/`.
- `CGDaemonClient` is the views’ only daemon interface, wrapping the existing `CLAPIClient` protocol on `127.0.0.1:1230` (`get_conf` / `set_conf`); views no longer call the daemon directly.
- `CGBatteryViewModel` is pure derivation, with no UIKit or daemon calls; all writes pass `CGConfig` validation first, and invalid thresholds are rejected locally.
- This release remains a layered UIKit architecture, **not a SwiftUI migration**. A SwiftUI migration was not done in this release because it cannot be verified without Xcode; the model and view model are decoupled from UIKit to allow a later migration.

### 3. New features

All features use data the daemon already provides; no hardware feature was invented, and read-only features do not write configuration:

- **History trends**: charging speed (%/hour), longest continuous charging, and temperature summaries across 5-minute / hourly / daily / monthly ranges; an explicit “no samples yet” state when there is no data.
- **Smart full-charge suggestion**: a text-only estimate of when to start charging before wake time, based on current charging speed; it does not change configuration by itself.
- **Temperature and health alerts, cycle forecast**: an alert when health is below 80%, and an estimate of months to 1000 cycles.
- **One-tap presets**: Daily 80%, Longevity 60%, Travel 100%; tapping applies the preset by changing only the stop-charge value, with rollback on failure.
- **Diagnostics export**: a plain-text report with configuration snapshot, battery data, diagnostics, and analysis summary, shareable without changing configuration; no empty report is shared on failure.
- **Automation links**: `cl:///` to open, `cl:///charge` to enable charging, and `cl:///nocharge` to stop charging, copyable from Software Settings.

### 4. Full rename and Settings-only deb

| Old identifier | New identifier |
| --- | --- |
| Package `com.chargelimiter.mod` | `com.chargeguard` |
| Bundle ID `com.chargelimiter.mod` | `com.chargeguard` |
| App folder `ChargeLimiter.app` | `ChargeGuard.app` |
| Daemon `ChargeLimiterDaemon` | `ChargeGuardDaemon` |
| Data directory `/var/mobile/ChargeLimiter` | `/var/mobile/ChargeGuard` |
| Launch item `com.chargelimiter.mod.plist` | `com.chargeguard.plist` |
| Daemon location in deb | `/usr/libexec/ChargeGuardDaemon` (`/var/jb/usr/libexec` on rootless) |
| Download filename `ChargeLimiter_<version>_…` | `ChargeGuard_<version>_…` |

- **Deb Settings-only, actually usable**: deb packages no longer install a `.app` on the home screen; the daemon goes to `libexec`, the Settings bundle goes to `PreferenceBundles/ChargeGuardSettings.bundle` (with rootless/roothide paths as applicable), and a PreferenceLoader entry `ChargeGuard.plist` is included so the entry really appears in Settings. The Settings controller is a full implementation (POST JSON `get_conf` → switch/slider cells → `set_conf` with rollback, no values shown offline, no NSUserDefaults), with a new Info.plist and Theos Makefile; if Theos cannot build the bundle, the deb build fails fast instead of shipping a package with no UI.
- **TrollStore tipa stays on the home screen**; only the deb is Settings-only.
- **Migration (deb)**: the new package replaces the old one via `Conflicts` / `Replaces: com.chargelimiter.mod`, not side-by-side; on install, if the old data directory exists and the new one is missing or empty, its contents are copied to the new directory, an old-named config file is renamed when the new-named file is missing, the old daemon job is explicitly stopped before the new job starts, and permissions are repaired again after copying; **the old directory is never deleted**. TrollStore users get a new app container because the Bundle ID changed, so configuration must be set again; directory migration does not apply to the tipa container.
- **Repository**: update and help addresses are xstar68/ChargeGuard; the Xcode project is now `ChargeGuard.xcodeproj`, with targets and schemes renamed accordingly.

### 5. Fixes and optimisations

Verified fixes from the report, grouped by area:

- **Build blockers**: rootful app target `PRODUCT_NAME` unified to ChargeGuard; rootless launch plist daemon path fixed from a doubled `/var/jb/var/jb/…` prefix to a single prefix; rootful daemon target entitlements path fixed to an existing file; the missing PreferenceLoader entry for the Settings bundle was added, otherwise a Settings-only deb would install with no visible entry.
- **Functional key fix**: the Advanced “smart stop” switch previously wrote `use_smart`, which the daemon silently ignores as a runtime detection value; it now reads and writes the effective key `adv_predictive_inhibit_charge`, with `use_smart` kept read-only for diagnostics.
- **History fixes**: previously an empty statistics request returned no data; it now explicitly requests the four ranges; capsule filtering previously did not affect the calculation and now selects the bucket; temperature raw values above 200 are divided by 100 to avoid showing about 2850°C; the temperature limit now uses the live `tempAbove` value instead of a hardcoded 40.
- **Configuration writes**: previously every change wrote all 7 keys, which could trigger daemon side effects on unrelated keys; writes are now diff-only against the previous configuration (full write only when there is no previous configuration), and rollback on failure covers only keys already written.
- **Write honesty and races**: writes are serialised while one is in flight; on failure the UI redraws from the captured previous configuration and shows the real error, local validation rejections are no longer presented as daemon rejections, and a failed rollback explicitly says rollback did not fully succeed and refetches the true configuration.
- **State and refresh**: when unplugged, the UI no longer shows “stopped” or fake adapter power (gated on external connection); returning from a sub-page refreshes immediately instead of showing data up to 60 seconds stale; an empty `get_conf` response is treated as failure instead of presenting the 80/20/40/35 defaults as confirmed configuration.
- **Other fixes**: writes are validated against the live configuration with nil-key/value guards; Advanced switches are disabled until the first confirmed read; diagnostics export uses real battery data; entering a legacy page restores the navigation bar so a back button is visible, and returning restores hiding; language switching no longer mislabels “not read” as “local cache”; in-app legacy migration recognises the old plist filename; the Settings bundle cross-validates threshold pairs (resume below stop, start below stop); new-interface sliders handle TouchCancel; roothide postinst/prerm jbroot path parsing and daemon bundle ID were unified; a non-empty new directory missing the new-named config also gets the config copied from the old directory; uninstall error prefixes, the README download table, and postinst migration gaps (old config rename, old job stop, permission repair after copying) were fixed as reviewed.

### 6. Unchanged

- **Daemon stop core unchanged**: the `daemon.mm` difference from the old version is only identifier and path strings (notification names, launchctl labels, plist paths, binary name), with no logic change.
- **Setpoints and slider semantics unchanged**: stop 80%, start 20%, over-temp stop 40°C, cool-down resume 35°C; slider ranges stop 15–100, start 10–95, over-temp 30–50, cool-down 25–49; sliders write once on release, not on every step during dragging.
- **Test standards unchanged**: compatibility test 5mA strict standard and daemon daily 120mA standard are unchanged; software stop is not a physical disconnect, and a residual current of tens of milliamps (about 85mA) on some devices after stopping is a normal soft stop, not a bug in this release, and is not claimed to be fixed to 0mA.
- **Other unchanged items**: URL scheme `cl` is unchanged; update and help addresses are xstar68/ChargeGuard; charging, limiting, temperature, gear, full-charge schedule, and Optimized Battery Charging logic and defaults are unchanged.

### Not yet verified and known limitations

- Xcode builds (3 app targets + 3 daemon targets), Theos Settings-bundle builds, real-device installation and Settings entry, 80% stop and temperature-control regression, compatibility tests, updates, and post-migration configuration persistence have not yet been verified on a real device; Linux local tests do not substitute for that verification, and each item must be checked before release.
- New-interface pages currently use hardcoded Chinese strings; under an English system language the new pages still show Chinese, while legacy pages remain bilingual. English localisation is a follow-up task.
- The legacy fallback path is retained: if the new main screen has a problem on a real device, the root content can be switched back to the legacy main controller.

## What it is

- A new main screen on open: a large capacity status card, live data cards, one-tap presets, and feature entries — not the old long list.
- Stop charging at your set limit; disable inflow, limit inflow, plug-in hold, full-charge schedule, temperature control, and Optimized Battery Charging coordination are in Advanced.
- Defaults: stop charging 80%, over-temp stop 40°C, cool-down resume 35°C, start charging 20%.
- Note: software stop is not a physical disconnect. A residual current of tens of milliamps on some devices after stopping is a normal soft stop, not a bug.
- Requires iOS 13.0 or later, plus TrollStore or a jailbreak. It cannot be on the App Store and cannot be installed with a regular sideload.

## Download and install

Download: <https://github.com/xstar68/ChargeGuard/releases>

| Environment | Package |
| --- | --- |
| TrollStore | `ChargeGuard_<version>_TrollStore.tipa` |
| Jailbreak rootful | `ChargeGuard_<version>_rootful_arm.deb` |
| Jailbreak rootless | `ChargeGuard_<version>_rootless_arm64.deb` |
| Jailbreak roothide | `ChargeGuard_<version>_roothide_arm64e.deb` |

- The deb installs only in system Settings, with no home-screen icon; the TrollStore tipa stays on the home screen.
- The deb replaces the old package (`com.chargelimiter.mod`) and migrates the old config directory to the new one; the old directory is kept as a fallback.
- On TrollStore, uninstall the old version before installing a new one.
- After installing, first check that the 80% stop, temperature control, and Advanced switches open and save normally in Settings.

## Basic use

1. Check the current state on the main screen: charging / plugged in · stopped / paused by temperature / holding.
2. Drag the stop-charging slider to your limit; it writes once on release. Turn on temperature control, then set the over-temp stop and cool-down resume values.
3. In Advanced, enable as needed: smart stop, disable inflow on stop, plug-in hold, full-charge schedule, thermal simulation / charging limit.
4. History shows 5-minute / hourly / daily / monthly charts; Policy diagnostics shows why charging stopped or resumed.
5. Automation via URL scheme: `cl:///` opens the app, `cl:///charge` enables charging, `cl:///nocharge` stops charging.

## Build from source

```bash
./scripts/build_packages.sh
```

Packages land in `out/` with the names in the table above. Verify a single build with:

```bash
xcodebuild -project ChargeGuard.xcodeproj -scheme "ChargeGuard" -destination "generic/platform=iOS" -configuration Release -derivedDataPath build_rootful CODE_SIGNING_ALLOWED=NO ARCHS=arm64
xcodebuild -project ChargeGuard.xcodeproj -scheme "ChargeGuard rootless" -destination "generic/platform=iOS" -configuration Release -derivedDataPath build_rootless CODE_SIGNING_ALLOWED=NO ARCHS=arm64
xcodebuild -project ChargeGuard.xcodeproj -scheme "ChargeGuard roothide" -destination "generic/platform=iOS" -configuration Release -derivedDataPath build_roothide CODE_SIGNING_ALLOWED=NO ARCHS=arm64 THEOS_PACKAGE_SCHEME=roothide
```

See [构建安装包.md](构建安装包.md) for build details and [CHANGELOG.md](CHANGELOG.md) for version history.

Report issues at [Issues](https://github.com/xstar68/ChargeGuard/issues).

Based on the work of lich4 and tunecc.
