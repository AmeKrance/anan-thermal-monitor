# ============================================================
#  安安热能监控 · 备选手动安装脚本
#
#  主要安装方式（推荐）：作为 DSH 插件包通过 pnpm 安装 ——
#     dsh plugin --profile web add <包名或本地路径或git仓库>
#
#  本脚本用于：下载仓库 zip 并解压到本地，然后可用
#    dsh plugin --profile <profile名> add <解压目录>
#  完成安装；也支持不接入 harness 的独立运行。
# ============================================================
param(
  [string]$InstallDir = (Join-Path $HOME 'anan-thermal-monitor'),
  [string]$RepoUrl = 'https://github.com/YOUR_USERNAME/anan-thermal-monitor/archive/refs/heads/main.zip'
)
$ErrorActionPreference = 'Stop'

Write-Host "== 安安热能监控 · 手动安装 =="
Write-Host "[1/3] 下载仓库 zip ..."
$tmpZip = Join-Path $env:TEMP 'anan-thermal-monitor.zip'
Invoke-WebRequest -Uri $RepoUrl -OutFile $tmpZip -UseBasicParsing

Write-Host "[2/3] 解压到 $InstallDir ..."
$tmpExtract = Join-Path $env:TEMP 'anan-extract'
Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force
$extracted = Get-ChildItem $tmpExtract -Directory | Select-Object -First 1
if (-not $extracted) { throw '无法定位解压后的目录' }
Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item "$($extracted.FullName)\*" $InstallDir -Recurse -Force

Write-Host "[3/3] 完成。"
Write-Host ""
Write-Host "接下来二选一："
Write-Host ""
Write-Host "方式 A（接入 DeepSeek Harness，推荐）："
Write-Host "  dsh plugin --profile web add $InstallDir"
Write-Host "  重启 dsh 后桌宠自动出现在桌面（首次弹 UAC 请点『是』）"
Write-Host ""
Write-Host "方式 B（独立运行，不接入 harness）："
Write-Host "  powershell -ExecutionPolicy Bypass -File $InstallDir\assets\desktop-pet.ps1"
Write-Host "  右键桌宠卡片 → 『退出安安热能监控』关闭"
Write-Host ""
Write-Host "备注：脚本路径全部基于脚本自身目录相对定位，任意位置可运行；"
Write-Host "运行时临时文件写入 %TEMP%\anan-thermal-monitor\。"
