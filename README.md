# Windows Proxy Kill-Switch（防直连泄露安全工具集）

专为 Windows 桌面 AI 客户端（**Claude Desktop / Claude Code / Google Antigravity** 等）设计的**内核级防直连泄露（Kill-Switch）与路由加固工具集**。

## 🛡️ 为什么需要它？

仅在系统设置或环境变量里配置本地代理（如 `127.0.0.1:10808`）并不等于“代理断开就会断网”：
1. **默认出站放行**：Windows Defender 防火墙默认允许所有出站连接，部分商店版/Electron 应用甚至自带全局 `Outbound Allow` 放行规则。一旦代理闪断、重启，或底层库回退 `DIRECT` / 发送 QUIC UDP 443 / WebRTC STUN / 直连 DNS，请求会直接走本地宽带出口裸连。
2. **绕过大陆规则误直连**：在 `Bypass CN` 白名单路由下，部分关联遥测/CDN 域名（如 `statsig`、`sentry`、`intercom` 等）若未显式前置标为 `proxy`，命中 `geoip:cn` / `geosite:cn` 后会被本地代理内核直接放行直连。
3. **系统定位 API 暴露**：Windows 桌面的 `NonPackaged` 定位权限默认若为 `Allow`，Electron / WebView 应用可通过系统定位服务扫描周边 Wi-Fi 获取真实物理坐标。

## 🔧 工具清单

| 文件 | 作用 |
|---|---|
| `apply_killswitch.ps1` | 自动发现目标程序（Claude MSIX 容器 + Claude Code + Antigravity 等）并写入 Windows 内核防火墙 `Block` 规则，**仅放行 `127.0.0.0/8` 与 `::1` 回环地址** |
| `rollback_killswitch.ps1` | 一键移除对应规则组的所有防火墙规则，无损回滚 |
| `patch_v2rayn_routing.py` | 自动备份 `v2rayN` 数据库 `guiNDB.db`，并在 `direct` 规则之前注入 Claude / Anthropic / Antigravity / Google 关联域名的强制 `proxy` 规则 |

## 🚀 使用方法

### 1. 应用内核级防火墙 Kill-Switch（需管理员权限 PowerShell）

```powershell
# 仅锁定防火墙（代理一掉，目标应用立刻物理断网）
powershell -ExecutionPolicy Bypass -File .\apply_killswitch.ps1

# 同时关闭桌面非打包应用的 Windows 系统定位权限
powershell -ExecutionPolicy Bypass -File .\apply_killswitch.ps1 -DenyNonPackagedLocation

# 如需额外锁定其他桌面程序（如 Cursor / Codex 等）
powershell -ExecutionPolicy Bypass -File .\apply_killswitch.ps1 -ExtraPrograms "C:\Path\To\App.exe"
```

> **原理说明**：Windows 防火墙中 `Block` 规则无条件覆盖任何 `Allow` 规则。规则封锁 `0.0.0.0-126.255.255.255`、`128.0.0.0-255.255.255.255`、`::` 与 `::2-ffff:...` 的所有协议（TCP / UDP / ICMP / QUIC），因此本地进程间通信与 `127.0.0.1:10808` 代理完全不受影响，而任何直连外网流量都会在内核层直接丢弃。

### 2. 加固 v2rayN 白名单路由（防内部误直连）

1. 先完全退出 `v2rayN`（避免内存状态覆盖数据库）
2. 运行脚本：
   ```powershell
   python .\patch_v2rayn_routing.py --db "你的路径\v2rayN\guiConfigs\guiNDB.db"
   ```
3. 重新启动 `v2rayN` 即可自动生成新路由配置（原数据库会自动备份为 `guiNDB.backup_<时间戳>.db`）。

### 3. 一键回滚防火墙规则

```powershell
powershell -ExecutionPolicy Bypass -File .\rollback_killswitch.ps1
```

## ⚠️ 注意事项

- 若 Claude Desktop 或 Antigravity 升级了版本号目录，重新运行一次 `apply_killswitch.ps1` 即可自动重新发现并覆盖更新规则。
- 请以管理员身份运行 PowerShell 执行防火墙修改脚本。
