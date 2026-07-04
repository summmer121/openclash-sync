module("luci.controller.openclash_sync", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/openclash_sync") then
		return
	end

	entry({"admin", "services", "openclash_sync"}, alias("admin", "services", "openclash_sync", "config"), _("OpenClash Sync"), 60).dependent = true
	entry({"admin", "services", "openclash_sync", "config"}, cbi("openclash_sync"), _("配置"), 10).leaf = true
	entry({"admin", "services", "openclash_sync", "status"}, cbi("openclash_sync/status"), _("状态/日志"), 20).leaf = true
	entry({"admin", "services", "openclash_sync", "action"}, call("action"), nil).leaf = true
	entry({"admin", "services", "openclash_sync", "peer_status"}, call("action_peer_status"), nil).leaf = true
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
	elseif act == "refresh" then
		out = sys.exec("rm -f /tmp/openclash_sync_peer_cache 2>/dev/null; /usr/bin/openclash_sync.sh peer-status 2>&1 >/dev/null; echo refreshed")
	elseif act == "clearlog" then
		out = sys.exec(">/var/log/openclash_sync.log 2>&1; echo log_cleared")
	else
		out = "unknown action"
	end

	http.prepare_content("text/plain; charset=utf-8")
	http.write(out)
end

function action_peer_status()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local raw = sys.exec("/usr/bin/openclash_sync.sh peer-status 2>&1")

	-- Parse BEGIN_NODE...END_NODE blocks into JSON array
	local json = require "luci.jsonc"
	local nodes = {}
	local cur = nil
	for line in raw:gmatch("[^\r\n]+") do
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

	http.prepare_content("application/json; charset=utf-8")
	http.write(json.stringify({ nodes = nodes }))
end
