local sys = require "luci.sys"

m = SimpleForm("openclash_sync_status", translate("OpenClash Sync"), translate("对端 OpenClash 状态、同步操作、服务状态、日志。"))
m.reset = false
m.submit = false

local function esc(s)
	return luci.util.pcdata(s or "")
end

local function parse_peer_status(text)
	local nodes = {}
	local cur = nil
	for line in (text or ""):gmatch("[^\r\n]+") do
		if line == "BEGIN_NODE" then
			cur = {}
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

local peer_raw = sys.exec("/usr/bin/openclash_sync.sh peer-status 2>&1")
local peers = parse_peer_status(peer_raw)
local status = sys.exec("/usr/bin/openclash_sync.sh status 2>&1")
local service = sys.exec("/etc/init.d/openclash_sync enabled >/dev/null 2>&1; echo enabled=$?")
local log_file = sys.exec("uci -q get openclash_sync.main.log_file 2>/dev/null")
log_file = (log_file:gsub("%s+$", ""))
if log_file == "" then log_file = "/var/log/openclash_sync.log" end
local logs = sys.exec("tail -160 " .. log_file .. " 2>/dev/null")

-- 1. 对端 OpenClash 状态（最上方）
peer = m:field(DummyValue, "peer_openclash", translate("对端 OpenClash 状态"))
peer.rawhtml = true
local rows = {}
rows[#rows + 1] = [[<table class="table cbi-section-table" style="width:100%;margin-bottom:0">
<thead><tr style="font-size:13px">
<th style="width:10%">节点</th><th style="width:16%">地址</th><th style="width:8%">连接</th>
<th style="width:10%">OpenClash</th><th style="width:10%">版本</th><th style="width:7%">自启</th>
<th style="width:16%">最近同步</th><th style="width:15%">结果</th>
</tr></thead><tbody>]]
if #peers == 0 then
	rows[#rows + 1] = "<tr><td colspan='8' style='text-align:center;color:#888'>未配置同步节点</td></tr>"
else
	for _, n in ipairs(peers) do
		local reachable = n.peer_reachable or "未知"
		local badge = reachable == "yes" and '<span style="color:#5cb85c">在线</span>' or (reachable == "disabled" and '<span style="color:#999">未启用</span>' or '<span style="color:#d9534f">离线</span>')
		local enabled = n.openclash_enabled == "1" and "✅" or (n.openclash_enabled == "0" and "❌" or esc(n.openclash_enabled or "-"))
		local oc_state = esc(n.openclash_state or "-")
		if n.openclash_state == "running" then oc_state = '<span style="color:#5cb85c">运行中</span>'
		elseif n.openclash_state == "inactive" then oc_state = '<span style="color:#f0ad4e">未运行</span>' end
		rows[#rows + 1] = string.format(
			"<tr><td>%s</td><td style='font-size:12px'>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td style='font-size:12px'>%s</td><td>%s %s</td></tr>",
			esc(n.name), esc(n.target), badge, oc_state, esc(n.openclash_version), enabled,
			esc(n.last_sync ~= "" and n.last_sync or "-"), esc(n.sync_state or "-"), esc(n.sync_message or "")
		)
	end
end
rows[#rows + 1] = "</tbody></table>"
peer.default = table.concat(rows, "\n")

-- 2. 操作按钮（对端状态下方）
btn = m:field(DummyValue, "actions", translate("操作"))
btn.rawhtml = true
btn.default = [[
<div style="display:flex;gap:8px;flex-wrap:wrap;margin:4px 0">
  <button class="btn cbi-button cbi-button-apply" onclick="return ocsAction('sync')">立即同步全部节点</button>
  <button class="btn cbi-button cbi-button-reload" onclick="return ocsAction('restart')">重启服务</button>
  <button class="btn cbi-button cbi-button-reset" onclick="return ocsAction('stop')">停止服务</button>
  <button class="btn cbi-button" onclick="return ocsAction('start')">启动服务</button>
  <button class="btn cbi-button cbi-button-remove" onclick="return ocsAction('clearlog')">清空日志</button>
</div>
<pre id="ocs_action_result" style="white-space:pre-wrap;max-height:180px;overflow:auto;background:#111;color:#eee;padding:6px;display:none;font-size:12px"></pre>
<script type="text/javascript">
function ocsAction(act) {
  var box = document.getElementById('ocs_action_result');
  box.style.display = 'block';
  box.textContent = '执行中: ' + act + ' ...';
  XHR.get(L.url('admin/services/openclash_sync/action'), { 'do': act }, function(x, data) {
    box.textContent = x.responseText || 'OK';
    if (act != 'sync') setTimeout(function(){ location.reload(); }, 1200);
  });
  return false;
}
</script>
]]

-- 3. 服务状态总览（中下方）
v = m:field(DummyValue, "status", translate("服务状态"))
v.rawhtml = true
v.default = "<pre style='white-space:pre-wrap;max-height:140px;overflow:auto;font-size:12px'>" .. esc(status .. "\n" .. service) .. "</pre>"

-- 4. 最近日志（最底部）
logv = m:field(DummyValue, "logs", translate("最近日志"))
logv.rawhtml = true
logv.default = "<pre style='white-space:pre-wrap;max-height:400px;overflow:auto;background:#111;color:#eee;padding:8px;font-size:12px'>" .. esc(logs) .. "</pre>"

return m
