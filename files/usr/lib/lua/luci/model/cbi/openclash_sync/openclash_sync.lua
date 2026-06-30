local sys = require "luci.sys"

m = Map("openclash_sync", translate("OpenClash Sync"), translate("将本机 OpenClash 配置实时同步到一台或多台 OpenWrt/iStoreOS 设备。"))
m:chain("openclash_sync")

local function esc(s)
	return luci.util.pcdata(s or "")
end

local function parse_peer_status(text)
	local nodes = {}
	local cur = nil
	for line in (text or ""):gmatch("[^\r\n]+") do
		if line == "BEGIN_NODE" then cur = {}
		elseif line == "END_NODE" then
			if cur then nodes[#nodes + 1] = cur end
			cur = nil
		elseif cur then
			local k, v = line:match("^([^=]+)=(.*)$")
			if k then cur[k] = v end
		end
	end
	return nodes
end

-- 读缓存
local peer_raw = sys.exec("/usr/bin/openclash_sync.sh peer-status 2>&1")
local peers = parse_peer_status(peer_raw)

-- 纯文本卡片，不依赖table CSS
local lines = {}
if #peers == 0 then
	lines[#lines + 1] = '<div style="color:#888;padding:8px">暂无节点</div>'
else
	lines[#lines + 1] = [[<table style="width:100%;border-collapse:collapse;font-size:12px">
<tr style="font-weight:bold;border-bottom:2px solid">
<td style="padding:6px 8px">节点</td>
<td style="padding:6px 8px">地址</td>
<td style="padding:6px 8px">连接</td>
<td style="padding:6px 8px">OpenClash</td>
<td style="padding:6px 8px">版本</td>
<td style="padding:6px 8px">最近同步</td>
<td style="padding:6px 8px">结果</td>
</tr>]]
	for i, n in ipairs(peers) do
		local reachable = n.peer_reachable or "未知"
		local badge = reachable == "yes" and '<span style="color:#5cb85c">在线</span>' or (reachable == "disabled" and "停用" or '<span style="color:#d9534f">离线</span>')
		local oc = esc(n.openclash_state or "-")
		if n.openclash_state == "running" then oc = '<span style="color:#5cb85c">运行</span>'
		elseif n.openclash_state == "inactive" then oc = '<span style="color:#f0ad4e">停止</span>' end
		local ts = n.last_sync ~= "" and n.last_sync or "-"
		ts = ts:match("(%d+:%d+:%d+)$") or ts
		lines[#lines + 1] = string.format(
			'<tr><td style="padding:5px 8px">%s</td><td style="padding:5px 8px">%s</td><td style="padding:5px 8px">%s</td><td style="padding:5px 8px">%s</td><td style="padding:5px 8px">%s</td><td style="padding:5px 8px">%s</td><td style="padding:5px 8px">%s %s</td></tr>',
			esc(n.name or n.section or "-"), esc(n.target or "-"), badge, oc, esc(n.openclash_version or "-"), ts, esc(n.sync_state or "-"), esc(n.sync_message or "")
		)
	end
	lines[#lines + 1] = '</table>'
end
local peer_html = table.concat(lines, "\n")

-- 对端状态
peer_section = m:section(NamedSection, "main", "openclash_sync", translate("对端 OpenClash 状态"))
peer_section.addremove = false
peer_section.anonymous = true
pv = peer_section:option(DummyValue, "_peer_status", "")
pv.rawhtml = true
pv.default = peer_html

-- 全局设置
s = m:section(NamedSection, "main", "openclash_sync", translate("全局设置"))
s.addremove = false
s.anonymous = true

o = s:option(Flag, "enabled", translate("启用服务"))
o.default = "1"
o.rmempty = false

o = s:option(Value, "debounce", translate("防抖(秒)"), translate("文件变化后等待几秒再同步"))
o.datatype = "uinteger"
o.default = "5"
o.size = 4

o = s:option(Value, "periodic_sync", translate("兜底周期(秒)"), translate("重启/断网恢复后自动补偿"))
o.datatype = "uinteger"
o.default = "300"
o.size = 6

o = s:option(Value, "log_file", translate("日志文件"))
o.default = "/var/log/openclash_sync.log"
o.size = 28

scope = m:section(NamedSection, "main", "openclash_sync", translate("同步范围"))
scope.addremove = false
scope.anonymous = true

local flags = {
	{"sync_config_file", translate("主配置 /etc/config/openclash")},
	{"sync_config_dir", translate("订阅配置 config/")},
	{"sync_custom_dir", translate("自定义规则 custom/")},
	{"sync_overwrite_dir", translate("覆写配置 overwrite/")},
	{"sync_proxy_provider_dir", translate("proxy_provider/")},
	{"sync_rule_provider_dir", translate("rule_provider/")},
	{"sync_game_rules_dir", translate("game_rules/")},
	{"sync_root_assets", translate("根目录 yaml/dat/mmdb/ipset")}
}

for _, f in ipairs(flags) do
	o = scope:option(Flag, f[1], f[2])
	o.default = "1"
end

-- 同步节点
n = m:section(TypedSection, "node", translate("同步节点（一对多）"), translate("新增/删除对端节点，每次同步依次推送。"))
n.addremove = true
n.anonymous = true
n.template = "cbi/tblsection"
n.extedit = nil
n.sortable = true

function n.create(self, section)
	local sid = TypedSection.create(self, section)
	m.uci:set("openclash_sync", sid, "enabled", "1")
	m.uci:set("openclash_sync", sid, "name", "新节点")
	m.uci:set("openclash_sync", sid, "remote_port", "22")
	m.uci:set("openclash_sync", sid, "remote_user", "root")
	m.uci:set("openclash_sync", sid, "auth_mode", "key")
	m.uci:set("openclash_sync", sid, "ssh_key", "/root/.ssh/openclash_sync_openssh_ed25519")
	m.uci:set("openclash_sync", sid, "known_hosts", "/root/.ssh/openclash_sync_known_hosts")
	m.uci:set("openclash_sync", sid, "reload_remote", "1")
	m.uci:set("openclash_sync", sid, "auto_deploy_openclash", "0")
	return sid
end

o = n:option(Flag, "enabled", translate("启用"))
o.default = "1"

o = n:option(Value, "name", translate("名称"))
o.placeholder = "外网节点"
o.rmempty = false

o = n:option(Value, "remote_host", translate("IP/域名"))
o.placeholder = "www.example.com"
o.rmempty = false

o = n:option(Value, "remote_port", translate("端口"))
o.datatype = "port"
o.default = "22"
o.rmempty = false
o.size = 5

o = n:option(Value, "remote_user", translate("用户"))
o.default = "root"
o.rmempty = false
o.size = 6

o = n:option(ListValue, "auth_mode", translate("认证"))
o:value("key", translate("SSH Key"))
o:value("password", translate("密码"))
o.default = "key"

o = n:option(Value, "password", translate("密码"))
o.password = true
o:depends("auth_mode", "password")

o = n:option(Value, "ssh_key", translate("私钥路径"))
o.default = "/root/.ssh/openclash_sync_openssh_ed25519"
o:depends("auth_mode", "key")

o = n:option(Value, "known_hosts", translate("KnownHosts"))
o.default = "/root/.ssh/openclash_sync_known_hosts"

o = n:option(Flag, "reload_remote", translate("同步后重载"))
o.default = "1"

o = n:option(Flag, "auto_deploy_openclash", translate("自动部署/修复"), translate("对端缺失或版本不一致时自动部署"))
o.default = "0"

function m.on_after_commit(self)
	luci.sys.call("/etc/init.d/openclash_sync enable >/dev/null 2>&1")
	luci.sys.call("/etc/init.d/openclash_sync restart >/dev/null 2>&1 &")
end

return m
