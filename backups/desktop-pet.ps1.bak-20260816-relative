# ============================================================
#  desktop-pet.ps1 - 安安热能监控 · 桌面悬浮窗 + 硬件温度监控
#  依赖: LibreHardwareMonitorLib.dll (同目录 LibreHardwareMonitor/)
#  素材: 素材1号.jpg (同目录)
#  运行: 首次会弹 UAC 提权(读取CPU温度/内存温度需要管理员)
#  路径: 全部基于 $PSScriptRoot 相对定位, 可随包任意部署
# ============================================================
$ErrorActionPreference = 'Stop'

# ---------- 常量(全部相对脚本所在目录, 可移植) ----------
$workspace   = $PSScriptRoot
$imagePath   = Join-Path $workspace '素材1号.jpg'
$lhmDir      = Join-Path $workspace 'LibreHardwareMonitor'
$lhmDll      = Join-Path $lhmDir 'LibreHardwareMonitorLib.dll'
$tempDir     = Join-Path $env:TEMP 'anan-thermal-monitor'
$pidFile     = Join-Path $tempDir 'desktop-pet.pid'
$dataFile    = Join-Path $tempDir 'desktop-pet-data.json'
$posFile     = Join-Path $tempDir 'desktop-pet-pos.txt'
$stopFile    = Join-Path $tempDir 'desktop-pet-stop.flag'
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# ---------- 幂等: 已有一个实例则退出(放在提权前, 避免重复实例弹两次 UAC) ----------
if (Test-Path $pidFile) {
  $oldPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($oldPid) {
    $oldProc = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
    if ($oldProc) { exit }
  }
}

# ---------- 确认要启动后才清理上次的停止信号(避免覆盖插件正在发送的停止指令) ----------
Remove-Item -Path $stopFile -Force -ErrorAction SilentlyContinue

# ---------- 自提权(读取 CPU 温度/内存温度需要管理员) ----------
# 调试开关: $env:PET_NO_ELEVATE=1 时跳过提权(便于非管理员调试 UI)
if ($env:PET_NO_ELEVATE -ne '1') {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    try {
      Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$PSCommandPath`"")
    } catch {
      # 用户拒绝提权: 仍以降权模式运行(GPU/NVMe温度可用)
    }
    exit
  }
}
Set-Content -Path $pidFile -Value ([string]$PID) -Encoding ASCII

# ---------- 共享状态 ----------
$errFile = Join-Path $tempDir 'desktop-pet-error.log'
$state = [hashtable]::Synchronized(@{
  running = $true
  cpu = $null; gpu = $null; mem = $null; nvme = $null
  err = $null; ts = 0
  dataFile = $dataFile
  errFile = $errFile
})
function Write-ErrLog {
  param($msg)
  try { [System.IO.File]::AppendAllText($errFile, ("[" + (Get-Date -Format 'HH:mm:ss') + "] " + $msg + "`r`n"), [System.Text.Encoding]::UTF8) } catch {}
}

# ---------- WPF ----------
try {
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms

# ---------- 后台传感器采集(runspace) ----------
$sensorScript = {
  param($st)
  try {
    [Reflection.Assembly]::LoadFrom($st.lhmDll) | Out-Null
  } catch {
    $st.err = "LHM加载失败: " + $_.Exception.Message
    try { [System.IO.File]::WriteAllText($st.errFile, ("LHM加载失败: " + $_.Exception.Message + "`r`n"), [System.Text.Encoding]::UTF8) } catch {}
    return
  }
  $computer = [LibreHardwareMonitor.Hardware.Computer]::new()
  $computer.IsCpuEnabled = $true
  $computer.IsGpuEnabled = $true
  $computer.IsMotherboardEnabled = $true
  $computer.IsControllerEnabled = $true
  $computer.IsStorageEnabled = $true
  $computer.IsMemoryEnabled = $true
  try { $computer.Open() } catch { $st.err = "Open失败: " + $_.Exception.Message; try { [System.IO.File]::WriteAllText($st.errFile, ("Open失败: " + $_.Exception.Message + "`r`n"), [System.Text.Encoding]::UTF8) } catch {}; return }
  try { [System.IO.File]::AppendAllText($st.errFile, ("采集线程已启动 " + (Get-Date -Format 'HH:mm:ss') + "`r`n"), [System.Text.Encoding]::UTF8) } catch {}
  Start-Sleep -Seconds 2
  while ($st.running) {
    try {
      foreach ($hu in $computer.Hardware) {
        try { $hu.Update() } catch {}
        foreach ($shu in $hu.SubHardware) { try { $shu.Update() } catch {} }
      }
      $cpu = $null; $gpu = $null; $mem = $null; $nvme = $null
      foreach ($h in $computer.Hardware) {
        $type = [string]$h.HardwareType
        $sensors = @($h.Sensors)
        foreach ($sh in $h.SubHardware) { $sensors += @($sh.Sensors) }
        if ($type -eq 'Cpu') {
          $t = $sensors | Where-Object { [string]$_.SensorType -eq 'Temperature' -and $_.Name -eq 'CPU Package' } | Select-Object -First 1
          if (-not $t) { $t = $sensors | Where-Object { [string]$_.SensorType -eq 'Temperature' -and $_.Name -eq 'Core Max' } | Select-Object -First 1 }
          if (-not $t) { $t = $sensors | Where-Object { [string]$_.SensorType -eq 'Temperature' -and $_.Value } | Sort-Object Value -Descending | Select-Object -First 1 }
          if ($t -and $null -ne $t.Value) { $cpu = [double]$t.Value }
        } elseif ($type -like 'Gpu*') {
          $t = $sensors | Where-Object { [string]$_.SensorType -eq 'Temperature' -and $_.Name -eq 'GPU Core' } | Select-Object -First 1
          if (-not $t) { $t = $sensors | Where-Object { [string]$_.SensorType -eq 'Temperature' -and $_.Value } | Select-Object -First 1 }
          if ($t -and $null -ne $t.Value) { $gpu = [double]$t.Value }
        } elseif ($type -eq 'Memory') {
          # 内存温度: 优先 DIMM 传感器, 取所有 DIMM 最大值
          $ts = $sensors | Where-Object { [string]$_.SensorType -eq 'Temperature' -and $_.Name -match 'DIMM' -and $_.Value }
          if (-not $ts) { $ts = $sensors | Where-Object { [string]$_.SensorType -eq 'Temperature' -and $_.Value } }
          foreach ($t in $ts) {
            $v = [double]$t.Value
            if ($null -eq $mem -or $v -gt $mem) { $mem = $v }
          }
        } elseif ($type -eq 'Storage') {
          # NVMe 固态温度: 优先 Composite Temperature, 多块盘取最大值
          $ts = $sensors | Where-Object { [string]$_.SensorType -eq 'Temperature' -and $_.Name -match 'Composite' -and $_.Value }
          if (-not $ts) { $ts = $sensors | Where-Object { [string]$_.SensorType -eq 'Temperature' -and $_.Value } | Select-Object -First 1 }
          foreach ($t in $ts) {
            $v = [double]$t.Value
            if ($null -eq $nvme -or $v -gt $nvme) { $nvme = $v }
          }
        }
      }
      $st.cpu = $cpu; $st.gpu = $gpu; $st.mem = $mem; $st.nvme = $nvme
      $st.ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
      try {
        $json = @{ cpu = $cpu; mem = $mem; gpu = $gpu; nvme = $nvme; ts = $st.ts } | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($st.dataFile, $json)
      } catch {}
    } catch {
      $st.err = $_.Exception.Message
      try { [System.IO.File]::AppendAllText($st.errFile, ("采集循环异常: " + $_.Exception.Message + "`r`n"), [System.Text.Encoding]::UTF8) } catch {}
    }
    Start-Sleep -Seconds 2
  }
  try { $computer.Close() } catch {}
}

$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$state.lhmDll = $lhmDll
$ps = [powershell]::Create()
$ps.Runspace = $runspace
$null = $ps.AddScript($sensorScript).AddArgument($state)
$asyncHandle = $ps.BeginInvoke()

# ---------- XAML 界面 ----------
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="223" Height="336" AllowsTransparency="True" WindowStyle="None"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        ResizeMode="NoResize" WindowStartupLocation="Manual">
  <Border x:Name="Card" Width="207" Height="320" CornerRadius="18" BorderThickness="1.5"
          BorderBrush="#B9A5E3" Background="#F7F2FC" ClipToBounds="True" Margin="8">
    <Border.Effect>
      <DropShadowEffect Color="#6A3FA0" BlurRadius="20" ShadowDepth="4" Opacity="0.45"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="200"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0" CornerRadius="14,14,0,0" Margin="9,9,9,0"
              Background="White" ClipToBounds="True">
        <Grid x:Name="PetHost">
          <Image x:Name="PetImage" Stretch="Uniform" Margin="4"
                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
      </Border>
      <Grid Grid.Row="1" Margin="12,6,12,8">
        <StackPanel x:Name="IdlePanel" VerticalAlignment="Top" HorizontalAlignment="Center" Margin="0,6,0,0">
          <TextBlock Text="安安热能监控" FontSize="16" FontWeight="Bold" Foreground="#5E35B1"
                     HorizontalAlignment="Center"/>
          <TextBlock Text="2024极光X" FontSize="11" FontWeight="Bold" Foreground="#8E6FB8"
                     HorizontalAlignment="Center" Margin="0,5,0,0"/>
          <TextBlock x:Name="SpecText" Text="i7-12800HX · RTX 4070 · 16GB" FontSize="9.5" Foreground="#A08CC4"
                     HorizontalAlignment="Center" Margin="0,3,0,0"/>
          <TextBlock x:Name="ResDiskText" Text="1920×1080 · 2TB" FontSize="9.5" Foreground="#A08CC4"
                     HorizontalAlignment="Center" Margin="0,3,0,0"/>
          <TextBlock x:Name="BatteryText" Text="电池 --% · --" FontSize="9.5" Foreground="#A08CC4"
                     HorizontalAlignment="Center" Margin="0,3,0,0"/>
        </StackPanel>
        <StackPanel x:Name="HoverPanel" Visibility="Collapsed" VerticalAlignment="Top" Margin="0,4,0,0">
          <TextBlock Text="实时温度" FontSize="11" FontWeight="Bold" Foreground="#7B4FA6"
                     Margin="2,0,0,3"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

$window = [System.Windows.Markup.XamlReader]::Parse($xaml)
$card = $window.FindName('Card')
$petHost = $window.FindName('PetHost')
$petImage = $window.FindName('PetImage')
$idlePanel = $window.FindName('IdlePanel')
$hoverPanel = $window.FindName('HoverPanel')
$specTextBlock = $window.FindName('SpecText')
$resDiskTextBlock = $window.FindName('ResDiskText')
$batteryTextBlock = $window.FindName('BatteryText')

# ---------- 硬件信息(启动时读取一次, 失败保留兜底文本) ----------
try {
  $cpuName = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
  $cpuShort = ''
  if ($cpuName -match 'i[0-9]+-[0-9A-Za-z]+') { $cpuShort = $matches[0] }
  elseif ($cpuName -match 'Ryzen [0-9]+') { $cpuShort = $matches[0] }
  if (-not $cpuShort -and $cpuName) { $cpuShort = (($cpuName -split '\(')[0]).Trim() }
  $gpuName = (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Virtual|Remote|Basic|Microsoft|Display' } | Select-Object -First 1).Name
  $gpuShort = ''
  if ($gpuName -match 'RTX [0-9]+') { $gpuShort = $matches[0] }
  elseif ($gpuName -match 'GTX [0-9]+') { $gpuShort = $matches[0] }
  elseif ($gpuName -match 'RX [0-9]+') { $gpuShort = $matches[0] }
  elseif ($gpuName) { $gpuShort = (($gpuName -split ' ' | Select-Object -First 2) -join ' ') }
  $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB)
  if ($cpuShort -and $gpuShort -and $ramGB) {
    $specTextBlock.Text = "$cpuShort · $gpuShort · ${ramGB}GB"
  }
  # 屏幕分辨率(取非虚拟显卡的当前分辨率)
  $resText = ''
  $vcs = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Virtual|Remote|Basic|Microsoft|Display' }
  foreach ($vc in $vcs) {
    if ($vc.CurrentHorizontalResolution -and $vc.CurrentVerticalResolution) {
      $resText = "$($vc.CurrentHorizontalResolution)×$($vc.CurrentVerticalResolution)"
      break
    }
  }
  # 硬盘总容量
  $diskGB = 0
  foreach ($d in (Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)) {
    if ($d.Size) { $diskGB += [math]::Round($d.Size / 1GB) }
  }
  $diskText = ''
  if ($diskGB -ge 1024) { $diskText = ('{0:F0}TB' -f ($diskGB / 1024)) }
  elseif ($diskGB -gt 0) { $diskText = "$diskGB GB" }
  if ($resText -and $diskText) {
    $resDiskTextBlock.Text = "$resText · $diskText"
  } elseif ($resText) {
    $resDiskTextBlock.Text = $resText
  } elseif ($diskText) {
    $resDiskTextBlock.Text = $diskText
  }
} catch {
  Write-ErrLog ("硬件信息读取失败: " + $_.Exception.Message)
}

# ---------- 素材图片(失败则自绘兜底萌宠) ----------
$imgLoaded = $false
if (Test-Path $imagePath) {
  try {
    $bmp = [System.Windows.Media.Imaging.BitmapImage]::new()
    $bmp.BeginInit()
    $bmp.UriSource = ([System.Uri]::new($imagePath))
    $bmp.DecodePixelWidth = 460
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.EndInit()
    $petImage.Source = $bmp
    $imgLoaded = $true
  } catch {
    Write-ErrLog ("素材加载失败: " + $_.Exception.Message)
  }
}
if (-not $imgLoaded) {
  Write-ErrLog "进入兜底绘制分支"
  try {
    $canvas = [System.Windows.Controls.Canvas]::new()
    $canvas.Width = 180; $canvas.Height = 180
    $canvas.RenderTransformOrigin = [System.Windows.Point]::new(0, 0)
    $canvas.RenderTransform = [System.Windows.Media.ScaleTransform]::new(0.55, 0.55)
    # 脸
    $face = [System.Windows.Shapes.Ellipse]::new()
    $face.Width = 150; $face.Height = 140
    $face.Fill = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0xB9,0xA5,0xE3))
    [System.Windows.Controls.Canvas]::SetLeft($face, 15); [System.Windows.Controls.Canvas]::SetTop($face, 20)
    $null = $canvas.Children.Add($face)
    # 眼睛
    foreach ($ex in @(50, 100)) {
      $eye = [System.Windows.Shapes.Ellipse]::new()
      $eye.Width = 18; $eye.Height = 24
      $eye.Fill = [System.Windows.Media.Brushes]::White
      [System.Windows.Controls.Canvas]::SetLeft($eye, $ex); [System.Windows.Controls.Canvas]::SetTop($eye, 62)
      $null = $canvas.Children.Add($eye)
      $pupil = [System.Windows.Shapes.Ellipse]::new()
      $pupil.Width = 9; $pupil.Height = 12
      $pupil.Fill = [System.Windows.Media.Brushes]::Black
      [System.Windows.Controls.Canvas]::SetLeft($pupil, $ex + 4.5); [System.Windows.Controls.Canvas]::SetTop($pupil, 68)
      $null = $canvas.Children.Add($pupil)
    }
    # 腮红
    foreach ($cx in @(36, 128)) {
      $blush = [System.Windows.Shapes.Ellipse]::new()
      $blush.Width = 20; $blush.Height = 12
      $blush.Fill = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0xF0,0xA8,0xC8))
      [System.Windows.Controls.Canvas]::SetLeft($blush, $cx); [System.Windows.Controls.Canvas]::SetTop($blush, 104)
      $null = $canvas.Children.Add($blush)
    }
    # 嘴
    $mouth = [System.Windows.Shapes.Ellipse]::new()
    $mouth.Width = 26; $mouth.Height = 14
    $mouth.Fill = [System.Windows.Media.Brushes]::White
    [System.Windows.Controls.Canvas]::SetLeft($mouth, 77); [System.Windows.Controls.Canvas]::SetTop($mouth, 110)
    $null = $canvas.Children.Add($mouth)
    $petHost.Children.Add($canvas) | Out-Null
  } catch {
    Write-ErrLog ("兜底绘制异常: " + $_.Exception.Message)
    Write-ErrLog ("位置: " + $_.InvocationInfo.PositionMessage)
  }
}

# ---------- 温度行(悬停面板) ----------
function New-TempRow {
  param($name)
  $row = [System.Windows.Controls.Grid]::new()
  $c1 = [System.Windows.Controls.ColumnDefinition]::new(); $c1.Width = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
  $c2 = [System.Windows.Controls.ColumnDefinition]::new(); $c2.Width = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
  $c3 = [System.Windows.Controls.ColumnDefinition]::new(); $c3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
  $null = $row.ColumnDefinitions.Add($c1); $null = $row.ColumnDefinitions.Add($c2); $null = $row.ColumnDefinitions.Add($c3)
  $dot = [System.Windows.Shapes.Ellipse]::new()
  $dot.Width = 8; $dot.Height = 8
  $dot.Fill = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x95, 0x75, 0xCD))
  [System.Windows.Controls.Grid]::SetColumn($dot, 0)
  $null = $row.Children.Add($dot)
  $label = [System.Windows.Controls.TextBlock]::new()
  $label.Text = $name
  $label.FontSize = 12.5
  $label.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x5E,0x35,0xB1))
  $label.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
  $label.VerticalAlignment = 'Center'
  [System.Windows.Controls.Grid]::SetColumn($label, 1)
  $null = $row.Children.Add($label)
  $value = [System.Windows.Controls.TextBlock]::new()
  $value.Text = '--'
  $value.FontSize = 12.5
  $value.FontWeight = 'Bold'
  $value.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x6A,0x1B,0x9A))
  $value.HorizontalAlignment = 'Right'
  $value.VerticalAlignment = 'Center'
  [System.Windows.Controls.Grid]::SetColumn($value, 2)
  $null = $row.Children.Add($value)
  $row.Margin = [System.Windows.Thickness]::new(2, 1, 2, 1)
  $dot.Tag = 'dot'
  return @{ Row = $row; Dot = $dot; Label = $label; Value = $value }
}

$rowCpu = New-TempRow 'CPU 温度'
$rowMem  = New-TempRow '内存 温度'
$rowGpu = New-TempRow 'GPU 温度'
$rowNvme = New-TempRow 'NVMe 固态'
foreach ($r in @($rowCpu, $rowMem, $rowGpu, $rowNvme)) { $null = $hoverPanel.Children.Add($r.Row) }

function Set-TempColor {
  param($dot, $valueText, $temp)
  if ($null -eq $temp) {
    $dot.Fill = [System.Windows.Media.Brushes]::LightGray
    return
  }
  $color = [System.Windows.Media.Color]::FromRgb(0x95, 0x75, 0xCD)   # 紫
  if ($temp -ge 80) { $color = [System.Windows.Media.Color]::FromRgb(0xC6, 0x28, 0x28) }  # 红
  elseif ($temp -ge 65) { $color = [System.Windows.Media.Color]::FromRgb(0xE6, 0x51, 0x00) }  # 橙
  $dot.Fill = [System.Windows.Media.SolidColorBrush]::new($color)
  $valueText.Foreground = [System.Windows.Media.SolidColorBrush]::new($color)
}

function Update-UI {
  $cpu = $state.cpu; $gpu = $state.gpu; $mem = $state.mem; $nvme = $state.nvme
  $rowCpu.Value.Text = if ($null -ne $cpu) { ('{0:F1}°C' -f $cpu) } else { '--' }
  $rowMem.Value.Text = if ($null -ne $mem) { ('{0:F1}°C' -f $mem) } else { '--' }
  $rowGpu.Value.Text = if ($null -ne $gpu) { ('{0:F1}°C' -f $gpu) } else { '--' }
  $rowNvme.Value.Text = if ($null -ne $nvme) { ('{0:F1}°C' -f $nvme) } else { '--' }
  Set-TempColor $rowCpu.Dot $rowCpu.Value $cpu
  Set-TempColor $rowMem.Dot $rowMem.Value $mem
  Set-TempColor $rowGpu.Dot $rowGpu.Value $gpu
  Set-TempColor $rowNvme.Dot $rowNvme.Value $nvme
}

# ---------- 页面切换(每5秒自动切换 温度信息/硬件信息, 鼠标悬停时停止切换) ----------
$script:showTemps = $false
$script:hoverActive = $false
$script:switchTick = 0

function Show-TempPage {
  $script:showTemps = $true
  $hoverPanel.Visibility = 'Visible'
  $idlePanel.Visibility = 'Collapsed'
  Update-UI
}
function Show-InfoPage {
  $script:showTemps = $false
  $idlePanel.Visibility = 'Visible'
  $hoverPanel.Visibility = 'Collapsed'
}
function Toggle-Page {
  if ($script:showTemps) { Show-InfoPage } else { Show-TempPage }
}

# ---------- 事件 ----------
$card.Add_MouseEnter({
  # 悬停: 停止自动切换, 固定显示温度页面
  $script:hoverActive = $true
  $script:switchTick = 0
  Show-TempPage
})
$card.Add_MouseLeave({
  # 移开: 恢复自动切换, 回到硬件信息页面
  $script:hoverActive = $false
  $script:switchTick = 0
  Show-InfoPage
})
$window.Add_MouseLeftButtonDown({
  try { $window.DragMove() } catch {}
})
$exitItem = [System.Windows.Controls.MenuItem]::new()
$exitItem.Header = '退出安安热能监控'
$exitItem.Add_Click({ $state.running = $false; $window.Close() })
$menu = [System.Windows.Controls.ContextMenu]::new()
$null = $menu.Items.Add($exitItem)
$card.ContextMenu = $menu

# ---------- 电池状态(每10秒刷新) ----------
$script:batteryTick = 0
function Update-Battery {
  try {
    $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
    $pct = [math]::Round($ps.BatteryLifePercent * 100)
    if ($pct -gt 100) { $pct = 100 }
    if ($pct -le 0) { $pct = 0 }
    $line = [string]$ps.PowerLineStatus
    $charge = [string]$ps.BatteryChargeStatus
    $state = '使用中'
    if ($line -eq 'Online') { $state = '电源' }
    if ($charge -match 'Charging') { $state = '充电中' }
    $batteryTextBlock.Text = "电池 $pct% · $state"
  } catch {}
}

$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  Update-UI
  $script:batteryTick++
  if ($script:batteryTick -ge 10) { $script:batteryTick = 0; Update-Battery }
  # 页面自动切换(每5秒一次, 鼠标悬停时暂停)
  if (-not $script:hoverActive) {
    $script:switchTick++
    if ($script:switchTick -ge 5) {
      $script:switchTick = 0
      Toggle-Page
    }
  }
  # 停止信号: 插件停止时写入该文件, 宠物优雅退出
  if (Test-Path $stopFile) {
    $state.running = $false
    try { $window.Close() } catch {}
  }
})
$timer.Start()

$window.Add_Closed({
  $state.running = $false
  try { ("{0},{1}" -f [int]$window.Left, [int]$window.Top) | Set-Content -Path $posFile -Encoding ASCII } catch {}
  try { Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue } catch {}
  try { Remove-Item -Path $stopFile -Force -ErrorAction SilentlyContinue } catch {}
  $timer.Stop()
  try { $window.Dispatcher.InvokeShutdown() } catch {}
})

# ---------- 初始位置(默认右下角/记忆位置) ----------
$wa = [System.Windows.SystemParameters]::WorkArea
$left = $wa.Right - 250
$top = $wa.Bottom - 380
if (Test-Path $posFile) {
  try {
    $parts = (Get-Content $posFile -ErrorAction Stop | Select-Object -First 1).Split(',')
    if ($parts.Count -ge 2) {
      $lx = [double]$parts[0]; $ly = [double]$parts[1]
      if ($lx -ge 0 -and $ly -ge 0 -and $lx -le $wa.Right - 80 -and $ly -le $wa.Bottom - 60) {
        $left = $lx; $top = $ly
      }
    }
  } catch {}
}
$window.Left = $left
$window.Top = $top

# ---------- 启动(ShowDialog: 窗口关闭即返回, 进程随之退出) ----------
Update-UI
Update-Battery
$null = $window.ShowDialog()

} catch {
  Write-ErrLog ("主逻辑异常: " + $_.Exception.ToString())
  Write-ErrLog ("位置: " + $_.InvocationInfo.PositionMessage)
  try { $state.running = $false } catch {}
} finally {
  # ---------- 清理 ----------
  try { $ps.Stop() } catch {}
  try { $runspace.Close() } catch {}
  try { Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue } catch {}
}
