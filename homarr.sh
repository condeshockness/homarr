#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/homarr-labs/homarr

# This function sets various color variables using ANSI escape codes for formatting text in the terminal.
color() {
  # Colors
  YW=$(echo "\033[33m")
  YWB=$(echo "\033[93m")
  BL=$(echo "\033[36m")
  RD=$(echo "\033[01;31m")
  BGN=$(echo "\033[4;92m")
  GN=$(echo "\033[1;92m")
  DGN=$(echo "\033[32m")

  # Formatting
  CL=$(echo "\033[m")
  BOLD=$(echo "\033[1m")
  HOLD=" "
  TAB="  "
  TAB3="      "

  # Icons
  CM="${TAB}✔️${TAB}"
  CROSS="${TAB}✖️${TAB}"
  INFO="${TAB}💡${TAB}${CL}"
  OS="${TAB}🖥️${TAB}${CL}"
  OSVERSION="${TAB}🌟${TAB}${CL}"
  CONTAINERTYPE="${TAB}📦${TAB}${CL}"
  DISKSIZE="${TAB}💾${TAB}${CL}"
  CPUCORE="${TAB}🧠${TAB}${CL}"
  RAMSIZE="${TAB}🛠️${TAB}${CL}"
  SEARCH="${TAB}🔍${TAB}${CL}"
  VERBOSE_CROPPED="🔍${TAB}"
  VERIFYPW="${TAB}🔐${TAB}${CL}"
  CONTAINERID="${TAB}🆔${TAB}${CL}"
  HOSTNAME="${TAB}🏠${TAB}${CL}"
  BRIDGE="${TAB}🌉${TAB}${CL}"
  NETWORK="${TAB}📡${TAB}${CL}"
  GATEWAY="${TAB}🌐${TAB}${CL}"
  DISABLEIPV6="${TAB}🚫${TAB}${CL}"
  DEFAULT="${TAB}⚙️${TAB}${CL}"
  MACADDRESS="${TAB}🔗${TAB}${CL}"
  VLANTAG="${TAB}🏷️${TAB}${CL}"
  ROOTSSH="${TAB}🔑${TAB}${CL}"
  CREATING="${TAB}🚀${TAB}${CL}"
  ADVANCED="${TAB}🧩${TAB}${CL}"
  FUSE="${TAB}🗂️${TAB}${CL}"
}

# This function enables error handling in the script by setting options and defining a trap for the ERR signal.
catch_errors() {
  set -Eeuo pipefail
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

# This function is called when an error occurs. It receives the exit code, line number, and command that caused the error, and displays an error message.
error_handler() {
  source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)
  if [ -n "$SPINNER_PID" ] && ps -p "$SPINNER_PID" >/dev/null; then kill "$SPINNER_PID" >/dev/null; fi
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  post_update_to_api "failed" "${command}"
  echo -e "\n$error_message\n"
}

# This function displays an informational message with logging support.
declare -A MSG_INFO_SHOWN
SPINNER_ACTIVE=0
SPINNER_PID=""
SPINNER_MSG=""

trap 'stop_spinner' EXIT INT TERM HUP

start_spinner() {
  local msg="$1"
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local spin_i=0
  local interval=0.1

  SPINNER_MSG="$msg"
  printf "\r\e[2K" >&2

  {
    while [[ "$SPINNER_ACTIVE" -eq 1 ]]; do
      printf "\r\e[2K%s %b" "${frames[spin_i]}" "${YW}${SPINNER_MSG}${CL}" >&2
      spin_i=$(((spin_i + 1) % ${#frames[@]}))
      sleep "$interval"
    done
  } &

  SPINNER_PID=$!
  disown "$SPINNER_PID"
}

stop_spinner() {
  if [[ ${SPINNER_PID+v} && -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null
    sleep 0.1
    kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  SPINNER_ACTIVE=0
  unset SPINNER_PID
}

spinner_guard() {
  if [[ "$SPINNER_ACTIVE" -eq 1 ]] && [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_ACTIVE=0
    unset SPINNER_PID
  fi
}

msg_info() {
  local msg="$1"
  [[ -n "${MSG_INFO_SHOWN["$msg"]+x}" ]] && return
  MSG_INFO_SHOWN["$msg"]=1

  spinner_guard
  SPINNER_ACTIVE=1
  start_spinner "$msg"
}

msg_ok() {
  local msg="$1"
  stop_spinner
  printf "\r\e[2K%s %b\n" "${CM}" "${GN}${msg}${CL}" >&2
  unset MSG_INFO_SHOWN["$msg"]
}

msg_error() {
  stop_spinner
  local msg="$1"
  printf "\r\e[2K%s %b\n" "${CROSS}" "${RD}${msg}${CL}" >&2
}

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

msg_info "Installing Dependencies"
$STD apt-get install -y \
  redis-server \
  ca-certificates \
  make \
  g++ \
  build-essential \
  nginx \
  gettext \
  jq \
  openssl
msg_ok "Installed Dependencies"

NODE_VERSION=$(curl -s https://raw.githubusercontent.com/homarr-labs/homarr/dev/package.json | jq -r '.engines.node | split(">=")[1] | split(".")[0]')
NODE_MODULE="pnpm@$(curl -s https://raw.githubusercontent.com/homarr-labs/homarr/dev/package.json | jq -r '.packageManager | split("@")[1]')"
install_node_and_modules
fetch_and_deploy_gh_release "homarr-labs/homarr"

msg_info "Installing Homarr (Patience)"
cd /opt
mkdir -p /opt/homarr_db
touch /opt/homarr_db/db.sqlite
SECRET_ENCRYPTION_KEY="$(openssl rand -hex 32)"
cd /opt/homarr
cat <<EOF >/opt/homarr/.env
DB_DRIVER='better-sqlite3'
DB_DIALECT='sqlite'
SECRET_ENCRYPTION_KEY='${SECRET_ENCRYPTION_KEY}'
DB_URL='/opt/homarr_db/db.sqlite'
TURBO_TELEMETRY_DISABLED=1
AUTH_PROVIDERS='credentials'
NODE_ENV='production'
EOF
$STD pnpm install --recursive --frozen-lockfile --shamefully-hoist
$STD pnpm build
msg_ok "Installed Homarr"

msg_info "Copying build and config files"
cp /opt/homarr/apps/nextjs/next.config.ts .
cp /opt/homarr/apps/nextjs/package.json .
cp -r /opt/homarr/packages/db/migrations /opt/homarr_db/migrations
cp -r /opt/homarr/apps/nextjs/.next/standalone/* /opt/homarr
mkdir -p /appdata/redis
cp /opt/homarr/packages/redis/redis.conf /opt/homarr/redis.conf
mkdir -p /etc/nginx/templates
rm /etc/nginx/nginx.conf
cp /opt/homarr/nginx.conf /etc/nginx/templates/nginx.conf
mkdir -p /opt/homarr/apps/cli
cp /opt/homarr/packages/cli/cli.cjs /opt/homarr/apps/cli/cli.cjs
echo $'#!/bin/bash\ncd /opt/homarr/apps/cli && node ./cli.cjs "$@"' >/usr/bin/homarr
chmod +x /usr/bin/homarr
mkdir /opt/homarr/build
cp ./node_modules/better-sqlite3/build/Release/better_sqlite3.node ./build/better_sqlite3.node
msg_ok "Finished copying"

msg_info "Creating Services"
cat <<'EOF' >/opt/run_homarr.sh
#!/bin/bash
set -a
source /opt/homarr/.env
set +a
export DB_DIALECT='sqlite'
export AUTH_SECRET=$(openssl rand -base64 32)
node /opt/homarr_db/migrations/$DB_DIALECT/migrate.cjs /opt/homarr_db/migrations/$DB_DIALECT
for dir in $(find /opt/homarr_db/migrations/migrations -mindepth 1 -maxdepth 1 -type d); do
  dirname=$(basename "$dir")
  mkdir -p "/opt/homarr_db/migrations/$dirname"
  cp -r "$dir"/* "/opt/homarr_db/migrations/$dirname/" 2>/dev/null || true
done
export HOSTNAME=$(ip route get 1.1.1.1 | grep -oP 'src \K[^ ]+')
envsubst '${HOSTNAME}' < /etc/nginx/templates/nginx.conf > /etc/nginx/nginx.conf
nginx -g 'daemon off;' &
redis-server /opt/homarr/packages/redis/redis.conf &
node apps/tasks/tasks.cjs &
node apps/websocket/wssServer.cjs &
node apps/nextjs/server.js & PID=$!
wait $PID
EOF
chmod +x /opt/run_homarr.sh
cat <<EOF >/etc/systemd/system/homarr.service
[Unit]
Description=Homarr Service
After=network.target

[Service]
Type=exec
WorkingDirectory=/opt/homarr
EnvironmentFile=-/opt/homarr/.env
ExecStart=/opt/run_homarr.sh

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now homarr
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"