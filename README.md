# 安安热能监控 · 桌面萌宠温度监控（DSH 插件包）

一个悬浮在 Windows 桌面上的紫白主题萌宠卡片，实时监控 **CPU / 内存 / GPU / NVMe 固态** 四项温度，并展示笔记本型号与硬件信息。这是一个标准的 **DeepSeek Harness (DSH) 插件包**，可通过 `dsh plugin --profile <name> add <包名>` 一条命令安装；也支持脱离 harness 独立运行。基于 PowerShell 5.1 + WPF 原生实现，无第三方桌面组件依赖。

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

## 📦 安装方法（推荐：DSH 插件包）

### 前提
- Windows 10/11（64 位）、PowerShell 5.1+
- 已安装 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（含 `dsh` CLI 与 `pnpm`）

### 一键安装

```bash
# 已发布到 npm registry 时：
dsh plugin --profile web add anan-thermal-monitor

# 或从 GitHub 仓库安装（推荐，无需 npm 账号）：
dsh plugin --profile web add github:AmeKrance/anan-thermal-monitor

# 或使用本地已解压的源码目录：
dsh plugin --profile web add /path/to/anan-thermal-monitor
```

安装后 **重启 dsh（web profile）**，桌宠自动出现在桌面右下角；首次运行弹 UAC 提权确认（读取 CPU/内存温度需要管理员权限），点"是"即可。

### 卸载

```bash
dsh plugin --profile web remove anan-thermal-monitor
```

### 备选：独立运行（不接入 harness）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File assets\desktop-pet.ps1
```

右键桌宠卡片 → "退出安安热能监控" 关闭。

---

## 🖥️ 对电脑各种信息的调用

| 信息 | 调用方式 | 权限 | 说明 |
|---|---|---|---|
| CPU 温度 | LibreHardwareMonitorLib (Ring0 / Intel MSR) | 管理员 | CPU Package / Core Max 温度 |
| 内存温度 | LibreHardwareMonitorLib (SMBus / SPD) | 管理员 | DDR DIMM 温度传感器，无传感器显示 "--" |
| GPU 温度 | LibreHardwareMonitorLib (NVIDIA NVAPI / AMD ADL) | 普通 | GPU Core 温度 |
| NVMe 固态温度 | LibreHardwareMonitorLib (NVMe SMART / ATA) | 普通 | Composite Temperature，多盘取最热 |
| CPU 型号 | WMI `Win32_Processor.Name` | 普通 | 精简为如 `i7-12800HX` |
| 显卡型号 | WMI `Win32_VideoController.Name`（过滤虚拟显卡） | 普通 | 精简为如 `RTX 4070` |
| 内存容量 | WMI `Win32_ComputerSystem.TotalPhysicalMemory` | 普通 | 四舍五入到 GB |
| 屏幕分辨率 | WMI `Win32_VideoController.CurrentHorizontal/VerticalResolution` | 普通 | 如 `1920×1080` |
| 硬盘总容量 | WMI `Win32_DiskDrive.Size`（多盘求和） | 普通 | 换算 TB/GB |
| 电池状态 | `System.Windows.Forms.SystemInformation.PowerStatus` | 普通 | 电量 % + 状态，每 10 秒刷新 |
| 进程托管 | 插件 Host：`node:child_process` spawn + 停止信号文件 | — | 生命周期随插件启停 |
| 硬件库 | `assets/LibreHardwareMonitor/LibreHardwareMonitorLib.dll` | — | MIT License v0.9.6，随包内置 |

> WMI 查询仅在桌宠启动时执行一次；温度采集在后台 runspace 线程每 2 秒执行，UI 线程零阻塞。

---

## 🧱 插件包结构

```
anan-thermal-monitor/
├── package.json                # npm 包清单：声明 dsh.bundle.patch（使插件可被 dsh plugin add 识别）
├── cordis.patch.yml            # 组合层 patch：把插件插入 profile 的层栈
├── lib/index.js                # 插件 Host（ESM，完整 Node API）：spawn/停止桌宠进程
├── assets/
│   ├── desktop-pet.ps1         # 桌宠主脚本（WPF + LHM 采集 + 自提权，路径全相对，可移植）
│   ├── 素材1号.jpg              # 桌宠素材（可替换）
│   └── LibreHardwareMonitor/   # 硬件监控库（运行时依赖）
├── install.ps1                 # 备选手动安装脚本
├── README.md
└── backups/                    # 历史版本备份
```

### 安装原理

`dsh plugin --profile <name> add <包>` 是一个 pnpm 转发器：安装依赖后，会读取每个新依赖的 `package.json`，凡声明 `dsh.bundle.patch` 的包会自动加入 profile 的 `dsh.profile.bundles` 层栈；下次启动时，该 patch（`cordis.patch.yml`）把插件作为一行 `- id: anan-thermal-monitor / name: anan-thermal-monitor` 插入组合，插件 `apply()` 随即执行并拉起桌宠进程。

---

## ⚙️ 配置与运行时文件

- 所有资源路径基于脚本自身目录相对定位（`$PSScriptRoot`），任意位置部署无需改路径
- 运行时临时文件写入 `%TEMP%\anan-thermal-monitor\`：

| 文件 | 作用 |
|---|---|
| `desktop-pet.pid` | 桌宠进程 PID（插件判定运行状态） |
| `desktop-pet-data.json` | 最新传感器数据 `{cpu, mem, gpu, nvme, ts}` |
| `desktop-pet-stop.flag` | 停止信号（插件停止时写入，桌宠优雅退出） |
| `desktop-pet-pos.txt` | 窗口位置记忆 |
| `desktop-pet-error.log` | 运行诊断日志 |

---

## 🐛 常见问题

- **硬件显示 "--"**：对应传感器未暴露（如笔记本主板无板载温度传感器），非故障
- **每次启动弹 UAC**：Ring0/SMBus 读取需要管理员权限，属正常现象
- **重复启动双开**：脚本内置幂等检查，已运行实例存在时新实例直接退出

---

## 📄 许可

- 代码：MIT License
- `assets/LibreHardwareMonitor/`：[LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) (MIT License, v0.9.6)
- 素材版权归原作者所有
