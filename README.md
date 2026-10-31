<p align="center">
  <img src="docs/assets/chargeguard-icon-1024.png" alt="ChargeGuard" width="128">
</p>

<h1 align="center">ChargeGuard</h1>

<p align="center">
  <strong>Charge smarter. Keep your battery young.</strong><br>
  充得聪明，电池更年轻。
</p>

<p align="center">
  <a href="#installation">安装</a> ·
  <a href="#usage">快速上手</a> ·
  <a href="#configuration">配置</a> ·
  <a href="#faq">常见问题</a> ·
  <a href="https://github.com/xstar68/ChargeGuard/issues">Issues</a>
</p>

<p align="center">
  iOS 13+ · TrollStore · Jailbreak · GPL-3.0
</p>

---

## Why ChargeGuard / 为什么需要它

Batteries age fastest at two extremes: sitting at 100% for hours, and charging while hot. Most phones do little about either. ChargeGuard gives you a simple, practical answer: set a ceiling, guard the temperature, and let the phone stop when it should — in software, with no hardware bypass and no special charger.

电池老化最快的两个场景，是长时间满电和高温下充电。ChargeGuard 的做法很直接：设一个上限、守住温度，到点就停。它在软件层面控制充电策略，不需要硬件旁路，也不需要专用充电器。

> ChargeGuard is a charging-control tool for iPhone. It decides where charging stops, so your battery is not left full or charged while hot.

## In short / 一句话概括

ChargeGuard lets your iPhone stop charging at a limit you choose and pause when it gets hot — so the battery spends less time full and hot, and lasts longer. Set it once, and it takes care of the rest.

ChargeGuard 让你的 iPhone 在你设定的电量停下来、温度高了暂停充电——让电池少满电、少受热，自然用得更久。设好一次，剩下的交给它。

## Design principles / 设计原则

- **默认即合理**：装好就能用，80% 上限、40°C / 35°C 温控都是开箱即用的默认值，不用先读一遍说明书。
- **只在必要时干预**：平时不打扰你，只有停充、温控暂停、恢复充电这些状态变化时，才在界面上说清楚原因。
- **改动可预期**：滑块松手才保存，预设一键切换且失败会回滚，不会出现改了设置却不知道有没有生效的情况。
- **不夸大效果**：软件停充不是物理断电，残留电流会如实说明；能做到的写清楚，做不到的不承诺。

## How it works / 工作原理

ChargeGuard 由两部分组成：一个常驻的守护进程按你的配置接管充电状态，一个应用负责展示与配置。你在应用里改的每一项设置，都会同步到守护进程；即使应用没有打开，守护进程仍会按最后保存的配置工作。插上充电器后，它会实时看电量、温度和充电状态：到了上限就停，温度高了就暂停，条件恢复了就继续——你不需要每次插电都手动干预。

## Who it's for / 适合谁

- 长期插电使用 iPhone 的人：守住上限，电池不必整天满电待命。
- 注重电池寿命的人：把日常上限设在 80% 左右，是最省事的保养方式。
- 经常出差、旅行的人：平时用上限保护电池，出行前用满充计划充到满电，两者不用手动来回切换。

## Requirements / 使用条件

- iPhone，iOS 13.0 或更高版本。
- TrollStore 或越狱环境（二者选一即可）。
- 不需要 App Store，不需要特殊充电器，不需要网络服务。

## Preview / 界面预览

下图为界面设计预览，按设计稿绘制，不是真机截图；真机截图待真机测试后补充。

| 主界面 | 更多功能 | 历史统计 |
| --- | --- | --- |
| <img src="docs/assets/preview-main.png" alt="ChargeGuard 主界面设计预览" width="240"> | <img src="docs/assets/preview-entries.png" alt="ChargeGuard 更多功能设计预览" width="240"> | <img src="docs/assets/preview-history.png" alt="ChargeGuard 历史统计设计预览" width="240"> |

## Features / 功能

- **电量上限，充到就停** — 设定上限，到了就停，不再一路充到 100%。默认 80%，可按需要调整。
- **温度守护** — 过热暂停充电，降温后再恢复。默认高温停充 40°C、降温恢复 35°C。
- **智能停充** — 优先系统级停充，失效时自动回退；也可选择停充时禁流、按档位限流。
- **插电保持** — 在上限附近维持一个缓冲区间，适合长期插电使用的设备。
- **满充计划** — 平时守住上限，出行前按计划临时解除、充到满电，用完自动回到日常上限。
- **历史与诊断** — 按 5 分钟、小时、天、月查看充电曲线与温度变化；策略诊断会说明当前为什么停充或恢复充电。
- **兼容性测试** — 帮你确认这台设备是否支持停充、智能停充与禁流。
- **一键预设与自动化** — 日常、长寿、出行预设一键切换；诊断报告一键导出；支持快捷指令与自动化链接。

## Installation / 安装

下载：<https://github.com/xstar68/ChargeGuard/releases>

| 环境 | 产物 |
| --- | --- |
| TrollStore | `ChargeGuard_<版本>_TrollStore.tipa` |
| 越狱 rootful | `ChargeGuard_<版本>_rootful_arm.deb` |
| 越狱 rootless | `ChargeGuard_<版本>_rootless_arm64.deb` |
| 越狱 roothide | `ChargeGuard_<版本>_roothide_arm64e.deb` |

deb 版只出现在系统设置里，桌面不留图标；tipa 版留在桌面，打开即用。

## Usage / 快速上手

1. 打开 ChargeGuard，确认当前状态：正在充电、已停充、温控暂停，还是插电保持中。
2. 拖动上限滑块设好停充值，松手即保存；打开温度控制，设好高温停充与降温恢复。
3. 需要时在充电高级里打开智能停充、禁流、限流或满充计划。
4. 想了解充电过程时，查看历史统计与策略诊断。

## Configuration / 主要配置

| 设置 | 默认值 | 说明 |
| --- | --- | --- |
| 停止充电 | 80% | 电量到达该值时停止充电 |
| 开始充电 | 20% | 电量回落到该值附近时恢复充电 |
| 高温停充 | 40°C | 电池温度到达该值时暂停充电 |
| 降温恢复 | 35°C | 电池温度回落到该值时恢复充电 |

## What it does not do / 不承诺的事

- 不承诺把停充后的残留电流降到 0mA：软件停充不是物理断电，残留是正常现象。
- 不承诺让电池永不老化：它能做的是减少满电和高温这两个最伤电池的习惯，延缓老化，而不是逆转它。
- 不替代系统电池健康管理：它与系统优化充电协调工作，而不是绕过系统。
- 不需要、也不收集你的任何个人数据：所有配置与历史都只存在本机。

## FAQ / 常见问题

**停充后为什么还有几十毫安电流？**
这是软件停充的正常现象，不是物理断电，残留电流属于软停，不代表停充失效。

**没有越狱的 iPhone 能用吗？**
不能。ChargeGuard 需要 TrollStore 或越狱环境，无法上架 App Store，也无法用常规自签安装。

**需要代理节点或特殊网络吗？**
不需要。它只控制本机充电，不依赖任何代理或网络服务。

## Contributing / 反馈

问题反馈请前往 [Issues](https://github.com/xstar68/ChargeGuard/issues)。

从源码构建：

```bash
./scripts/build_packages.sh
```

产物在 `out/`，命名同上表。详细构建说明见 [构建安装包.md](构建安装包.md)，版本历史见 [CHANGELOG.md](CHANGELOG.md)。

## License / 许可与致谢

Licensed under GPL-3.0. See [LICENSE](LICENSE).

Based on the work of lich4 and tunecc.
