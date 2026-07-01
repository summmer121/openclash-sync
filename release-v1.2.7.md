## v1.2.7 — OpenClash Sync Safety Fix

本版本重点修复从节点 OpenClash 被误停止/误重装的安全问题。

### 关键修复

- 默认关闭周期同步：`periodic_sync=0`，只在主设备配置发生变更时同步。
- 修复 SSH 版本检测失败误判：连接失败时记录错误并跳过自动部署，不再把空输出当成“对端未安装 OpenClash”。
- 自动部署/修复保持默认关闭，并在 LuCI 中标注为高风险选项。
- 自动部署不再在从设备保留远端备份目录，避免占用有限 overlay 空间。
- IPK 声明 `/etc/config/openclash_sync` 为配置文件，升级时尽量保留已有节点配置。
- README 已同步更新安装、配置、注意事项和 v1.2.7 修复说明。

### 验证

- `sh -n files/usr/bin/openclash_sync.sh` 通过。
- `sh -n files/etc/init.d/openclash_sync` 通过。
- IPK control/data/conffiles 结构校验通过。

### 安装

下载附件：`luci-app-openclash-sync_1.2.7-1_all.ipk`

```sh
opkg install luci-app-openclash-sync_1.2.7-1_all.ipk
/etc/init.d/openclash_sync restart
```
