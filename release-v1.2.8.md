# luci-app-openclash-sync v1.2.8-1

## 新功能

### 1. 节点选择同步(方案 A)
主设备在 OpenClash 切换代理节点后,从设备自动跟切同名策略组的同名节点。

- 独立 inotify 监听 `/etc/openclash/history/*.db`(`modify` 事件),3 秒防抖
- 通过对端本地 Clash API(`127.0.0.1:9090`)切换,**不同步 db 文件**,不污染对端测速/运行状态,不暴露公网端口
- 仅切换"组名与节点名都存在且不一致"的策略组
- 支持中文 + emoji 节点名(直接走 curl URL path,实测 HTTP 204)
- 新增开关 `option sync_selection '1'`(默认开,置 0 关闭)
- 节点跟切完成后同步刷新该节点"最近同步"时间戳

### 2. 对端状态表格增强
- 新增 **国内网络** 列(实时检测国内连通性)
- 新增 **科学上网** 列(实时检测代理出口 + 落地地区)
- 新增 **刷新时间** 列(每行数据的实际探测时刻,避免被 60s 缓存误导)
- 新增 **重启服务** / **刷新状态** 两个操作按钮(AJAX 调用,完成后自动刷新页面)

## 修复
- **init 脚本进程累积**:`cleanup_leftovers` 匹配规则收窄导致新监听器(选择监听器)杀不干净,重启时进程越攒越多。已改为通用匹配 `inotifywait *.../etc/openclash*`,重启不再残留。
- 继承并巩固 v1.2.7 的误停安全修复:`periodic_sync` 默认 `0`(关闭周期同步),`periodic_loop` 加 `-gt 0` 守卫。

## 安装
```
opkg install luci-app-openclash-sync_1.2.8-1_all.ipk
```
