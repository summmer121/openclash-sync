local sys = require "luci.sys"
local disp = require "luci.dispatcher"

m = Map("openclash_sync", translate("OpenClash Sync"), translate("将本机 OpenClash 配置实时同步到一台或多台 OpenWrt/iStoreOS 设备。"))
m:chain("openclash_sync")

local function esc(s)
	return luci.util.pcdata(s or "")
end

-- 对端状态：先渲染骨架占位，AJAX异步加载
local act_url = disp.build_url("admin", "services", "openclash_sync", "action")
local peer_api_url = disp.build_url("admin", "services", "openclash_sync", "peer_status")
local local_api_url = disp.build_url("admin", "services", "openclash_sync", "local_status")

-- 本机状态卡片
local local_placeholder = [[
<div id="ocs_local_container" style="margin-bottom:12px">
  <div style="font-weight:bold;padding:4px 0 6px 0;border-bottom:1px solid #eee;margin-bottom:6px">本机 OpenClash 状态</div>
  <div id="ocs_local_loading" style="padding:8px;color:#888">⏳ 正在检测本机状态...</div>
  <div id="ocs_local_table" style="display:none"></div>
</div>
]]

-- 对端状态：先渲染骨架占位，AJAX异步加载
local peer_placeholder = [[
<div id="ocs_peer_container">
  <div id="ocs_peer_loading" style="text-align:center;padding:24px;color:#888">
    <span style="font-size:18px">⏳</span> 正在检测从节点状态...
  </div>
  <div id="ocs_peer_table" style="display:none"></div>
</div>
<div style="margin-top:10px">
<button type="button" class="btn cbi-button cbi-button-apply" id="ocs_btn_sync" style="margin-right:8px">立即同步</button>
<button type="button" class="btn cbi-button cbi-button-reload" id="ocs_btn_restart" style="margin-right:8px">重启服务</button>
<button type="button" class="btn cbi-button cbi-button-reset" id="ocs_btn_refresh">刷新状态</button>
<span id="ocs_act_msg" style="margin-left:10px;color:#888"></span>
</div>
<script type="text/javascript">
(function(){
	var peerUrl = "]] .. peer_api_url .. [[";
	var actUrl = "]] .. act_url .. [[";
	var localUrl = "]] .. local_api_url .. [[";

	function escHtml(s) {
		var d = document.createElement('div');
		d.appendChild(document.createTextNode(s || ''));
		return d.innerHTML;
	}

	function renderLocalStatus(d) {
		if (!d) return '<div style="color:#888;padding:8px">无数据</div>';
		var oc = escHtml(d.openclash_state || '-');
		if (d.openclash_state === 'running') oc = '<span style="color:#5cb85c">运行</span>';
		else if (d.openclash_state === 'inactive') oc = '<span style="color:#f0ad4e">停止</span>';
		else if (d.openclash_state === '未安装') oc = '<span style="color:#d9534f">未安装</span>';
		var cn = d.cn_net || '未知';
		var cn_badge = cn === 'up' ? '<span style="color:#5cb85c">正常</span>'
			: (cn === '未知' ? '<span style="color:#999">未知</span>' : '<span style="color:#d9534f">异常</span>');
		var px = d.px_net || '未知';
		var px_txt = px === 'up' ? ('<span style="color:#5cb85c">通</span>' + (d.px_loc ? ' <span style="color:#888">' + escHtml(d.px_loc) + '</span>' : ''))
			: (px === '未知' ? '<span style="color:#999">未知</span>' : '<span style="color:#d9534f">不通</span>');
		var lcfg = escHtml(d.local_config || '');
		if (!lcfg) lcfg = '<span style="color:#999">-</span>';
		var sel = escHtml(d.local_selection || '');
		if (!sel) sel = '<span style="color:#999">-</span>';
		var auto = d.openclash_enabled === '1' ? '<span style="color:#5cb85c">已启用</span>' : '<span style="color:#f0ad4e">未启用</span>';
		var h = '<table style="width:100%;border-collapse:collapse;font-size:12px">';
		h += '<tr style="font-weight:bold;border-bottom:2px solid">';
		h += '<td style="padding:6px 8px">OpenClash</td>';
		h += '<td style="padding:6px 8px">开机自启</td>';
		h += '<td style="padding:6px 8px">配置</td>';
		h += '<td style="padding:6px 8px">国内网</td>';
		h += '<td style="padding:6px 8px">科学上网</td>';
		h += '<td style="padding:6px 8px">版本</td>';
		h += '<td style="padding:6px 8px">节点选择</td>';
		h += '<td style="padding:6px 8px">刷新时间</td>';
		h += '</tr>';
		h += '<tr>';
		h += '<td style="padding:5px 8px">' + oc + '</td>';
		h += '<td style="padding:5px 8px">' + auto + '</td>';
		h += '<td style="padding:5px 8px">' + lcfg + '</td>';
		h += '<td style="padding:5px 8px">' + cn_badge + '</td>';
		h += '<td style="padding:5px 8px">' + px_txt + '</td>';
		h += '<td style="padding:5px 8px">' + escHtml(d.openclash_version || '-') + '</td>';
		h += '<td style="padding:5px 8px;max-width:300px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + sel + '">' + sel + '</td>';
		h += '<td style="padding:5px 8px;color:#888">' + escHtml(d.probe_time || '-') + '</td>';
		h += '</tr>';
		h += '</table>';
		return h;
	}

	function loadLocalStatus() {
		var loading = document.getElementById('ocs_local_loading');
		var table = document.getElementById('ocs_local_table');
		if (loading) loading.style.display = '';
		if (table) table.style.display = 'none';
		var xhr = new XMLHttpRequest();
		xhr.open('GET', localUrl, true);
		xhr.timeout = 30000;
		xhr.onreadystatechange = function() {
			if (xhr.readyState !== 4) return;
			if (loading) loading.style.display = 'none';
			if (xhr.status === 200) {
				try {
					var data = JSON.parse(xhr.responseText);
					if (table) {
						table.innerHTML = renderLocalStatus(data);
						table.style.display = '';
					}
				} catch(e) {
					if (table) {
						table.innerHTML = '<div style="color:#d9534f;padding:8px">解析失败: ' + escHtml(e.message) + '</div>';
						table.style.display = '';
					}
				}
			} else {
				if (table) {
					table.innerHTML = '<div style="color:#d9534f;padding:8px">获取失败 (HTTP ' + xhr.status + ')</div>';
					table.style.display = '';
				}
			}
		};
		xhr.send();
	}

	function renderPeerTable(nodes) {
		if (!nodes || nodes.length === 0) {
			return '<div style="color:#888;padding:8px">暂无节点</div>';
		}
		var h = '<table style="width:100%;border-collapse:collapse;font-size:12px">';
		h += '<tr style="font-weight:bold;border-bottom:2px solid">';
		h += '<td style="padding:6px 8px">节点</td>';
		h += '<td style="padding:6px 8px">地址</td>';
		h += '<td style="padding:6px 8px">连接</td>';
		h += '<td style="padding:6px 8px">OpenClash</td>';
		h += '<td style="padding:6px 8px">配置</td>';
		h += '<td style="padding:6px 8px">国内网</td>';
		h += '<td style="padding:6px 8px">科学上网</td>';
		h += '<td style="padding:6px 8px">版本</td>';
		h += '<td style="padding:6px 8px">最近同步</td>';
		h += '<td style="padding:6px 8px">结果</td>';
		h += '<td style="padding:6px 8px">刷新时间</td>';
		h += '</tr>';
		for (var i = 0; i < nodes.length; i++) {
			var n = nodes[i];
			var reachable = n.peer_reachable || '未知';
			var badge = reachable === 'yes' ? '<span style="color:#5cb85c">在线</span>'
				: (reachable === 'disabled' ? '停用' : '<span style="color:#d9534f">离线</span>');
			var oc = escHtml(n.openclash_state || '-');
			if (n.openclash_state === 'running') oc = '<span style="color:#5cb85c">运行</span>';
			else if (n.openclash_state === 'inactive') oc = '<span style="color:#f0ad4e">停止</span>';
			var cn = n.cn_net || '未知';
			var cn_badge = cn === 'up' ? '<span style="color:#5cb85c">正常</span>'
				: (cn === '未知' ? '<span style="color:#999">未知</span>' : '<span style="color:#d9534f">异常</span>');
			var px = n.px_net || '未知';
			var px_txt = px === 'up' ? ('<span style="color:#5cb85c">通</span>' + (n.px_loc ? ' <span style="color:#888">' + escHtml(n.px_loc) + '</span>' : ''))
				: (px === '未知' ? '<span style="color:#999">未知</span>' : '<span style="color:#d9534f">不通</span>');
			var ts = n.last_sync || '-';
			var m2 = ts.match(/(\d+:\d+:\d+)$/);
			if (m2) ts = m2[1];
			var rcfg = escHtml(n.remote_config || '');
			if (!rcfg) rcfg = '<span style="color:#999">-</span>';
			h += '<tr>';
			h += '<td style="padding:5px 8px">' + escHtml(n.name || n.section || '-') + '</td>';
			h += '<td style="padding:5px 8px">' + escHtml(n.target || '-') + '</td>';
			h += '<td style="padding:5px 8px">' + badge + '</td>';
			h += '<td style="padding:5px 8px">' + oc + '</td>';
			h += '<td style="padding:5px 8px">' + rcfg + '</td>';
			h += '<td style="padding:5px 8px">' + cn_badge + '</td>';
			h += '<td style="padding:5px 8px">' + px_txt + '</td>';
			h += '<td style="padding:5px 8px">' + escHtml(n.openclash_version || '-') + '</td>';
			h += '<td style="padding:5px 8px">' + escHtml(ts) + '</td>';
			h += '<td style="padding:5px 8px">' + escHtml(n.sync_state || '-') + ' ' + escHtml(n.sync_message || '') + '</td>';
			h += '<td style="padding:5px 8px;color:#888">' + escHtml(n.probe_time || '-') + '</td>';
			h += '</tr>';
		}
		h += '</table>';
		return h;
	}

	function loadPeerStatus() {
		var loading = document.getElementById('ocs_peer_loading');
		var table = document.getElementById('ocs_peer_table');
		if (loading) loading.style.display = '';
		if (table) table.style.display = 'none';
		var xhr = new XMLHttpRequest();
		xhr.open('GET', peerUrl, true);
		xhr.timeout = 30000;
		xhr.onreadystatechange = function() {
			if (xhr.readyState !== 4) return;
			if (xhr.status === 200) {
				try {
					var data = JSON.parse(xhr.responseText);
					var html = renderPeerTable(data.nodes || []);
					if (table) {
						table.innerHTML = html;
						table.style.display = '';
					}
				} catch(e) {
					if (table) {
						table.innerHTML = '<div style="color:#d9534f;padding:8px">解析状态失败: ' + escHtml(e.message) + '</div>';
						table.style.display = '';
					}
				}
			} else {
				if (table) {
					table.innerHTML = '<div style="color:#d9534f;padding:8px">获取状态失败 (HTTP ' + xhr.status + ')</div>';
					table.style.display = '';
				}
			}
			if (loading) loading.style.display = 'none';
		};
		xhr.ontimeout = function() {
			if (loading) loading.style.display = 'none';
			if (table) {
				table.innerHTML = '<div style="color:#f0ad4e;padding:8px">检测超时，从节点可能不可达</div>';
				table.style.display = '';
			}
		};
		xhr.send();
	}

	function doAct(act, label) {
		var msg = document.getElementById('ocs_act_msg');
		msg.style.color = '#888';
		msg.innerHTML = label + '中…';
		var xhr = new XMLHttpRequest();
		xhr.open('POST', actUrl, true);
		xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
		xhr.onreadystatechange = function() {
			if (xhr.readyState === 4) {
				if (xhr.status === 200) {
					msg.style.color = '#5cb85c';
					msg.innerHTML = label + '完成';
					if (act === 'refresh' || act === 'sync') {
						loadLocalStatus();
						loadPeerStatus();
					}
				} else {
					msg.style.color = '#d9534f';
					msg.innerHTML = label + '失败 (HTTP ' + xhr.status + ')';
				}
			}
		};
		xhr.send('do=' + encodeURIComponent(act));
	}

	var bs = document.getElementById('ocs_btn_sync');
	var br = document.getElementById('ocs_btn_restart');
	var bf = document.getElementById('ocs_btn_refresh');
	if (bs) bs.onclick = function(){ doAct('sync', '同步'); };
	if (br) br.onclick = function(){ doAct('restart', '重启服务'); };
	if (bf) bf.onclick = function(){ doAct('refresh', '刷新状态'); };

	// 页面加载后立即异步获取节点状态
	loadLocalStatus();
	loadPeerStatus();
})();
</script>]]

-- 本机状态
local_section = m:section(NamedSection, "main", "openclash_sync", translate("本机 OpenClash 状态"))
local_section.addremove = false
local_section.anonymous = true
lv = local_section:option(DummyValue, "_local_status", "")
lv.rawhtml = true
lv.default = local_placeholder

-- 对端状态
peer_section = m:section(NamedSection, "main", "openclash_sync", translate("对端 OpenClash 状态"))
peer_section.addremove = false
peer_section.anonymous = true
pv = peer_section:option(DummyValue, "_peer_status", "")
pv.rawhtml = true
pv.default = peer_placeholder

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
	m.uci:set("openclash_sync", sid, "known_hosts", "/root/.ssh/openclash_sync_openssh_known_hosts")
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
o.default = "/root/.ssh/openclash_sync_openssh_known_hosts"

o = n:option(Flag, "reload_remote", translate("同步后重载"))
o.default = "1"

o = n:option(Flag, "auto_deploy_openclash", translate("自动部署/修复"), translate("对端缺失或版本不一致时自动部署"))
o.default = "0"

function m.on_after_commit(self)
	luci.sys.call("/etc/init.d/openclash_sync enable >/dev/null 2>&1")
	luci.sys.call("/etc/init.d/openclash_sync restart >/dev/null 2>&1 &")
end

return m
