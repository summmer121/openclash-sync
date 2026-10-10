#!/bin/sh
# openclash-sync remote selection helper (runs ON the peer node).
# Reads pairs from stdin: <group>\n<node>\n ... and PUTs each to the local clash API.
# Requires: local clash API running; auth from dashboard_password or c2.yaml secret.
api="http://127.0.0.1:9090"
apisec=
# prefer dashboard_password (has the real secret), fall back to yaml secret
apisec=$(uci -q get openclash.config.dashboard_password 2>/dev/null)
if [ -z "$apisec" ]; then
  cfg=$(uci -q get openclash.config.config_path 2>/dev/null)
  [ -n "$cfg" ] && [ -f "$cfg" ] && apisec=$(grep -E "^secret:" "$cfg" 2>/dev/null | head -1 | awk '{print $2}')
  # strip empty '' literal
  [ "$apisec" = "''" ] && apisec=
fi
changed=0
while IFS= read -r grp; do
  IFS= read -r node || break
  [ -z "$grp" ] && continue
  if [ -n "$apisec" ]; then
    cur=$(curl -s -m5 -H "Authorization: Bearer $apisec" "$api/proxies/$grp" 2>/dev/null | jsonfilter -e "@.now" 2>/dev/null)
  else
    cur=$(curl -s -m5 "$api/proxies/$grp" 2>/dev/null | jsonfilter -e "@.now" 2>/dev/null)
  fi
  [ -z "$cur" ] && continue
  [ "$cur" = "$node" ] && continue
  if [ -n "$apisec" ]; then
    code=$(curl -s -m8 -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $apisec" -X PUT --data "{\"name\":\"$node\"}" "$api/proxies/$grp" 2>/dev/null)
  else
    code=$(curl -s -m8 -o /dev/null -w "%{http_code}" -X PUT --data "{\"name\":\"$node\"}" "$api/proxies/$grp" 2>/dev/null)
  fi
  [ "$code" = "204" ] && changed=$((changed+1)) && echo "switched [$grp] -> $node"
done
echo "selection_changed=$changed"
