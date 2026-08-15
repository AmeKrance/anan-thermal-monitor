# ============================================================
#  安安热能监控 · 自动安装脚本
#
#  供其他 DeepSeek Harness 用户使用：
#   方式 A（推荐）：让 harness 中的 agent 执行本脚本，然后按提示
#                  用 cordis_define / cordis_run 注册插件
#   方式 B：手动运行
#      powershell -ExecutionPolicy Bypass -File install.ps1
#
#  参数：
#    -InstallDir  安装目录（默认 $HOME\anan-thermal-monitor）
#    -RepoUrl     仓库 zip 下载地址（默认 GitHub main 分支）
# ============================================================
param(
  [string]$InstallDir = (Join-Path $HOME 'anan-thermal-monitor'),
  [string]$RepoUrl = 'https://github.com/YOUR_USERNAME/anan-thermal-monitor/archive/refs/heads/main.zip'
)
$ErrorActionPreference = 'Stop'

Write-Host "== 安安热能监控 · 自动安装 =="
Write-Host "安装目录: $InstallDir"
Write-Host "下载地址: $RepoUrl"

Write-Host "[1/4] 下载仓库 zip ..."
$tmpZip = Join-Path $env:TEMP 'anan-thermal-monitor.zip'
Invoke-WebRequest -Uri $RepoUrl -OutFile $tmpZip -UseBasicParsing

Write-Host "[2/4] 解压到安装目录 ..."
$tmpExtract = Join-Path $env:TEMP 'anan-extract'
Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force
$extracted = Get-ChildItem $tmpExtract -Directory | Select-Object -First 1
if (-not $extracted) { throw '无法定位解压后的目录' }
Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item "$($extracted.FullName)\*" $InstallDir -Recurse -Force

Write-Host "[3/4] 修正 desktop-pet.ps1 中的部署路径 ..."
$pet = Join-Path $InstallDir 'desktop-pet.ps1'
$content = [System.IO.File]::ReadAllText($pet, [System.Text.Encoding]::UTF8)
$wsEsc = [regex]::Escape("`$workspace   = 'G:\harness-organized'")
if ($content -match [regex]::Escape("`$workspace")) {
  $content = $content -replace $wsEsc, "`$workspace   = '$InstallDir'"
}
[System.IO.File]::WriteAllText($pet, $content, [System.Text.UTF8Encoding]::new($true))

Write-Host "[4/4] 生成插件定义文件 plugin-definition.json ..."
$escaped = $InstallDir.Replace('\', '\\')
$hostCode = @'
return {
  apply(ctx) {
    const sub = ctx.get('subprocess')
    const fs = ctx.get('fs')
    const WS = '__INSTALL_DIR__'
    const PET = WS + '\\desktop-pet.ps1'
    const PID_FILE = WS + '\\temp\\desktop-pet.pid'
    const DATA_FILE = WS + '\\temp\\desktop-pet-data.json'
    const STOP_FILE = WS + '\\temp\\desktop-pet-stop.flag'
    let handle = null
    let startedAt = 0

    const spawnArgs = (extra) => ({
      argv: ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', ...extra],
      cwd: WS,
      stdio: { stdin: 'ignore', stdout: 'ignore', stderr: 'ignore' },
      graceMs: 2000,
    })

    const startPet = () => {
      if (handle) return { running: true, pid: handle.pid }
      try {
        handle = sub.spawn(spawnArgs(['-File', PET]))
        startedAt = Date.now()
        const h = handle
        h.done.then(() => { if (handle === h) handle = null }).catch(() => { if (handle === h) handle = null })
        return { running: true, pid: h.pid }
      } catch (e) {
        return { running: false, error: String((e && e.message) || e) }
      }
    }

    const stopPet = () => {
      if (handle) { try { handle.terminate() } catch (e) {} handle = null }
      try {
        sub.spawn(spawnArgs(['-Command', 'Set-Content -Path "' + STOP_FILE + '" -Value stop']))
      } catch (e) {}
      return { stopped: true }
    }

    ctx.effect(() => {
      const r = startPet()
      if (!r.running) console.error('pet start failed: ' + JSON.stringify(r))
      return () => { stopPet() }
    })

    const readJson = async (file) => {
      try {
        const t = await fs.resolve(file)
        const info = await fs.stat(t)
        if (!info) return null
        return JSON.parse(await fs.readText(t))
      } catch (e) { return null }
    }

    const readPid = async () => {
      try {
        const t = await fs.resolve(PID_FILE)
        const info = await fs.stat(t)
        if (!info) return null
        const n = parseInt((await fs.readText(t)).trim(), 10)
        return Number.isFinite(n) && n > 0 ? n : null
      } catch (e) { return null }
    }

    harness.handle('pet-status', async () => {
      const pid = await readPid()
      return { running: !!handle || !!pid, spawned: !!handle, pid: handle ? handle.pid : pid, startedAt }
    })
    harness.handle('pet-temps', async () => readJson(DATA_FILE))
    harness.handle('pet-stop', async () => stopPet())
    harness.handle('pet-start', async () => startPet())
  },
}
'@
$hostCode = $hostCode.Replace('__INSTALL_DIR__', $escaped)

$clientCode = ''
try {
  $clientCode = (Get-Content (Join-Path $InstallDir 'plugin-source\pet-plugin-pkg7-backup.json') -Raw -Encoding UTF8 | ConvertFrom-Json).client
} catch {
  Write-Warning '无法从备份读取 client 代码，插件将只有 Host 半部（桌宠功能不受影响，仅缺 GUI 卡片）'
}
$def = @{ host = $hostCode; client = $clientCode } | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText((Join-Path $InstallDir 'plugin-definition.json'), $def, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "=============================="
Write-Host "安装完成！接下来在 DeepSeek Harness 中操作："
Write-Host ""
Write-Host "1. 用 read 工具读取: $InstallDir\plugin-definition.json"
Write-Host "   （得到 host 与 client 两段代码）"
Write-Host ""
Write-Host "2. 用 cordis_define 创建插件："
Write-Host "   plugin: { kind: 'new', idPrefix: 'pet' }"
Write-Host "   name: '安安热能监控'"
Write-Host "   code.host = json 中的 host 字段"
Write-Host "   code.client = json 中的 client 字段（可选）"
Write-Host ""
Write-Host "3. 用 cordis_run 运行插件（mode: 'run'）"
Write-Host "   - 首次运行会弹 UAC 提权确认（读取 CPU/内存温度需要管理员权限）"
Write-Host "   - 授权后桌宠出现在桌面右下角"
Write-Host ""
Write-Host "4. 若使用 Bigfish 桌面壳：托盘菜单可勾选『安安热能监控』"
Write-Host "=============================="
