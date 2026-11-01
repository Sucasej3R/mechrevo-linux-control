# mechrevo-linux-control

**机械革命（Uniwill 准系统）游戏本的 Linux 控制台** —— 在 Arch / CachyOS 与 Ubuntu 上实现性能模式、独显功耗解锁、风扇强冷、键盘 RGB、电池限充与平台硬件开关。

> 本仓库基于 [ss12wzh/mechrevo-linux-control (v3.4.3)](https://github.com/ss12wzh/mechrevo-linux-control) 二次修改，重点补齐了 **机械革命 苍龙 16X Pro**（ITE 8291 键盘灯、9955HX + 5070 Ti 档案）与 **Arch / KDE Plasma Wayland** 环境适配，并修复了上游 GUI 的高占用 Bug。

| 概览 | 控制 |
|---|---|
| ![概览](mrv-ctl/assets/ui-preview.png) | ![控制](mrv-ctl/assets/ui-preview-controls.png) |

---

## 二改内容（v3.5.0）

相比上游 `v3.4.3`，主要改动如下：

1. **支持 ITE 8291 (`048d:600b`) 键盘灯**：苍龙 16X Pro 等机型使用 ITE 8291 USB HID 控制器，写 `uniwill_laptop` 的 sysfs 无效。`mrvd.py` 新增 `/dev/hidraw*` 原生驱动，支持亮度调节、单色 RGB、硬件彩虹动画和关灯；无此芯片的机型自动回退原 sysfs 接口。
2. **修复 GUI 点击按钮后单核 100% CPU 死循环**：原版 `mrv-gui` 在 `_send()` 中调用 `GLib.idle_add(self.refresh)`，因 `refresh()` 返回 `True`，点击任意按钮后主循环会无限空转并每秒新建约 7 个后台线程轮询 `mrvd`。现已改为单次执行即销毁。
3. **KDE Plasma Wayland 适配**：`mrv-gui` 默认走 `GDK_BACKEND=x11`，去掉 KDE Wayland 强加的原生外层标题栏；新增单实例唤醒（`/run/user/<uid>/mrv-gui.sock`），重复启动时直接唤出已有窗口。
4. **状态持久化与睡眠恢复**：开机及 S3/S0ix 睡眠唤醒后自动恢复性能档位、充电阈值、键盘灯与全部 4 项 INOU 硬件开关；修复离电自动关灯在 ITE 8291 上不生效、离电时 EC `0x0751` 返回 `0x20` 被误判为 `custom(0x20)`、以及关灯后丢失上次亮度记忆的问题。
5. **机型档案与细节补齐**：新增 **苍龙 16X Pro**（R9 9955HX + RTX 5070 Ti）档案；修复 `/opt/mrv/models.json` 路径读取；GUI 控制页开放“触控板开关”；修复滑条滚轮/点击防抖及切档后 GPU 功耗上限刷新延迟。

---

## 优缺点

**优点**
- **直接走硬件通道**：通过 ACPI `\_SB.AMW0.WKBC`、EC 寄存器、`uniwill_laptop`、`hidraw` 和 `nvidia-powerd` 工作，不改内核、不改 NVIDIA 闭源驱动。
- **不干预内核调度器**：切档只写 EC `0x0751` 并联动 `amd-pstate-epp`（静音档关睿频压制 9955HX 单核积热以保持风扇低转速；平衡/狂暴档全开睿频，不影响 BIOS PBO 负压）。
- **资源占用低**：纯 Python + GTK3，无 OpenRGB 等重型依赖，后台静置 CPU 占用接近 0%。
- **安全边界清晰**：EC 写入有寄存器白名单（仅 `0x0751` 与 `0x07B9`）和写后读回校验，`/proc/acpi/call` 有线程锁 + 跨进程 `flock`。

**缺点**
- **依赖 `acpi_call` 内核模块**：开启 Secure Boot 的机器需要自行签模块才能加载。
- **不支持自定义风扇曲线**：主板 EC 固件在自动模式下不读取外部风扇表，只能用“EC 自动曲线”或“全速强冷 / 高温自动强冷”。
- **键盘灯不支持单键涂色**：仅提供全键单色和硬件彩虹灯效。

---

## 支持与不支持

| 功能 | 状态 | 说明 |
|---|---|---|
| 性能模式（静音 / 平衡 / 狂暴） | ✅ 支持 | 写 EC `0x0751` 切换功耗墙、风扇曲线与 Dynamic Boost，支持机身物理模式键同步 |
| 独显 Dynamic Boost 解锁 | ✅ 支持 | 配合 `nvidia-powerd`，随档位自动切换独显功耗上限（如 5070 Ti 115W / 130W / 140W） |
| 风扇强冷 / 高温自动强冷 | ✅ 支持 | EC 全速模式；高温强冷默认 ≥88°C 开启、≤78°C 恢复自动，阈值可调 |
| 键盘灯（ITE 8291 & `uniwill_laptop`） | ✅ 支持 | 0–200 亮度、单色 RGB、彩虹灯效、离电自动关灯 |
| 电池限充 | ✅ 支持 | EC `0x07B9`，支持 20%–100% |
| 硬件开关（4 项） | ✅ 支持 | Fn 锁定、Win/超级键、睡眠呼吸灯、触控板双击启停 |
| 开机与睡眠唤醒自动恢复 | ✅ 支持 | 状态保存在 `/var/lib/mrvd/state.json` |
| CPU 功耗墙校准 | ✅ 支持 | `mrvctl calibrate` 实测各档功耗墙 |
| 独显直连（MUX）查询与切换 | 🧪 实验 | 状态查询正常；标准/直连切换需重启生效 |
| 纯集显模式（`igpu`） | ❌ 不支持 | 未实现，GUI 中仅灰显占位 |
| 自定义风扇温控曲线 | ❌ 不支持 | EC 固件不支持（详见 [`mrv-ctl/docs/hardware.md`](mrv-ctl/docs/hardware.md)） |
| 突破 OEM 上限的显卡超功耗 | ❌ 不支持 | 最高到主板 VBIOS/EC 标称上限 |

---

## 测试与未测试

### 1. 机型与系统

| 项目 | 状态 | 环境说明 |
|---|---|---|
| **机械革命 苍龙 16X Pro** (R9 9955HX + RTX 5070 Ti) | ✅ 已实测 | CachyOS (Arch, 内核 7.2) + KDE Plasma 6.8 Wayland |
| **机械革命 苍龙 16** (`M6DR55xx`, R9 8945HX + RTX 5060, BIOS `N.1.16MRO13`) | ✅ 上游已实测 | Ubuntu 24.04 + 内核 7.0 HWE + NVIDIA 595 |
| 其它机械革命 / Uniwill 准系统游戏本 | ⚠️ 未实测 | 按 DSDT 方法与 EC 可读性动态开放功能；未收录机型可用 `mrvctl calibrate` 校准功耗墙 |

### 2. 功能项测试记录（苍龙 16X Pro）

- **已测试通过**：三档切换与物理按键同步、独显功耗上限随档位切换（最高 140W）、ITE 8291 键盘灯（亮度/颜色/单色/彩虹/关灯）、拔电源自动关灯与插电恢复、风扇强冷与高温自动强冷、电池限充（20–100%）、4 项硬件开关、重启与睡眠唤醒恢复、托盘与悬浮窗。
- **未测试（跳过）**：**显卡直连软切换（`mrvctl mux dgpu|standard`）**。测试机固定在 BIOS 独显直连模式下使用，仅测试了 `mux query` 读取，未在系统内执行切换。

---

## 安装与使用

### Arch Linux / CachyOS

```bash
sudo pacman -S --needed python python-gobject gtk3 libayatana-appindicator acpi_call-dkms
git clone https://github.com/Sucasej3R/mechrevo-linux-control.git
cd mechrevo-linux-control
sudo ./install-arch.sh
```

### Ubuntu 24.04 / Debian 系

```bash
git clone https://github.com/Sucasej3R/mechrevo-linux-control.git
cd mechrevo-linux-control/mrv-ctl
sudo ./install.sh
```

> 不要与 TUXEDO Control Center 同时使用，避免双方互相覆盖 EC、CPU 策略和键盘灯。

### 命令行（`mrvctl`）

```bash
mrvctl status                        # 整机状态
mrvctl info                          # 机型识别与功能支持状态
mrvctl profile office|balanced|boost # 静音 / 平衡 / 狂暴
mrvctl fan boost | fan auto          # 强冷 / 自动
mrvctl fan guard on 88 78            # 高温自动强冷阈值
mrvctl kbd 150                       # 亮度 0-200
mrvctl kbd color 40 120 200          # RGB 颜色 (0-200)
mrvctl kbd effect solid|rainbow|off  # 单色 / 彩虹 / 关闭
mrvctl charge 80                     # 充电上限 20-100%
mrvctl mux query                     # 查询显卡直连状态
mrvctl calibrate                     # 实测各档 CPU 功耗墙（约 2 分钟）
```

---

## 致谢

- **[ss12wzh/mechrevo-linux-control](https://github.com/ss12wzh/mechrevo-linux-control)**：上游原作者，完成了核心守护进程架构、EC 寄存器/DSDT 实验验证与硬件文档。
- **[Javis603/token-monitor](https://github.com/Javis603/token-monitor)**：GUI 界面设计语言参考。
- **[tuxedocomputers/tuxedo-drivers](https://github.com/tuxedocomputers/tuxedo-drivers)** 与主线内核 `drivers/platform/x86/uniwill/`：Uniwill EC 寄存器语义与驱动。
- **[L-Mechrevo](https://github.com/LiangyuLu-lly/L-Mechrevo)**、**NvpwrControl**、**[jpy794/wujie-fan-control](https://github.com/jpy794/wujie-fan-control)**、**[bavelee/Mechrevo-Fan-Control](https://github.com/bavelee/Mechrevo-Fan-Control)**、**[xuwd1/mechrevo-wujie14-kmod](https://github.com/xuwd1/mechrevo-wujie14-kmod)**：机械革命 EC 与键盘灯逆向参考资料。

## 许可证

本项目基于 [MIT 许可证](LICENSE) 发布（保留上游完整版权声明），以下文件除外（详见 [NOTICE](NOTICE)）：

- `mrv-ctl/docs/archive/tuxedo-mrv-1.0.patch`：基于 tuxedo-drivers 的补丁，沿用 GPL-2.0-or-later 许可证；
- `mrv-ctl/docs/acpi/`：验证机导出的 ACPI 表，版权归设备厂商所有，仅供研究参考。

## 免责声明

本项目与机械革命（MECHREVO）及其代工厂无任何关系。调整功耗、风扇与 EC 寄存器存在风险，可能影响系统稳定性和硬件寿命，请自行评估风险。本软件按“现状”提供，不提供任何明示或暗示的担保。
