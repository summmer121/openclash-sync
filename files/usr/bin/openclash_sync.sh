#!/bin/sh
# OpenClash Sync - realtime one-to-many OpenClash configuration sync for OpenWrt

CONFIG="openclash_sync"
MAIN="main"
STATUS_FILE="/tmp/openclash_sync.status"
NODE_STATUS_DIR="/tmp/openclash_sync_nodes"
mkdir -p "$NODE_STATUS_DIR"

get_cfg() {
  uci -q get "$CONFIG.$1.$2" 2>/dev/null || echo "$3"
}

get_bool_sec() {
  local sec="$1" opt="$2" def="$3" v
  v="$(get_cfg "$sec" "$opt" "$def")"
  [ "$v" = "1" ] || [ "$v" = "true" ] || [ "$v" = "yes" ]
}

LOG="$(get_cfg "$MAIN" log_file /var/log/openclash_sync.log)"
DEBOUNCE="$(get_cfg "$MAIN" debounce 5)"
PERIODIC_SYNC="$(get_cfg "$MAIN" periodic_sync 300)"
LOCK="/tmp/openclash_sync.lock"
PENDING="/tmp/openclash_sync.pending"
DEBOUNCE_LOCK="/tmp/openclash_sync.debounce"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
  logger -t openclash-sync "$*" 2>/dev/null || true
}

status_set() {
  {
    echo "last_update=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "state=$1"
    echo "message=$2"
  } > "$STATUS_FILE"
}

node_status_set() {
  local sec="$1" state="$2" msg="$3"
  {
    echo "last_update=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "state=$state"
    echo "message=$msg"
  } > "$NODE_STATUS_DIR/$sec"
}

node_count_enabled() {
  uci -q show "$CONFIG" | sed -n "s/^$CONFIG\.\([^=]*\)=node$/\1/p" | while read sec; do
    get_bool_sec "$sec" enabled 1 && echo "$sec"
  done | wc -l
}

sync_dir_to_node() {
  local sec="$1" enabled_opt="$2" src="$3" dst="$4" rsync_ssh="$5" user="$6" host="$7"
  get_bool_sec "$MAIN" "$enabled_opt" 1 || return 0
  [ -d "$src" ] || return 0
  rsync -az --delete -e "$rsync_ssh" \
    --exclude='core/' --exclude='history/' --exclude='cache/' --exclude='run/' --exclude='logs/' \
    --exclude='backup/' --exclude='*.log' --exclude='*.pid' \
    "$src/" "$user@$host:$dst/" >>"$LOG" 2>&1
}

local_openclash_version() {
  opkg list-installed 2>/dev/null | awk '$1=="luci-app-openclash"{print $3; exit}'
}

prepare_openclash_payload() {
  local payload="/tmp/openclash_sync_openclash_payload.tgz"
  local list="/tmp/openclash_sync_openclash_files.txt"
  : > "$list"

  opkg files luci-app-openclash 2>/dev/null | sed '1d' | while read f; do
    [ -e "$f" ] && echo "${f#/}"
  done >> "$list"

  # 确保运行/配置关键目录存在时也会带上。
  for p in etc/config/openclash etc/init.d/openclash etc/openclash usr/share/openclash usr/lib/lua/luci/controller/openclash.lua usr/lib/lua/luci/model/cbi/openclash usr/lib/lua/luci/view/openclash www/luci-static/resources/openclash usr/share/ucitrack/luci-app-openclash.json usr/lib/opkg/info/luci-app-openclash.control usr/lib/opkg/info/luci-app-openclash.list usr/lib/opkg/info/luci-app-openclash.postinst usr/lib/opkg/info/luci-app-openclash.prerm; do
    [ -e "/$p" ] && echo "$p"
  done >> "$list"

  sort -u "$list" > "$list.sorted"
  tar -czf "$payload" -C / -T "$list.sorted" >>"$LOG" 2>&1
  echo "$payload"
}

ensure_remote_openclash() {
  local sec="$1" name="$2" ssh_base="$3" rsync_ssh="$4" user="$5" host="$6"
  get_bool_sec "$sec" auto_deploy_openclash 0 || return 0

  local local_ver remote_ver need_deploy backup force payload ts
  local_ver="$(local_openclash_version)"
  [ -n "$local_ver" ] || { log "[$name] local OpenClash package not found"; node_status_set "$sec" error "本机未安装 luci-app-openclash"; return 1; }

  remote_ver="$($ssh_base "$user@$host" "opkg list-installed 2>/dev/null | awk '\''\$1==\"luci-app-openclash\"{print \$3; exit}'\''; [ -f /usr/lib/opkg/info/luci-app-openclash.control ] && awk -F': ' '\''\$1==\"Version\"{print \$2; exit}'\'' /usr/lib/opkg/info/luci-app-openclash.control" 2>/dev/null | tail -1)"
  force="$(get_cfg "$sec" force_reinstall_mismatch 1)"
  need_deploy=0
  if [ -z "$remote_ver" ]; then
    need_deploy=1
    log "[$name] remote OpenClash missing, will deploy local version $local_ver"
  elif [ "$remote_ver" != "$local_ver" ] && [ "$force" = "1" ]; then
    need_deploy=1
    log "[$name] remote OpenClash version mismatch: remote=$remote_ver local=$local_ver, will reinstall"
  else
    log "[$name] remote OpenClash ok: remote=$remote_ver local=$local_ver"
  fi
  [ "$need_deploy" = "1" ] || return 0

  node_status_set "$sec" deploying "部署 OpenClash 中"
  backup="$(get_cfg "$sec" backup_before_deploy 1)"
  ts="$(date '+%Y%m%d_%H%M%S')"

  if [ "$backup" = "1" ]; then
    $ssh_base "$user@$host" "mkdir -p /root/openclash_sync_remote_backup && tar -czf /root/openclash_sync_remote_backup/openclash_before_deploy_$ts.tgz /etc/config/openclash /etc/openclash /etc/init.d/openclash /usr/share/openclash /usr/lib/lua/luci/controller/openclash.lua /usr/lib/lua/luci/model/cbi/openclash /usr/lib/lua/luci/view/openclash /www/luci-static/resources/openclash /usr/share/ucitrack/luci-app-openclash.json /usr/lib/opkg/info/luci-app-openclash.* 2>/dev/null || true" >>"$LOG" 2>&1
  fi

  payload="$(prepare_openclash_payload)"
  rsync -az -e "$rsync_ssh" "$payload" "$user@$host:/tmp/openclash_sync_openclash_payload.tgz" >>"$LOG" 2>&1 || return 1

  $ssh_base "$user@$host" "
    /etc/init.d/openclash stop >/tmp/openclash_sync_stop.log 2>&1 || true
    rm -rf /etc/config/openclash /etc/openclash /etc/init.d/openclash /usr/share/openclash /usr/lib/lua/luci/controller/openclash.lua /usr/lib/lua/luci/model/cbi/openclash /usr/lib/lua/luci/view/openclash /www/luci-static/resources/openclash /usr/share/ucitrack/luci-app-openclash.json /usr/lib/opkg/info/luci-app-openclash.*
    tar -xzf /tmp/openclash_sync_openclash_payload.tgz -C /
    chmod +x /etc/init.d/openclash /usr/share/openclash/*.sh /usr/share/openclash/*.lua 2>/dev/null || true
    if [ -f /usr/lib/opkg/info/luci-app-openclash.control ]; then
      ver=\$(awk -F': ' '/^Version:/{print \$2; exit}' /usr/lib/opkg/info/luci-app-openclash.control)
      if [ -n \"\$ver\" ] && [ -f /usr/lib/opkg/status ]; then
        awk -v ver=\"\$ver\" 'BEGIN{inpkg=0} /^Package: luci-app-openclash$/{inpkg=1; print; next} /^Package: /{inpkg=0} inpkg && /^Version: /{print \"Version: \" ver; next} {print}' /usr/lib/opkg/status > /tmp/opkg_status_openclash_sync && mv /tmp/opkg_status_openclash_sync /usr/lib/opkg/status
      fi
    fi
    /etc/init.d/openclash enable >/tmp/openclash_sync_enable.log 2>&1 || true
    rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
    /etc/init.d/rpcd restart >/tmp/openclash_sync_rpcd.log 2>&1 || true
    /etc/init.d/uhttpd restart >/tmp/openclash_sync_uhttpd.log 2>&1 || true
  " >>"$LOG" 2>&1 || { node_status_set "$sec" error "OpenClash部署失败"; return 1; }

  log "[$name] OpenClash deployed: $local_ver"
  node_status_set "$sec" deploying "OpenClash部署完成"
  return 0
}

sync_node() {
  local sec="$1"
  get_bool_sec "$sec" enabled 1 || return 0

  local name host port user auth password key known reload ssh_base rsync_ssh
  name="$(get_cfg "$sec" name "$sec")"
  host="$(get_cfg "$sec" remote_host '')"
  port="$(get_cfg "$sec" remote_port 22)"
  user="$(get_cfg "$sec" remote_user root)"
  auth="$(get_cfg "$sec" auth_mode key)"
  password="$(get_cfg "$sec" password '')"
  key="$(get_cfg "$sec" ssh_key /root/.ssh/openclash_sync_openssh_ed25519)"
  known="$(get_cfg "$sec" known_hosts /root/.ssh/openclash_sync_known_hosts)"
  reload="$(get_cfg "$sec" reload_remote 1)"

  if [ -z "$host" ]; then
    log "[$name] skipped: empty host"
    node_status_set "$sec" error "未配置对端地址"
    return 1
  fi

  if [ "$auth" = "password" ]; then
    ssh_base="sshpass -p $password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=$known -o ConnectTimeout=20 -p $port"
  else
    ssh_base="ssh -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=$known -o ConnectTimeout=20 -p $port"
  fi
  rsync_ssh="$ssh_base"

  log "[$name] sync start to $user@$host:$port"
  node_status_set "$sec" syncing "同步中"

  if ! $ssh_base "$user@$host" "mkdir -p /etc/openclash/config /etc/openclash/custom /etc/openclash/overwrite /etc/openclash/proxy_provider /etc/openclash/rule_provider /etc/openclash/game_rules /etc/config" >>"$LOG" 2>&1; then
    log "[$name] remote connect failed"
    node_status_set "$sec" error "远端连接失败"
    return 1
  fi

  if ! ensure_remote_openclash "$sec" "$name" "$ssh_base" "$rsync_ssh" "$user" "$host"; then
    log "[$name] ensure OpenClash failed"
    return 1
  fi

  if get_bool_sec "$MAIN" sync_config_file 1; then
    if ! rsync -az --delete -e "$rsync_ssh" /etc/config/openclash "$user@$host:/etc/config/openclash" >>"$LOG" 2>&1; then
      log "[$name] sync /etc/config/openclash failed"
      node_status_set "$sec" error "主配置同步失败"
      return 1
    fi
  fi

  sync_dir_to_node "$sec" sync_config_dir /etc/openclash/config /etc/openclash/config "$rsync_ssh" "$user" "$host" || true
  sync_dir_to_node "$sec" sync_custom_dir /etc/openclash/custom /etc/openclash/custom "$rsync_ssh" "$user" "$host" || true
  sync_dir_to_node "$sec" sync_overwrite_dir /etc/openclash/overwrite /etc/openclash/overwrite "$rsync_ssh" "$user" "$host" || true
  sync_dir_to_node "$sec" sync_proxy_provider_dir /etc/openclash/proxy_provider /etc/openclash/proxy_provider "$rsync_ssh" "$user" "$host" || true
  sync_dir_to_node "$sec" sync_rule_provider_dir /etc/openclash/rule_provider /etc/openclash/rule_provider "$rsync_ssh" "$user" "$host" || true
  sync_dir_to_node "$sec" sync_game_rules_dir /etc/openclash/game_rules /etc/openclash/game_rules "$rsync_ssh" "$user" "$host" || true

  if get_bool_sec "$MAIN" sync_root_assets 1; then
    find /etc/openclash -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.dat' -o -name '*.mmdb' -o -name '*.ipset' \) -print0 \
      | rsync -az --delete --files-from=- --from0 -e "$rsync_ssh" / "$user@$host:/" >>"$LOG" 2>&1 || true
  fi

  if [ "$reload" = "1" ]; then
    $ssh_base "$user@$host" "/etc/init.d/openclash reload >/tmp/openclash_sync_reload.log 2>&1 || /etc/init.d/openclash restart >/tmp/openclash_sync_reload.log 2>&1 || true" >>"$LOG" 2>&1
  fi

  log "[$name] sync done"
  node_status_set "$sec" ok "同步完成"
  return 0
}

sync_once() {
  if ! mkdir "$LOCK" 2>/dev/null; then
    touch "$PENDING"
    log "sync already running, mark pending"
    return 0
  fi

  local ok=0 fail=0 count=0
  status_set syncing "同步中"
  log "sync batch start"

  for sec in $(uci -q show "$CONFIG" | sed -n "s/^$CONFIG\.\([^=]*\)=node$/\1/p"); do
    if get_bool_sec "$sec" enabled 1; then
      count=$((count + 1))
      if sync_node "$sec"; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
    fi
  done

  if [ "$count" -eq 0 ]; then
    status_set error "没有启用的同步节点"
    log "sync batch done: no enabled nodes"
  elif [ "$fail" -eq 0 ]; then
    status_set ok "全部节点同步完成：$ok/$count"
    log "sync batch done: ok=$ok fail=$fail"
  else
    status_set error "部分节点失败：成功 $ok，失败 $fail，共 $count"
    log "sync batch done: ok=$ok fail=$fail"
  fi

  rmdir "$LOCK" 2>/dev/null || true

  if [ -f "$PENDING" ]; then
    rm -f "$PENDING"
    log "pending change detected, run one more sync"
    sleep 2
    sync_once
  fi
}

schedule_sync() {
  touch "$PENDING"
  if mkdir "$DEBOUNCE_LOCK" 2>/dev/null; then
    (
      sleep "$DEBOUNCE"
      rm -f "$PENDING"
      sync_once
      rmdir "$DEBOUNCE_LOCK" 2>/dev/null || true
    ) &
  fi
}

periodic_loop() {
  log "periodic safety sync start, interval=${PERIODIC_SYNC}s"
  while true; do
    sleep "$PERIODIC_SYNC"
    log "periodic safety sync tick"
    sync_once
  done
}

watch_loop() {
  log "watch start (one-to-many monitor + periodic safety sync)"
  status_set running "监听中"
  sync_once
  periodic_loop &
  PERIODIC_PID=$!
  trap 'kill $PERIODIC_PID 2>/dev/null; exit 0' INT TERM
  while true; do
    inotifywait -m -r -e close_write,create,delete,move,attrib \
      --exclude '(/etc/openclash/(core|history|cache|run|logs|backup)/|\.log$|\.pid$)' \
      /etc/config/openclash /etc/openclash 2>>"$LOG" | while read line; do
        log "event $line"
        schedule_sync
      done
    log "inotifywait exited, restart in 3s"
    sleep 3
  done
}

peer_status() {
  local cache_file="/tmp/openclash_sync_peer_cache"
  local cache_age=9999
  if [ -f "$cache_file" ]; then
    local now=$(date +%s)
    local mtime=$(date -r "$cache_file" +%s 2>/dev/null || echo 0)
    cache_age=$(( now - mtime ))
  fi
  if [ "$cache_age" -lt 60 ]; then
    cat "$cache_file"
    return
  fi
  local tmp="$cache_file.tmp.$$"
  _peer_status_real > "$tmp" 2>/dev/null
  mv "$tmp" "$cache_file" 2>/dev/null
  cat "$cache_file"
}

_peer_status_real() {
  for sec in $(uci -q show "$CONFIG" | sed -n "s/^$CONFIG\.\([^=]*\)=node$/\1/p"); do
    local name host port user auth password key known en ssh_base last_sync node_state node_msg remote_info rc
    name="$(get_cfg "$sec" name "$sec")"
    host="$(get_cfg "$sec" remote_host '')"
    port="$(get_cfg "$sec" remote_port 22)"
    user="$(get_cfg "$sec" remote_user root)"
    auth="$(get_cfg "$sec" auth_mode key)"
    password="$(get_cfg "$sec" password '')"
    key="$(get_cfg "$sec" ssh_key /root/.ssh/openclash_sync_openssh_ed25519)"
    known="$(get_cfg "$sec" known_hosts /root/.ssh/openclash_sync_known_hosts)"
    en="$(get_cfg "$sec" enabled 1)"
    last_sync="$(sed -n 's/^last_update=//p' "$NODE_STATUS_DIR/$sec" 2>/dev/null | tail -1)"
    node_state="$(sed -n 's/^state=//p' "$NODE_STATUS_DIR/$sec" 2>/dev/null | tail -1)"
    node_msg="$(sed -n 's/^message=//p' "$NODE_STATUS_DIR/$sec" 2>/dev/null | tail -1)"

    echo "BEGIN_NODE"
    echo "section=$sec"
    echo "name=$name"
    echo "enabled=$en"
    echo "target=$user@$host:$port"
    echo "last_sync=$last_sync"
    echo "sync_state=$node_state"
    echo "sync_message=$node_msg"

    if [ "$en" != "1" ]; then
      echo "peer_reachable=disabled"
      echo "openclash_state=节点未启用"
      echo "openclash_version=-"
      echo "END_NODE"
      continue
    fi
    if [ -z "$host" ]; then
      echo "peer_reachable=no"
      echo "openclash_state=未配置地址"
      echo "openclash_version=-"
      echo "END_NODE"
      continue
    fi

    if [ "$auth" = "password" ]; then
      ssh_base="sshpass -p $password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=$known -o ConnectTimeout=8 -p $port"
    else
      ssh_base="ssh -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=$known -o ConnectTimeout=8 -p $port"
    fi

    remote_info="$($ssh_base "$user@$host" '
      ver=$(opkg list-installed 2>/dev/null | awk '\''$1=="luci-app-openclash"{print $3; exit}'\'')
      [ -z "$ver" ] && [ -f /usr/lib/opkg/info/luci-app-openclash.control ] && ver=$(awk -F": " '\''$1=="Version"{print $2; exit}'\'' /usr/lib/opkg/info/luci-app-openclash.control)
      [ -z "$ver" ] && ver="未安装"
      if [ -x /etc/init.d/openclash ]; then
        st=$(/etc/init.d/openclash status 2>/dev/null || true)
        case "$st" in
          running) ;;
          *) pgrep -f "clash" >/dev/null 2>&1 && st=running || st=inactive ;;
        esac
      else
        st="未安装"
      fi
      en=$(/etc/init.d/openclash enabled >/dev/null 2>&1 && echo 1 || echo 0)
      echo "openclash_version=$ver"
      echo "openclash_state=$st"
      echo "openclash_enabled=$en"
    ' 2>/dev/null)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "peer_reachable=yes"
      echo "$remote_info"
    else
      echo "peer_reachable=no"
      echo "openclash_version=未知"
      echo "openclash_state=连接失败"
      echo "openclash_enabled=未知"
    fi
    echo "END_NODE"
  done
}

case "$1" in
  once) sync_once ;;
  status)
    echo "enabled=$(get_cfg "$MAIN" enabled 1)"
    echo "nodes_enabled=$(node_count_enabled)"
    echo "service_pids=$(pgrep -f '/usr/bin/openclash_sync.sh watch' | xargs 2>/dev/null)"
    echo "inotify_pids=$(pgrep -f 'inotifywait -m -r' | xargs 2>/dev/null)"
    echo "periodic_pids=$(pgrep -f '^sleep 300$' | xargs 2>/dev/null)"
    if pgrep -f 'inotifywait -m -r' >/dev/null 2>&1; then echo "watching=1"; else echo "watching=0"; fi
    [ -f "$STATUS_FILE" ] && cat "$STATUS_FILE"
    for sec in $(uci -q show "$CONFIG" | sed -n "s/^$CONFIG\.\([^=]*\)=node$/\1/p"); do
      name="$(get_cfg "$sec" name "$sec")"
      host="$(get_cfg "$sec" remote_host '')"
      port="$(get_cfg "$sec" remote_port 22)"
      en="$(get_cfg "$sec" enabled 1)"
      echo "node.$sec=$name|$host:$port|enabled=$en"
      [ -f "$NODE_STATUS_DIR/$sec" ] && sed "s/^/node.$sec./" "$NODE_STATUS_DIR/$sec"
    done
    ;;
  peer-status) peer_status ;;
  watch|"") watch_loop ;;
  *) echo "Usage: $0 [once|watch|status]"; exit 1 ;;
esac
