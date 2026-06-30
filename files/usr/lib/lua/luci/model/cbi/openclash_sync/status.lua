local sys = require "luci.sys"

m = SimpleForm("openclash_sync_status", translate("OpenClash Sync"), translate("同步操作、服务状态、日志。"))
m.reset = false
m.submit = false

local function esc(s)
	return luci.util.pcdata(s or "")
end

local status = sys.exec("/usr/bin/openclash_sync.sh status 2>&1")
local log_file = sys.exec("uci -q get openclash_sync.main.log_file 2>/dev/null")
log_file = (log_file:gsub("%s+$", ""))
if log_file == "" then log_file = "/var/log/openclash_sync.log" end
local logs = sys.exec("tail -160 " .. log_file .. " 2>/dev/null")

-- 1. 操作按钮
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
  (new XHR()).get(L.url('admin/services/openclash_sync/action'), { 'do': act }, function(x, data) {
    box.textContent = x.responseText || 'OK';
    if (act != 'sync') setTimeout(function(){ location.reload(); }, 1200);
  });
  return false;
}
</script>
]]

-- 2. 服务状态
v = m:field(DummyValue, "status", translate("服务状态"))
v.rawhtml = true
v.default = "<pre style='white-space:pre-wrap;max-height:140px;overflow:auto;font-size:12px'>" .. esc(status) .. "</pre>"

-- 3. 最近日志
logv = m:field(DummyValue, "logs", translate("最近日志"))
logv.rawhtml = true
logv.default = "<pre style='white-space:pre-wrap;max-height:400px;overflow:auto;background:#111;color:#eee;padding:8px;font-size:12px'>" .. esc(logs) .. "</pre>"

return m
