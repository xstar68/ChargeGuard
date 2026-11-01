# ChargeGuard 设置版（deb 专用，ipa 排除）

## 目标
越狱 deb 版（rootful / rootless / roothide）只进系统设置，不再留桌面图标；
TrollStore 的 ipa 版仍留在桌面，继续用现有 UIKit 应用。

## 为什么不能用普通偏好设置写法
守护进程的配置不是 NSUserDefaults。守护进程读的是本地 KV 存储
（CLSettingsStore，`com.chargeguard.plist`），应用侧通过
`http://127.0.0.1:1230` 的 `get_conf` / `set_conf`（键 `charge_above`、
`charge_temp_above`、`charge_temp_below`、`enable`、`enable_temp` 等）读写。
如果设置版用 PreferenceLoader 的普通 PSSwitchCell / PSSliderCell + defaults
域写入，值只会进 NSUserDefaults，守护进程根本读不到——这是 v2.0 必须
避开的假实现。本 bundle 因此不走 defaults 写入。

## 实现方式（Theos 单独编译，不进 Xcode 工程）
- 入口：`Library/PreferenceBundles/ChargeGuardSettings.bundle`
  （rootless 为 `/var/jb/Library/PreferenceBundles/...`，
  roothide 为 jbroot 相对路径；rootful 为 `/Library/PreferenceBundles/...`）。
  `Root.plist` 只声明入口（label `ChargeGuard`、图标、控制器类
  `CLChargeGuardPrefsController`），不声明任何 defaults 键。
- 控制器：`CLChargeGuardPrefsController.m`（本目录，PSListController 子类，
  Preferences 框架）。打开时先 `GET get_conf` 取当前值并显示；
  开关 / 滑块变化时 `POST set_conf`（`key` + `val`），成功后才更新界面，
  失败时弹提示并回滚显示值；守护进程离线时只读显示、写入被禁用并提示，
  不写本地假值。定值含义与应用完全一致：停止 ≥80%（默认）、高温 40°C、
  降温 35°C，键名不变。
- 打包：deb 构建时把本 bundle 装到上述 PreferenceBundles 路径，
  并且不要把 `Applications/ChargeGuard.app` 装进 deb；
  ipa（TrollStore）构建排除本 bundle，只装 `.app`。
  本目录的控制器未加入 `ChargeGuard.xcodeproj`，避免 Xcode 构建
  因 Preferences / Theos 头文件缺失而失败；deb 打包步骤需在 macOS +
  Theos 环境单独验证（见主报告“未验证”清单）。

## 与应用的关系
设置版与应用是同一套接口的两种外壳：应用（ipa）+ 设置版（deb）
共享守护进程、键名、定值、120mA 守护进程标准与 5mA 测试标准；
两者不同时装在同一台设备上，deb 装机时应先卸载旧版桌面应用。


## v3.0 状态（2026-10-29，本地，未经设备验证）
- 控制器已由骨架改为完整实现：get_conf（POST JSON，与 CLAPIClient 一致）后建 PSSwitchCell/PSSliderCell，set_conf 写回、失败回滚、离线不显示数值、不写 NSUserDefaults。
- 新增 `Info.plist`（bundle id com.chargeguard.settings）与 Theos `Makefile`；deb 打包时 `scripts/build_packages.sh` 的 `stage_settings_bundle` 会尝试 Theos 编译，编不出则整个 deb 构建直接失败（不静默发无 UI 的包）。
- 仍未验证（无 Xcode/设备）：Theos 编译是否一次通过、设置里入口是否出现、开关/滑块往返是否生效。见主报告 `REPORT_V3_0.md` 的设备验收清单。
