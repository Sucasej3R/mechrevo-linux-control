#!/bin/bash
# mrv-ctl (mechrevo-linux-control v3.5.0 二改增强版) Arch / CachyOS 一键安装脚本
#
# 特点：
#   * 保留已装的 mechrevo-drivers-dkms / tuxedo-drivers (若存在)，不卸载、不破坏原驱动包。
#   * 用 modprobe install 覆盖规则让主线 uniwill_laptop 以 force=1 显式加载。
#   * 支持 ITE 8291 (048d:600b) USB HID RGB 键盘控制器（苍龙 16X Pro 等机型）与
#     标准 uniwill_laptop sysfs 多色键盘灯双后端。
#   * 自动排查并清理会导致 CapsLock/NumLock 乱切狂暴模式的旧版 /etc/acpi/events/mechrevo-wmi 规则。
#   * 自动为 KDE Plasma (KWin) 配置 mrv-gui 无边框窗口规则。

set -euo pipefail

if [ "$(id -u)" != 0 ]; then
    echo "请用 sudo 运行: sudo ./install-arch.sh" >&2
    exit 1
fi

# 自动定位源码目录：支持在仓库根目录或在 mrv-ctl/ 内运行
if [ -n "${SRC:-}" ]; then
    :
elif [ -d "$PWD/mrv-ctl" ]; then
    SRC="$PWD/mrv-ctl"
elif [ -f "$PWD/mrvd.py" ]; then
    SRC="$PWD"
else
    echo "找不到源码：请 cd 到 mechrevo-linux-control 仓库根目录或 mrv-ctl/ 下运行" >&2
    exit 1
fi
echo "==> 使用源码目录: $SRC"

# ---------- 0. 依赖检查 ----------
echo "==> 检查依赖..."
check() { command -v "$1" >/dev/null 2>&1 && echo "  [ok] $1" || { echo "  [缺] $1 —— 请先: pacman -S $2" >&2; }; }
check python3 python
python3 -c "import gi; gi.require_version('Gtk','3.0')" 2>/dev/null && echo "  [ok] python-gobject+gtk3" || echo "  [缺] python-gobject / gtk3 —— pacman -S python-gobject gtk3"
python3 -c "import gi; gi.require_version('AyatanaAppIndicator3','0.1')" 2>/dev/null && echo "  [ok] AyatanaAppIndicator3" || echo "  [注] libayatana-appindicator 未安装（可选，用于系统托盘图标）"
if [ -e /proc/acpi/call ] || modinfo acpi_call >/dev/null 2>&1; then
    echo "  [ok] acpi_call"
else
    echo "  [缺] acpi_call —— 请先安装: pacman -S acpi_call-dkms"
fi
command -v nvidia-powerd >/dev/null 2>&1 && echo "  [ok] nvidia-powerd" || echo "  [注] nvidia-powerd 未找到（可选，用于 NVIDIA Dynamic Boost）"

# ---------- 1. 部署文件 ----------
echo "==> 部署到 /opt/mrv 与 /usr/local/bin ..."
install -d -m 755 /opt/mrv
install -m 755 "$SRC/mrvd.py"          /opt/mrv/mrvd.py
install -m 644 "$SRC/mrvmodel.py"      /opt/mrv/mrvmodel.py
install -m 644 "$SRC/data/models.json" /opt/mrv/models.json
install -m 755 "$SRC/mrvctl"           /usr/local/bin/mrvctl
install -m 755 "$SRC/mrv-gui"          /usr/local/bin/mrv-gui
install -m 644 "$SRC/mrvd.service"     /usr/lib/systemd/system/mrvd.service
install -d -m 755 /usr/share/icons/hicolor/256x256/apps
install -m 644 "$SRC/icons/mrv-ctl.png" /usr/share/icons/hicolor/256x256/apps/mrv-ctl.png

# ---------- 2. 开机加载 acpi_call 与主线 uniwill_laptop (force=1) ----------
echo "==> 配置开机自动加载内核模块..."
cat > /etc/modules-load.d/mrv-ctl.conf <<'EOF'
acpi_call
uniwill_laptop
EOF

cat > /etc/modprobe.d/mrv-uniwill.conf <<'EOF'
# mrv-ctl: 强制在 MECHREVO 等非 TUXEDO 品牌的 Uniwill 准系统上加载主线 uniwill_laptop (force=1)
install uniwill_laptop /sbin/modprobe --ignore-install uniwill_laptop force=1
options uniwill_laptop force=1
EOF

echo "==> 加载内核模块..."
modprobe acpi_call 2>/dev/null || true
modprobe uniwill_laptop force=1 2>/dev/null || \
  { echo "  [警告] uniwill_laptop 加载失败：$(dmesg 2>/dev/null | tail -3)"; }

# ---------- 3. 清理冲突的旧版 acpid WMI 规则 ----------
if [ -f /etc/acpi/events/mechrevo-wmi ]; then
    echo "==> 检测到冲突的 /etc/acpi/events/mechrevo-wmi，正在移除（防止 CapsLock/NumLock 误触发狂暴模式）..."
    rm -f /etc/acpi/events/mechrevo-wmi /etc/acpi/mechrevo-perf.sh
    systemctl restart acpid 2>/dev/null || true
fi

# ---------- 4. 启用 mrvd 守护进程 ----------
echo "==> 启用并重启 mrvd.service ..."
systemctl daemon-reload
systemctl enable mrvd.service 2>/dev/null || true
systemctl restart mrvd.service 2>/dev/null || true
sleep 1
systemctl is-active mrvd.service >/dev/null 2>&1 && echo "  [ok] mrvd 运行中" || \
  { echo "  [警告] mrvd 未运行，查看: journalctl -u mrvd -e"; }

# ---------- 5. nvidia-powerd (Dynamic Boost, 可选) ----------
if [ -x /usr/bin/nvidia-powerd ]; then
  if [ ! -f /usr/lib/systemd/system/nvidia-powerd.service ]; then
    cat > /usr/lib/systemd/system/nvidia-powerd.service <<'EOF'
[Unit]
Description=NVIDIA Power Daemon (Dynamic Boost / NVPCF)
After=multi-user.target nvidia-persistenced.service

[Service]
Type=simple
ExecStart=/usr/bin/nvidia-powerd
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
  fi
  systemctl enable --now nvidia-powerd 2>/dev/null || true
  echo "  [ok] nvidia-powerd 已启用"
fi

# ---------- 6. 桌面入口 + 托盘自启 ----------
echo "==> 安装桌面入口与托盘自启..."
install -d -m 755 /usr/share/applications /etc/xdg/autostart
cat > /usr/share/applications/mrv-ctl.desktop <<'EOF'
[Desktop Entry]
Name=mrv-ctl 机械革命控制台
GenericName=笔记本控制中心
Comment=性能模式/RGB/限充/独显直连
Exec=/usr/local/bin/mrv-gui
Icon=mrv-ctl
Terminal=false
Type=Application
Categories=System;HardwareSettings;
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF
cat > /etc/xdg/autostart/mrv-ctl-autostart.desktop <<'EOF'
[Desktop Entry]
Name=mrv-ctl 托盘
Exec=/usr/local/bin/mrv-gui
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
EOF
update-desktop-database /usr/share/applications 2>/dev/null || true

echo ""
echo "==> 安装完成。"
echo "    查看识别/能力门槛: sudo /usr/local/bin/mrvctl info"
echo "    查看状态:          sudo /usr/local/bin/mrvctl status"
echo "    校准功耗墙:        sudo /usr/local/bin/mrvctl calibrate   (约2分钟,满载CPU)"
echo "    启动 GUI:          mrv-gui  (或从应用菜单打开 mrv-ctl)"
