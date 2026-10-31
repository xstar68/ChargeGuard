# ChargeGuard

中文 · **[English](#introduction)**

ChargeGuard（充电守卫）是一款面向 iPhone 的充电控制工具。它做的事很简单：让你决定充到多少就停，别让电池长期满电、高温满充，从而延长电池寿命。它是软件层面的充电策略控制，不是硬件旁路充电。

## 界面介绍

<img src="docs/assets/chargeguard-icon-1024.png" alt="ChargeGuard 图标" width="120">

下图为**新界面设计预览**（按界面设计稿绘制，不是真机截图；真机截图待真机测试后补充）：

| 主界面 | 更多功能 | 历史统计 |
| --- | --- | --- |
| <img src="docs/assets/preview-main.png" alt="ChargeGuard 主界面设计预览" width="240"> | <img src="docs/assets/preview-entries.png" alt="ChargeGuard 更多功能设计预览" width="240"> | <img src="docs/assets/preview-history.png" alt="ChargeGuard 历史统计设计预览" width="240"> |

## 功能

**电量上限，充到就停。** 设定一个上限，电量到了就停止充电，不再一路充到 100%。默认 80%，可按需要调整；插电保持可在上限附近维持一个缓冲区间，适合长期插电使用。

**温度守护，高温不停工。** 电池过热时暂停充电，温度回落后再恢复，默认高温停充 40°C、降温恢复 35°C。高温、满充这两个最伤电池的场景，都由它来挡。

**停充更聪明，充电更温和。** 智能停充会优先用系统级停充，失效时自动回退；也可选择停充时禁流、按档位限流，并与系统优化充电协调工作，让充电节奏更贴合你的使用习惯。

**满充计划，需要时再满。** 平时守住上限，出行前可按计划临时解除上限、充到满电，用完自动回到日常上限，不用每次手动改来改去。

**了解你的电池。** 历史统计按 5 分钟、小时、天、月呈现充电曲线与温度变化；策略诊断会告诉你当前为什么停充或恢复充电；电池兼容性测试能帮你确认这台设备是否支持停充、智能停充与禁流。

**省心预设与自动化。** 日常、长寿、出行一键预设，点一下就切换到合适的上限；诊断报告可一键导出，便于排查问题；也支持快捷指令与自动化链接，打开、启用充电、停用充电都可一键触发。

**两种形态，随你安装。** 越狱设备装 deb 版，只出现在系统设置里，桌面不留图标；TrollStore 设备装 tipa 版，留在桌面打开即用。最低支持 iOS 13.0，无法上架 App Store，也无法用常规自签安装。

## 下载安装

下载：<https://github.com/xstar68/ChargeGuard/releases>

| 环境 | 产物 |
| --- | --- |
| TrollStore | `ChargeGuard_<版本>_TrollStore.tipa` |
| 越狱 rootful | `ChargeGuard_<版本>_rootful_arm.deb` |
| 越狱 rootless | `ChargeGuard_<版本>_rootless_arm64.deb` |
| 越狱 roothide | `ChargeGuard_<版本>_roothide_arm64e.deb` |

装完先确认一件事：打开 ChargeGuard，检查上限、温度控制与高级开关都能正常打开和保存，再正常使用。

## 基本使用

1. 主界面确认当前状态：正在充电、已停充、温控暂停，还是插电保持中。
2. 拖动上限滑块设好停充值，松手即保存；打开温度控制，设好高温停充与降温恢复。
3. 需要时在充电高级里打开智能停充、禁流、限流、满充计划。
4. 想了解充电过程时，看历史统计与策略诊断。
5. 想自动化时，用链接打开应用、启用充电或停用充电。

## 从源码构建

```bash
./scripts/build_packages.sh
```

产物在 `out/`，命名同上表。详细构建说明见 [构建安装包.md](构建安装包.md)，版本历史见 [CHANGELOG.md](CHANGELOG.md)。

问题反馈请前往 [Issues](https://github.com/xstar68/ChargeGuard/issues)。

基于 lich4 与 tunecc 的工作更新维护。

---

## Introduction

**English · [中文](#chargeguard)**

ChargeGuard is a charging-control tool for iPhone. It does one thing well: it lets you decide where charging stops, so your battery is not left at a full charge or charged while hot — the two habits that wear a battery out fastest. It works at the software level, shaping how charging behaves, not by bypassing the battery in hardware.

## Features

**A limit that actually stops charging.** Set a ceiling and charging stops when it is reached, instead of drifting to 100%. The default is 80% and adjustable; plug-in hold keeps the level in a comfortable band around your limit, which suits devices left plugged in for long periods.

**Temperature protection that steps in quietly.** Charging pauses when the battery gets hot and resumes once it has cooled, by default stopping at 40°C and resuming at 35°C.

**Smarter stopping, gentler charging.** Smart stop prefers the system-level stop and falls back automatically when needed. You can also disable inflow while stopped, limit charging current by gear, and let the tool coordinate with Optimized Battery Charging.

**A full-charge plan for when you need it.** Keep your everyday limit most of the time, and let a schedule temporarily lift it before a trip, returning to the limit afterwards — no manual toggling each time.

**Know your battery.** History charts span 5 minutes, hours, days, and months, with temperature alongside. Policy diagnostics explain why charging stopped or resumed. A compatibility test tells you whether your device supports stop, smart stop, and inflow blocking.

**Presets and automation that save effort.** Daily, Longevity, and Travel presets switch your limit in one tap. A diagnostics report can be exported when something needs checking. Shortcuts and automation links can open the app, enable charging, or stop charging.

**Two forms, your choice.** On a jailbroken device, the deb version lives only in Settings, with no home-screen icon. On TrollStore, the tipa version stays on the home screen. It requires iOS 13.0 or later, cannot be listed on the App Store, and cannot be installed with a regular sideload.

## Download and install

Download: <https://github.com/xstar68/ChargeGuard/releases>

| Environment | Package |
| --- | --- |
| TrollStore | `ChargeGuard_<version>_TrollStore.tipa` |
| Jailbreak rootful | `ChargeGuard_<version>_rootful_arm.deb` |
| Jailbreak rootless | `ChargeGuard_<version>_rootless_arm64.deb` |
| Jailbreak roothide | `ChargeGuard_<version>_roothide_arm64e.deb` |

After installing, first check that the limit, temperature control, and Advanced switches open and save normally, then use it as usual.

## Basic use

1. Check the main screen: charging, stopped, paused by temperature, or holding.
2. Drag the limit slider to your ceiling; it saves on release. Turn on temperature control and set its stop and resume values.
3. In Advanced, enable smart stop, inflow blocking, current limiting, or a full-charge schedule as needed.
4. For insight, open History and Policy diagnostics.
5. For automation, use the links to open the app, enable charging, or stop charging.

## Build from source

```bash
./scripts/build_packages.sh
```

Packages land in `out/` with the names in the table above. See [构建安装包.md](构建安装包.md) for build details and [CHANGELOG.md](CHANGELOG.md) for version history.

Report issues at [Issues](https://github.com/xstar68/ChargeGuard/issues).

Based on the work of lich4 and tunecc.
