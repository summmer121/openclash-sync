module("luci.controller.openclash_sync", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/openclash_sync") then
		return
	end

	entry({"admin", "services", "openclash_sync"}, alias("admin", "services", "openclash_sync", "config"), _("OpenClash Sync"), 60).dependent = true
	entry({"admin", "services", "openclash_sync", "config"}, cbi("openclash_sync"), _("配置"), 10).leaf = true
	entry({"admin", "services", "openclash_sync", "status"}, cbi("openclash_sync/status"), _("状态/日志"), 20).leaf = true
	entry({"admin", "services", "openclash_sync", "action"}, call("action"), nil).leaf = true
end

function action()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local act = http.formvalue("do") or ""
	local out = ""

	if act == "start" then
		out = sys.exec("/etc/init.d/openclash_sync start 2>&1")
	elseif act == "stop" then
		out = sys.exec("/etc/init.d/openclash_sync stop 2>&1")
	elseif act == "restart" then
		out = sys.exec("/etc/init.d/openclash_sync restart 2>&1")
	elseif act == "sync" then
		out = sys.exec("/usr/bin/openclash_sync.sh once 2>&1")
	elseif act == "clearlog" then
		out = sys.exec(">/var/log/openclash_sync.log 2>&1; echo log_cleared")
	else
		out = "unknown action"
	end

	http.prepare_content("text/plain; charset=utf-8")
	http.write(out)
end
