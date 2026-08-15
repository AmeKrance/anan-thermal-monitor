// anan-thermal-monitor · DeepSeek Harness (DSH) 静态插件 Host 半部
//
// 功能：启动/停止桌宠进程（assets/desktop-pet.ps1，WPF 透明悬浮窗 +
// LibreHardwareMonitor 温度采集），插件停止时通过停止信号文件让桌宠优雅退出。
//
// 说明：这是 npm 包插件（经 dsh plugin --profile <name> add 安装），运行在完整
// Node 环境，可直接使用 node:fs / node:path / node:os / node:child_process 等
// 内置模块（不受动态插件的 Builtin 限制）。所有资源路径基于 import.meta.url
// 相对本包定位，可随包任意部署，无需任何配置。

import { fileURLToPath } from 'node:url'
import path from 'node:path'
import os from 'node:os'
import fs from 'node:fs'
import { spawn } from 'node:child_process'

export const name = 'anan-thermal-monitor'

/** 包根目录（node_modules/anan-thermal-monitor/ 或本地安装目录） */
const PKG_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
/** 桌宠脚本 */
const PET_SCRIPT = path.join(PKG_ROOT, 'assets', 'desktop-pet.ps1')
/** 运行时临时目录（不污染包目录） */
const TEMP_DIR = path.join(os.tmpdir(), 'anan-thermal-monitor')

export const apply = (ctx) => {
  try {
    fs.mkdirSync(TEMP_DIR, { recursive: true })
  } catch { /* 忽略 */ }

  const PID_FILE = path.join(TEMP_DIR, 'desktop-pet.pid')
  const DATA_FILE = path.join(TEMP_DIR, 'desktop-pet-data.json')
  const STOP_FILE = path.join(TEMP_DIR, 'desktop-pet-stop.flag')

  let proc = null

  const startPet = () => {
    if (proc && proc.exitCode === null) return { running: true, pid: proc.pid }
    try {
      proc = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', PET_SCRIPT], {
        cwd: PKG_ROOT,
        stdio: 'ignore',
        windowsHide: true,
      })
      const h = proc
      h.once('error', () => { if (proc === h) proc = null })
      h.once('exit', () => { if (proc === h) proc = null })
      return { running: true, pid: h.pid }
    } catch (e) {
      return { running: false, error: String((e && e.message) || e) }
    }
  }

  const stopPet = () => {
    if (proc) {
      try { proc.kill() } catch { /* 已退出 */ }
      proc = null
    }
    // 停止信号：提权的桌宠进程轮询到该文件后优雅退出
    // （非提权进程无法强杀管理员桌宠，必须用信号文件）
    try {
      fs.writeFileSync(STOP_FILE, 'stop')
    } catch { /* 忽略 */ }
    return { stopped: true }
  }

  ctx.effect(() => {
    const r = startPet()
    if (!r.running) console.error(`[anan-thermal-monitor] 桌宠启动失败: ${JSON.stringify(r)}`)
    return () => stopPet()
  })

  const readJson = () => {
    try {
      return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'))
    } catch { return null }
  }
  const readPid = () => {
    try {
      const n = parseInt(fs.readFileSync(PID_FILE, 'utf8').trim(), 10)
      return Number.isFinite(n) && n > 0 ? n : null
    } catch { return null }
  }

  // 若宿主环境提供 harness（动态插件式 RPC），注册状态查询；
  // 静态包环境下缺失则跳过（桌宠本身是完整功能）。
  const h = (typeof harness !== 'undefined') ? harness : undefined
  if (h && typeof h.handle === 'function') {
    h.handle('pet-status', async () => {
      const pid = readPid()
      return { running: !!proc || !!pid, pid: proc ? proc.pid : pid }
    })
    h.handle('pet-temps', async () => readJson())
    h.handle('pet-stop', async () => stopPet())
    h.handle('pet-start', async () => startPet())
  }
}
