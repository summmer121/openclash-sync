# luci-app-openclash-sync

> OpenWrt / iStoreOS LuCI 插件 — 将本机 OpenClash 配置**实时同步**到一台或多台对端设备，支持自动部署/修复、对端状态监控。

## ✨ 功能特性

- **一对多同步** — 支持同时向多台 OpenWrt/iStoreOS 推送 OpenClash 配置
- **实时监听** — 基于 `inotifywait -m -r`，文件变更后自动同步（5秒防抖）
- **周期兜底** — 可配置周期（默认300秒）补偿同步，设备重启/断网恢复后自动追上
- **自动部署/修复** — 对端未安装 OpenClash 或版本不一致时，自动备份并用本机 OpenClash 重装对端
- **对端状态面板** — LuCI 页面实时显示每个对端节点的 OpenClash 运行状态、版本、开机自启、最近同步时间
- **Web 全配置** — 所有参数均可通过 LuCI 页面配置，无需手改文件
- **手动操作** — 页面按钮：立即同步、启动/停止/重启服务、清空日志

## 📸 页面预览

### 配置页 — 全局设置 + 同步节点管理

- 全局：启用开关、防抖秒数、兜底周期、同步范围（8项可独立开关）
- 节点：新增/删除多个对端节点，每个节点独立配置 IP/端口/账号/认证方式/部署选项

### 状态页 — 对端状态 + 操作 + 日志

| 节点 | 地址 | 连接 | OpenClash状态 | 版本 | 自启 | 最近同步 | 结果 |
|------|------|------|------|------|------|------|------|
| 外网 | root@xxx:922 | ✅ 在线 | 🟢 运行中 | 0.47.038 | ✅ | 2026-06-30 17:22 | ok 同步完成 |

## 📦 安装

### 方式一：直接安装 IPK（推荐）

从 [Releases](../../releases) 下载最新 `.ipk`，上传到设备后：

```sh
opkg install luci-app-openclash-sync_*.ipk
```

### 方式二：手动部署文件

如果 `opkg` 安装失败，可手动复制文件：

```sh
# 将 files/ 下的内容复制到设备根目录
scp -r files/etc root@<设备IP>:/etc
scp -r files/usr root@<设备IP>:/usr
chmod +x /etc/init.d/openclash_sync /usr/bin/openclash_sync.sh
/etc/init.d/openclash_sync enable
/etc/init.d/openclash_sync start
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/*
/etc/init.d/uhttpd restart
```

## 🔧 依赖

| 依赖 | 说明 |
|------|------|
| `luci-base` | LuCI 基础框架 |
| `luci-compat` | Lua CBI 兼容层 |
| `rsync` | 文件同步 |
| `inotifywait` (inotify-tools) | 实时文件监听 |
| `openssh-client` | SSH 连接（Dropbear dbclient 兼容性不足） |
| `sshpass` | 密码认证模式（仅密码登录节点需要） |

安装依赖：

```sh
opkg update
opkg install luci-base luci-compat rsync inotifywait openssh-client sshpass
```

## ⚙️ 配置

安装后访问 **LuCI → 服务 → OpenClash Sync**

### 全局设置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| 启用服务 | ✅ | 总开关 |
| 防抖(秒) | 5 | 文件变化后等待几秒再同步 |
| 兜底周期(秒) | 300 | 周期补偿同步，重启/断网恢复后自动追上 |

### 同步范围

可独立开关以下目录/文件的同步：

- `/etc/config/openclash` — 主配置
- `/etc/openclash/config/` — 订阅配置
- `/etc/openclash/custom/` — 自定义规则
- `/etc/openclash/overwrite/` — 覆写配置
- `/etc/openclash/proxy_provider/`
- `/etc/openclash/rule_provider/`
- `/etc/openclash/game_rules/`
- 根目录 yaml/dat/mmdb/ipset 文件

自动排除：`core/`、`history/`、`cache/`、`run/`、`logs/`、`backup/`、`*.log`、`*.pid`

### 同步节点

每个节点可配置：

| 配置项 | 说明 |
|--------|------|
| 名称 | 节点标识 |
| IP/域名 | 对端地址 |
| 端口 | SSH 端口 |
| 用户 | SSH 用户名 |
| 认证方式 | SSH Key / 密码 |
| 私钥路径 | OpenSSH ed25519 密钥（Key 模式） |
| 密码 | SSH 密码（密码模式） |
| 同步后重载 | 同步完成后对端 `openclash reload` |
| 自动部署/修复 | 对端缺失或版本不一致时自动重装 |
| 版本不一致重装 | 开启后版本不匹配也重装 |
| 重装前备份 | 重装前备份对端 OpenClash |

## 🔑 SSH 免密配置（Key 模式）

```sh
# 本机生成密钥
ssh-keygen -t ed25519 -f /root/.ssh/openclash_sync_openssh_ed25519 -N ""

# 公钥写入对端（OpenWrt Dropbear 认读路径）
scp /root/.ssh/openclash_sync_openssh_ed25519.pub root@<对端>:/tmp/
ssh root@<对端> 'cat /tmp/openclash_sync_openssh_ed25519.pub >> /etc/dropbear/authorized_keys'
```

> ⚠️ OpenWrt Dropbear 的 authorized_keys 路径是 `/etc/dropbear/authorized_keys`，不是 `~/.ssh/authorized_keys`

## 🔄 同步流程

```
文件变更 → inotifywait 检测 → 5秒防抖
                                  ↓
            ┌─────────────────────────────────────┐
            │       遍历所有启用的同步节点          │
            │  ┌──────────────────────────────┐   │
            │  │ 1. SSH 连接对端               │   │
            │  │ 2. 检测对端 OpenClash 状态     │   │
            │  │ 3. 需要时自动部署/修复          │   │
            │  │ 4. rsync 同步配置文件          │   │
            │  │ 5. 对端 reload/restart OC      │   │
            │  └──────────────────────────────┘   │
            └─────────────────────────────────────┘
                                  ↓
                    300秒周期兜底（补偿漏同步）
```

## 🛠️ 命令行

```sh
# 手动触发一次同步
/usr/bin/openclash_sync.sh once

# 查看服务状态
/usr/bin/openclash_sync.sh status

# 查看对端节点状态
/usr/bin/openclash_sync.sh peer-status

# 启动/停止/重启服务
/etc/init.d/openclash_sync start
/etc/init.d/openclash_sync stop
/etc/init.d/openclash_sync restart
```

## 📁 文件结构

```
luci-app-openclash-sync/
├── Makefile                                          # OpenWrt SDK 编译定义
├── README.md
├── releases/                                         # 预编译 IPK
│   └── luci-app-openclash-sync_1.2.3-1_all.ipk
└── files/
    ├── etc/
    │   ├── config/openclash_sync                     # UCI 配置模板
    │   └── init.d/openclash_sync                    # init 服务（procd）
    └── usr/
        ├── bin/openclash_sync.sh                    # 核心同步脚本
        └── lib/lua/luci/
            ├── controller/openclash_sync.lua        # 路由控制器
            └── model/cbi/openclash_sync/
                ├── openclash_sync.lua               # 配置页 CBI
                └── status.lua                       # 状态/日志页 CBI
```

## ⚠️ 注意事项

1. **Dropbear SSH 兼容性** — OpenWrt 自带 dbclient 与某些 Dropbear 服务端存在兼容问题，建议安装 `openssh-client` 替代
2. **authorized_keys 路径** — OpenWrt Dropbear 认读 `/etc/dropbear/authorized_keys`
3. **对端需安装 rsync** — 密码认证节点还需安装 `openssh-client` 和 `sshpass`
4. **自动部署** — 会先备份对端再替换，备份目录 `/root/openclash_sync_remote_backup/`
5. **init stop 安全** — 进程清理通过 `/proc/cmdline` 精确匹配，不会误杀 SSH 管理会话

## 📄 License

MIT
