# luci-app-openclash-sync

> OpenWrt / iStoreOS LuCI 插件 — 将本机 OpenClash 配置**按变更实时同步**到一台或多台对端设备，支持对端状态监控与可选自动部署/修复。

## ✨ 功能特性

- **一对多同步** — 支持同时向多台 OpenWrt/iStoreOS 推送 OpenClash 配置
- **变更触发** — 基于 `inotifywait -m -r`，文件变更后自动同步（默认5秒防抖）
- **周期兜底可选** — `periodic_sync=0` 默认关闭；需要断网/重启补偿时可手动设置周期秒数
- **自动部署/修复默认关闭** — 高风险功能，仅确认需要由主设备替换对端 OpenClash 时再开启
- **SSH失败保护** — 对端版本检测 SSH 失败时不会再被误判为“未安装”，避免误触发 stop/重装
- **对端状态面板** — LuCI 页面显示每个对端节点的 OpenClash 运行状态、版本、开机自启、最近同步时间
- **Web 全配置** — 所有参数均可通过 LuCI 页面配置，无需手改文件
- **手动操作** — 页面按钮：立即同步、启动/停止/重启服务、清空日志

## 🆕 v1.2.7 重要修复

本版本针对“从节点 OpenClash 一会儿自动停止”的问题做了安全修复：

1. **默认关闭周期同步**：只在主设备 OpenClash 配置发生变更时同步，避免固定周期反复触发远端操作。
2. **修复 SSH 失败误判 missing**：版本检测连接失败时记录错误并跳过自动部署，不再把空输出当成“对端未安装 OpenClash”。
3. **自动部署保持默认关闭**：即使开启，也只有版本检测成功且确实缺失/不匹配时才会进入部署逻辑。
4. **不保留远端备份目录**：自动部署时以主设备为唯一配置源，不在从设备留下 `openclash_sync_remote_backup`，减少 overlay 占用。
5. **保护现有 UCI 配置**：IPK 声明 `/etc/config/openclash_sync` 为配置文件，升级时尽量保留用户已有节点配置。

## 📸 页面预览

### 配置页 — 对端状态 + 全局设置 + 同步节点管理

- 全局：启用开关、防抖秒数、可选兜底周期、日志文件、同步范围
- 节点：新增/删除多个对端节点，每个节点独立配置 IP/端口/账号/认证方式/同步后重载/自动部署开关

### 状态页 — 操作 + 服务状态 + 日志

| 节点 | 地址 | 连接 | OpenClash状态 | 版本 | 最近同步 | 结果 |
|------|------|------|------|------|------|------|
| 外网节点 | root@peer:22 | ✅ 在线 | 🟢 运行中 | 0.47.038 | 17:22:00 | ok 同步完成 |

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
| `openssh-client` | SSH 连接（建议，Dropbear dbclient 兼容性不足） |
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
| 兜底周期(秒) | 0 | `0=关闭`；需要周期补偿时填秒数，例如300 |
| 日志文件 | `/var/log/openclash_sync.log` | 同步日志路径 |

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
| 自动部署/修复 | 高风险选项，默认关闭；确认需要主设备重装对端时再开启 |

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

```text
文件变更 → inotifywait 检测 → 5秒防抖
                                  ↓
            ┌─────────────────────────────────────┐
            │       遍历所有启用的同步节点          │
            │  ┌──────────────────────────────┐   │
            │  │ 1. SSH 连接对端               │   │
            │  │ 2. 可选检测/部署 OpenClash     │   │
            │  │ 3. rsync 同步配置文件          │   │
            │  │ 4. 对端 reload/restart OC      │   │
            │  └──────────────────────────────┘   │
            └─────────────────────────────────────┘

可选：periodic_sync > 0 时按周期做补偿同步；默认关闭。
```

## 🛠️ 命令行

```sh
# 手动触发一次同步
/usr/bin/openclash_sync.sh once

# 查看服务状态
/usr/bin/openclash_sync.sh status

# 查看对端节点状态（60秒缓存，避免LuCI打开卡顿）
/usr/bin/openclash_sync.sh peer-status

# 启动/停止/重启服务
/etc/init.d/openclash_sync start
/etc/init.d/openclash_sync stop
/etc/init.d/openclash_sync restart
```

## 📁 文件结构

```text
luci-app-openclash-sync/
├── Makefile                                          # OpenWrt SDK 编译定义
├── README.md
├── releases/                                         # 预编译 IPK
│   └── luci-app-openclash-sync_1.2.7-1_all.ipk
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

1. **Dropbear SSH 兼容性** — OpenWrt 自带 dbclient 与某些 Dropbear 服务端存在兼容问题，建议安装 `openssh-client` 替代。
2. **authorized_keys 路径** — OpenWrt Dropbear 认读 `/etc/dropbear/authorized_keys`。
3. **对端需安装 rsync** — 密码认证节点还需安装 `openssh-client` 和 `sshpass`。
4. **自动部署高风险** — 主节点为唯一配置源，自动部署会直接替换对端 OpenClash 文件；默认关闭。
5. **周期同步默认关闭** — 需要断网/重启补偿时再设置 `periodic_sync`，否则只监听主设备变更。
6. **init stop 安全** — 进程清理通过 `/proc/cmdline` 精确匹配，不会误杀 SSH 管理会话。

## 📄 License

MIT
