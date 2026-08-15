# 安安热能监控 · 桌面萌宠温度监控

一个悬浮在 Windows 桌面上的紫白主题萌宠卡片，实时监控 **CPU / 内存 / GPU / NVMe 固态** 四项温度，并展示笔记本型号与硬件信息。基于 PowerShell 5.1 + WPF 原生实现，无第三方桌面组件依赖，可独立运行，也可作为 DeepSeek Harness (Bigfish) 的动态 Cordis 插件使用。

---

## ✨ 功能总览

- **桌面悬浮窗**：透明、无边框、置顶的紫白渐变卡片（207×320），可拖动，位置自动记忆
- **实时温度监控**：CPU / 内存 / GPU / NVMe 四项温度，每 2 秒刷新，数值按温度分级变色（紫 <65°C，橙 65–79°C，红 ≥80°C）
- **页面自动轮换**：下方区域每 5 秒在「温度信息页」与「硬件信息页」之间切换，鼠标悬停时暂停轮换并固定显示温度
- **硬件信息展示**：笔记本型号、CPU/显卡/内存摘要、屏幕分辨率、硬盘总容量、电池状态（电量 + 充电/电源/使用中）
- **自定义素材**：`assets/素材1号.jpg` 作为萌宠形象，等比缩放填充图片区
- **自动提权**：读取 CPU/内存温度需要管理员权限，启动时自动弹出 UAC 确认
- **优雅退出**：右键菜单退出；作为插件运行时，插件停止会通过停止信号文件让桌宠自动关闭并清理

---

## 🖥️ 对电脑各种信息的调用

| 信息 | 调用方式 | 权限 | 说明 |
|---|---|---|---|
| CPU 温度 | LibreHardwareMonitorLib (Ring0 / Intel MSR) | 管理员 | 读取 CPU Package / Core Max 温度 |
| 内存温度 | LibreHardwareMonitorLib (SMBus / SPD) | 管理员 | 读取 DDR DIMM 温度传感器，无传感器显示 "--" |
| GPU 温度 | LibreHardwareMonitorLib (NVIDIA NVAPI / AMD ADL) | 普通 | GPU Core 温度 |
| NVMe 固态温度 | LibreHardwareMonitorLib (NVMe SMART / ATA) | 普通 | Composite Temperature，多盘取最热 |
| CPU 型号 | WMI `Win32_Processor.Name` | 普通 | 自动精简为如 `i7-12800HX` |
| 显卡型号 | WMI `Win32_VideoController.Name`（过滤虚拟显卡） | 普通 | 精简为如 `RTX 4070` |
| 内存容量 | WMI `Win32_ComputerSystem.TotalPhysicalMemory` | 普通 | 四舍五入到 GB |
| 屏幕分辨率 | WMI `Win32_VideoController.CurrentHorizontal/VerticalResolution` | 普通 | 如 `1920×1080` |
| 硬盘总容量 | WMI `Win32_DiskDrive.Size`（多盘求和） | 普通 | 换算 TB/GB |
| 电池状态 | `System.Windows.Forms.SystemInformation.PowerStatus` | 普通 | 电量 % + 充电中/电源/使用中，每 10 秒刷新 |
| 硬件库 | `lib/LibreHardwareMonitor/LibreHardwareMonitorLib.dll` | — | 开源 MIT 许可，v0.9.6，随仓库内置 |

> 所有 WMI 查询仅在启动时执行一次；温度采集在后台 runspace 线程中每 2 秒执行，UI 线程零阻塞。

---

## 📁 目录结构

```
anan-thermal-monitor/
├── desktop-pet.ps1              # 主脚本（WPF 桌宠窗口 + 传感器采集 + 自提权）
├── install.ps1                  # ★ 自动安装脚本（供其他 harness 用户）
├── README.md
├── assets/
│   └── 素材1号.jpg              # 桌宠素材（可替换成自己的图片）
├── lib/
│   └── LibreHardwareMonitor/    # 硬件监控库（运行时依赖，勿删）
├── plugin-source/
│   └── pet-plugin-pkg7-backup.json  # Cordis 插件源码备份（Host/Client）
└── backups/                     # 历史版本备份
```

---

## 🚀 安装方法

### 方式 A：自动安装（推荐，供其他 DeepSeek Harness 用户）

1. 下载本仓库，或在 harness 中让 agent 执行安装脚本：

```powershell
# 把下面的 RepoUrl 换成你 fork/上传后的实际地址
powershell -ExecutionPolicy Bypass -File install.ps1 -RepoUrl "https://github.com/YOUR_USERNAME/anan-thermal-monitor/archive/refs/heads/main.zip"
```

2. 脚本会自动：下载 → 解压到 `$HOME\anan-thermal-monitor` → 修正脚本内路径 → 生成 `plugin-definition.json`
3. 在 DeepSeek Harness 中让 agent 执行：
   - `read` 读取 `plugin-definition.json`，得到 `host` 与 `client` 两段代码
   - `cordis_define` 创建插件（`idPrefix: 'pet'`，填入上述代码）
   - `cordis_run` 运行（首次弹 UAC 请点"是"）
4. 桌宠出现在桌面右下角；对话流内出现紫白控制卡片（实时温度 + 启停按钮）

### 方式 B：独立运行（不接入 harness）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File desktop-pet.ps1
```

右键桌宠 → "退出安安热能监控" 关闭。

---

## ⚙️ 部署路径配置

`desktop-pet.ps1` 顶部常量在 `install.ps1` 中会被自动修正；手动部署时请修改：

```powershell
$workspace   = 'G:\harness-organized'   # ← 改为仓库所在目录
$imagePath   = Join-Path $workspace '素材1号.jpg'
$lhmDir      = Join-Path $workspace 'lib\LibreHardwareMonitor'
$tempDir     = Join-Path $workspace 'temp'
```

> 素材默认放在仓库根目录（`素材1号.jpg`）；若放入 `assets/` 子目录请同步修改 `$imagePath`。

---

## 🔧 运行时文件（自动生成于 `temp/` 目录）

| 文件 | 作用 |
|---|---|
| `desktop-pet.pid` | 桌宠进程 PID（插件据此判断运行状态） |
| `desktop-pet-data.json` | 最新传感器数据 `{cpu, mem, gpu, nvme, ts}`（GUI 卡片轮询） |
| `desktop-pet-stop.flag` | 停止信号（插件/托盘写入后桌宠优雅退出） |
| `desktop-pet-pos.txt` | 窗口位置记忆 |
| `desktop-pet-error.log` | 运行诊断日志 |

---

## 🐛 常见问题

- **主板/风扇读不到**：本脚本按需求只展示 CPU/内存/GPU/NVMe；如硬件未暴露传感器，对应项显示 `--`（如笔记本主板通常无板载温度传感器）
- **每次启动弹 UAC**：读取 CPU/内存温度（Ring0/SMBus）需要管理员权限，这是硬件监控的固有要求
- **多个实例**：脚本内置幂等检查（检测到已有实例直接退出），重复启动不会开两个窗口

---

## 📄 许可

- 脚本部分：MIT License
- `lib/LibreHardwareMonitor/`：[LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) (MIT License, v0.9.6)
- 素材版权归原作者所有
