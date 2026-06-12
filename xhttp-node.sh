#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="xhttp-node"
INSTALL_DIR="/usr/local/xhttp-node"
CONFIG_DIR="/etc/xhttp-node"
CONFIG_FILE="${CONFIG_DIR}/config.env"
BACKUP_DIR="/root/xhttp-node-backups"

DOMAIN=""
PANEL_DOMAIN=""
XHTTP_PATH="/api/v1/sync"
XHTTP_PORT="10000"
PANEL_PORT="2070"
WEB_ROOT=""
CERT_FILE=""
KEY_FILE=""

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
blue() { printf '\033[34m%s\033[0m\n' "$*"; }

pause() {
  echo
  read -r -p "按回车继续..."
}

need_root() {
  [ "$(id -u)" = "0" ] || {
    red "请使用 root 运行。"
    exit 1
  }
}

ensure_dirs() {
  mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  fi
  [ -n "${PANEL_DOMAIN:-}" ] || {
    if [ -n "${DOMAIN:-}" ]; then PANEL_DOMAIN="panel.${DOMAIN}"; fi
  }
  [ -n "${WEB_ROOT:-}" ] || {
    if [ -n "${DOMAIN:-}" ]; then WEB_ROOT="/var/www/${DOMAIN}"; fi
  }
  [ -n "${CERT_FILE:-}" ] || {
    if [ -n "${DOMAIN:-}" ]; then CERT_FILE="/root/cert/${DOMAIN}/fullchain.pem"; fi
  }
  [ -n "${KEY_FILE:-}" ] || {
    if [ -n "${DOMAIN:-}" ]; then KEY_FILE="/root/cert/${DOMAIN}/privkey.pem"; fi
  }
}

save_config() {
  ensure_dirs
  local q_domain q_panel_domain q_xhttp_path q_xhttp_port q_panel_port q_web_root q_cert_file q_key_file
  q_domain="$(printf "%s" "$DOMAIN" | sed "s/'/'\\\\''/g")"
  q_panel_domain="$(printf "%s" "$PANEL_DOMAIN" | sed "s/'/'\\\\''/g")"
  q_xhttp_path="$(printf "%s" "$XHTTP_PATH" | sed "s/'/'\\\\''/g")"
  q_xhttp_port="$(printf "%s" "$XHTTP_PORT" | sed "s/'/'\\\\''/g")"
  q_panel_port="$(printf "%s" "$PANEL_PORT" | sed "s/'/'\\\\''/g")"
  q_web_root="$(printf "%s" "$WEB_ROOT" | sed "s/'/'\\\\''/g")"
  q_cert_file="$(printf "%s" "$CERT_FILE" | sed "s/'/'\\\\''/g")"
  q_key_file="$(printf "%s" "$KEY_FILE" | sed "s/'/'\\\\''/g")"
  cat > "$CONFIG_FILE" <<EOF
DOMAIN='${q_domain}'
PANEL_DOMAIN='${q_panel_domain}'
XHTTP_PATH='${q_xhttp_path}'
XHTTP_PORT='${q_xhttp_port}'
PANEL_PORT='${q_panel_port}'
WEB_ROOT='${q_web_root}'
CERT_FILE='${q_cert_file}'
KEY_FILE='${q_key_file}'
EOF
  chmod 600 "$CONFIG_FILE"
}

prompt_default() {
  local var_name="$1"
  local label="$2"
  local default_value="$3"
  local value
  read -r -p "${label} [默认: ${default_value}]: " value
  if [ -z "$value" ]; then value="$default_value"; fi
  printf -v "$var_name" '%s' "$value"
}

prompt_common() {
  load_config
  local default_domain="${DOMAIN:-57330.xyz}"
  prompt_default DOMAIN "请输入主域名" "$default_domain"
  prompt_default PANEL_DOMAIN "请输入面板域名" "${PANEL_DOMAIN:-panel.${DOMAIN}}"
  prompt_default XHTTP_PATH "请输入 xhttp 路径" "${XHTTP_PATH:-/api/v1/sync}"
  prompt_default XHTTP_PORT "请输入 xhttp 本机端口" "${XHTTP_PORT:-10000}"
  prompt_default PANEL_PORT "请输入面板本机端口" "${PANEL_PORT:-2070}"
  prompt_default WEB_ROOT "请输入静态网站目录" "${WEB_ROOT:-/var/www/${DOMAIN}}"
  prompt_default CERT_FILE "请输入证书路径" "${CERT_FILE:-/root/cert/${DOMAIN}/fullchain.pem}"
  prompt_default KEY_FILE "请输入私钥路径" "${KEY_FILE:-/root/cert/${DOMAIN}/privkey.pem}"
  validate_common
  save_config
}

validate_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  [ "$value" -ge 1 ] && [ "$value" -le 65535 ]
}

validate_common() {
  [ -n "$DOMAIN" ] || { red "主域名不能为空。"; return 1; }
  [ -n "$PANEL_DOMAIN" ] || { red "面板域名不能为空。"; return 1; }
  [[ "$XHTTP_PATH" == /* ]] || { red "xhttp 路径必须以 / 开头。"; return 1; }
  validate_port "$XHTTP_PORT" || { red "xhttp 端口无效。"; return 1; }
  validate_port "$PANEL_PORT" || { red "面板端口无效。"; return 1; }
}

backup_path() {
  local path="$1"
  local stamp
  stamp="$(date +%Y%m%d%H%M%S)"
  if [ -e "$path" ]; then
    mkdir -p "$BACKUP_DIR/files"
    cp -a "$path" "$BACKUP_DIR/files/$(echo "$path" | tr '/' '_').${stamp}"
  fi
}

backup_now() {
  ensure_dirs
  local stamp dest
  stamp="$(date +%Y%m%d%H%M%S)"
  dest="${BACKUP_DIR}/${stamp}"
  mkdir -p "$dest"
  [ -d /etc/nginx ] && cp -a /etc/nginx "$dest/nginx"
  [ -d /root/cert ] && cp -a /root/cert "$dest/cert"
  [ -f "$CONFIG_FILE" ] && cp -a "$CONFIG_FILE" "$dest/config.env"
  green "备份完成：${dest}"
}

restore_latest_backup() {
  local latest
  latest="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1 || true)"
  [ -n "$latest" ] || { yellow "没有找到备份。"; return 0; }
  yellow "将恢复最新备份：$latest"
  read -r -p "确认恢复？[y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] || return 0
  if [ -d "$latest/nginx" ]; then
    rm -rf /etc/nginx
    cp -a "$latest/nginx" /etc/nginx
  fi
  if [ -d "$latest/cert" ]; then
    rm -rf /root/cert
    cp -a "$latest/cert" /root/cert
  fi
  if [ -f "$latest/config.env" ]; then
    mkdir -p "$CONFIG_DIR"
    cp -a "$latest/config.env" "$CONFIG_FILE"
  fi
  nginx -t && systemctl reload nginx || true
  green "恢复完成。"
}

install_base() {
  blue "安装基础环境"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y nginx curl ca-certificates openssl socat
  systemctl enable nginx >/dev/null 2>&1 || true
  green "基础环境安装完成。"
}

install_or_check_3xui() {
  blue "安装/检查 3x-ui"
  if command -v x-ui >/dev/null 2>&1 || [ -x /usr/local/x-ui/x-ui ]; then
    green "检测到 3x-ui 已安装。"
    systemctl status x-ui --no-pager -l | sed -n '1,14p' || true
    return 0
  fi
  yellow "未检测到 3x-ui。"
  read -r -p "是否使用官方脚本安装 3x-ui？[y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] || return 0
  bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
}

install_cert_files() {
  local src_cert="$1"
  local src_key="$2"
  local main_dir panel_dir
  local dest_cert dest_key
  main_dir="/root/cert/${DOMAIN}"
  panel_dir="/root/cert/${PANEL_DOMAIN}"
  dest_cert="$main_dir/fullchain.pem"
  dest_key="$main_dir/privkey.pem"
  [ -f "$src_cert" ] || { red "证书文件不存在：$src_cert"; return 1; }
  [ -f "$src_key" ] || { red "私钥文件不存在：$src_key"; return 1; }
  mkdir -p "$main_dir" "$panel_dir"
  backup_path "$dest_cert"
  backup_path "$dest_key"
  backup_path "$panel_dir/fullchain.pem"
  backup_path "$panel_dir/privkey.pem"
  if [ "$(readlink -f "$src_cert")" != "$(readlink -f "$dest_cert" 2>/dev/null || true)" ]; then
    cp -a "$src_cert" "$dest_cert"
  fi
  if [ "$(readlink -f "$src_key")" != "$(readlink -f "$dest_key" 2>/dev/null || true)" ]; then
    cp -a "$src_key" "$dest_key"
  fi
  cp -a "$dest_cert" "$panel_dir/fullchain.pem"
  cp -a "$dest_key" "$panel_dir/privkey.pem"
  chmod 644 "$dest_cert" "$panel_dir/fullchain.pem"
  chmod 600 "$dest_key" "$panel_dir/privkey.pem"
  CERT_FILE="$dest_cert"
  KEY_FILE="$dest_key"
  save_config
  verify_cert_pair "$CERT_FILE" "$KEY_FILE" || return 1
  green "证书安装完成。"
  echo
  echo "主域证书："
  echo "$main_dir/fullchain.pem"
  echo "$main_dir/privkey.pem"
  echo
  echo "面板证书路径（3x-ui 面板可直接填写）："
  echo "$panel_dir/fullchain.pem"
  echo "$panel_dir/privkey.pem"
}

verify_cert_pair() {
  local cert="$1"
  local key="$2"
  openssl x509 -in "$cert" -noout -subject -issuer -dates -ext subjectAltName || return 1
  local cert_pub key_pub
  cert_pub="$(openssl x509 -in "$cert" -pubkey -noout | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  key_pub="$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  if [ "$cert_pub" != "$key_pub" ]; then
    red "证书和私钥不匹配。"
    return 1
  fi
  if ! openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null | grep -Eq "DNS:\*\.${DOMAIN}|DNS:${DOMAIN}"; then
    yellow "警告：没有在 SAN 中确认 ${DOMAIN} 或 *.${DOMAIN}，请自行确认。"
  fi
}

cf_issue_origin_cert() {
  blue "使用 Cloudflare API 自动签发 Origin 证书"
  prompt_default DOMAIN "请输入主域名" "${DOMAIN:-57330.xyz}"
  prompt_default PANEL_DOMAIN "请输入面板域名" "${PANEL_DOMAIN:-panel.${DOMAIN}}"
  WEB_ROOT="${WEB_ROOT:-/var/www/${DOMAIN}}"
  XHTTP_PATH="${XHTTP_PATH:-/api/v1/sync}"
  XHTTP_PORT="${XHTTP_PORT:-10000}"
  PANEL_PORT="${PANEL_PORT:-2070}"
  save_config

  echo
  echo "认证方式："
  echo "1. Cloudflare API Token (Bearer)"
  echo "2. Cloudflare Origin CA Key"
  echo "3. Cloudflare Global API Key + Email"
  read -r -p "请选择 [默认: 1]: " auth_mode
  auth_mode="${auth_mode:-1}"
  read -r -s -p "请输入 Cloudflare 密钥/Token: " cf_secret
  echo
  cf_email=""
  if [ "$auth_mode" = "3" ]; then
    read -r -p "请输入 Cloudflare 账号邮箱: " cf_email
  fi

  local work_dir key_path csr_path cert_path
  work_dir="/root/cert/${DOMAIN}"
  key_path="${work_dir}/privkey.pem"
  csr_path="${work_dir}/origin.csr"
  cert_path="${work_dir}/fullchain.pem.new"
  mkdir -p "$work_dir"
  chmod 700 "$work_dir"

  backup_path "$work_dir/privkey.pem"
  openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$key_path" \
    -out "$csr_path" \
    -subj "/CN=${DOMAIN}" \
    -addext "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN}" >/dev/null 2>&1
  chmod 600 "$key_path"

  CF_AUTH_MODE="$auth_mode" CF_SECRET="$cf_secret" CF_EMAIL="$cf_email" DOMAIN="$DOMAIN" CSR_PATH="$csr_path" CERT_PATH="$cert_path" python3 <<'PY'
import json, os, sys, urllib.request, urllib.error

mode = os.environ["CF_AUTH_MODE"]
secret = os.environ["CF_SECRET"]
email = os.environ.get("CF_EMAIL", "")
domain = os.environ["DOMAIN"]
csr_path = os.environ["CSR_PATH"]
cert_path = os.environ["CERT_PATH"]

with open(csr_path, encoding="utf-8") as f:
    csr = f.read()

payload = {
    "hostnames": [domain, f"*.{domain}"],
    "requested_validity": 5475,
    "request_type": "origin-rsa",
    "csr": csr,
}
headers = {"Content-Type": "application/json", "Accept": "application/json"}
if mode == "1":
    headers["Authorization"] = f"Bearer {secret}"
elif mode == "2":
    headers["X-Auth-User-Service-Key"] = secret
elif mode == "3":
    headers["X-Auth-Email"] = email
    headers["X-Auth-Key"] = secret
else:
    raise SystemExit("Invalid auth mode")

req = urllib.request.Request(
    "https://api.cloudflare.com/client/v4/certificates",
    data=json.dumps(payload).encode("utf-8"),
    headers=headers,
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=45) as resp:
        body = resp.read().decode("utf-8", "replace")
except urllib.error.HTTPError as e:
    body = e.read().decode("utf-8", "replace")
    print(body.replace(secret, "[redacted]"))
    raise SystemExit(1)

data = json.loads(body)
if not data.get("success"):
    print(json.dumps(data.get("errors"), ensure_ascii=False))
    raise SystemExit(1)

cert = data["result"]["certificate"]
with open(cert_path, "w", encoding="utf-8") as f:
    f.write(cert)
print("Cloudflare Origin cert id:", data["result"].get("id", ""))
print("Expires on:", data["result"].get("expires_on", ""))
PY

  install_cert_files "$cert_path" "$key_path"

  read -r -p "是否尝试自动配置 Cloudflare DNS A 记录？[y/N]: " dns_ok
  if [[ "$dns_ok" =~ ^[Yy]$ ]]; then
    cf_configure_dns "$auth_mode" "$cf_secret" "$cf_email"
  fi
}

cf_configure_dns() {
  local auth_mode="$1"
  local cf_secret="$2"
  local cf_email="$3"
  local vps_ip
  prompt_default vps_ip "请输入 VPS 公网 IP" "$(curl -sS --max-time 8 https://api.ipify.org || hostname -I | awk '{print $1}')"
  CF_AUTH_MODE="$auth_mode" CF_SECRET="$cf_secret" CF_EMAIL="$cf_email" DOMAIN="$DOMAIN" PANEL_DOMAIN="$PANEL_DOMAIN" VPS_IP="$vps_ip" python3 <<'PY'
import json, os, sys, urllib.parse, urllib.request, urllib.error

mode = os.environ["CF_AUTH_MODE"]
secret = os.environ["CF_SECRET"]
email = os.environ.get("CF_EMAIL", "")
domain = os.environ["DOMAIN"]
panel_domain = os.environ["PANEL_DOMAIN"]
vps_ip = os.environ["VPS_IP"]
base = "https://api.cloudflare.com/client/v4"

headers = {"Content-Type": "application/json", "Accept": "application/json"}
if mode == "1":
    headers["Authorization"] = f"Bearer {secret}"
elif mode == "3":
    headers["X-Auth-Email"] = email
    headers["X-Auth-Key"] = secret
else:
    print("当前认证方式通常不能管理 DNS，跳过。")
    raise SystemExit(0)

def request(method, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        print(body.replace(secret, "[redacted]"))
        raise

zones = request("GET", f"/zones?name={urllib.parse.quote(domain)}")
if not zones.get("success") or not zones.get("result"):
    print("没有找到 zone，跳过 DNS 配置。")
    raise SystemExit(0)
zone_id = zones["result"][0]["id"]

for name in (domain, panel_domain):
    existing = request("GET", f"/zones/{zone_id}/dns_records?type=A&name={urllib.parse.quote(name)}").get("result", [])
    payload = {"type": "A", "name": name, "content": vps_ip, "ttl": 1, "proxied": True}
    if existing:
        res = request("PUT", f"/zones/{zone_id}/dns_records/{existing[0]['id']}", payload)
        action = "updated"
    else:
        res = request("POST", f"/zones/{zone_id}/dns_records", payload)
        action = "created"
    print(action, name, "proxied=", res.get("result", {}).get("proxied"))
PY
}

cf_existing_cert() {
  blue "使用已有 Cloudflare Origin 证书文件"
  prompt_default DOMAIN "请输入主域名" "${DOMAIN:-57330.xyz}"
  prompt_default PANEL_DOMAIN "请输入面板域名" "${PANEL_DOMAIN:-panel.${DOMAIN}}"
  local src_cert src_key
  prompt_default src_cert "请输入已有证书文件路径" "/root/cf-origin.pem"
  prompt_default src_key "请输入已有私钥文件路径" "/root/cf-origin.key"
  WEB_ROOT="${WEB_ROOT:-/var/www/${DOMAIN}}"
  XHTTP_PATH="${XHTTP_PATH:-/api/v1/sync}"
  XHTTP_PORT="${XHTTP_PORT:-10000}"
  PANEL_PORT="${PANEL_PORT:-2070}"
  save_config
  install_cert_files "$src_cert" "$src_key"
}

cloudflare_menu() {
  while true; do
    clear
    echo "Cloudflare 域名和源站证书配置"
    echo
    echo "1. 使用 Cloudflare API 自动签发 Origin 证书"
    echo "2. 我已经有 Cloudflare Origin 证书文件"
    echo "0. 返回主菜单"
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) cf_issue_origin_cert; pause ;;
      2) cf_existing_cert; pause ;;
      0) return ;;
      *) yellow "无效选择"; pause ;;
    esac
  done
}

disable_default_nginx_site() {
  mkdir -p /etc/nginx/disabled-sites
  local stamp
  stamp="$(date +%Y%m%d%H%M%S)"
  if [ -e /etc/nginx/sites-enabled/default ]; then
    mv /etc/nginx/sites-enabled/default "/etc/nginx/disabled-sites/default.${stamp}"
  fi
  if [ -e /etc/nginx/conf.d/default.conf ]; then
    mv /etc/nginx/conf.d/default.conf "/etc/nginx/disabled-sites/default.conf.${stamp}"
  fi
}

nginx_test_reload_with_rollback() {
  local backup="${1:-}"
  local owns_backup="0"
  if [ -z "$backup" ]; then
    backup="$(mktemp -d /tmp/xhttp-node-nginx.XXXXXX)"
    cp -a /etc/nginx "$backup/nginx"
    owns_backup="1"
  fi
  if nginx -t; then
    systemctl reload nginx || systemctl restart nginx
    green "Nginx 配置已生效。"
    [ "$owns_backup" = "1" ] && rm -rf "$backup"
  else
    red "Nginx 配置测试失败，自动回滚。"
    rm -rf /etc/nginx
    cp -a "$backup/nginx" /etc/nginx
    nginx -t && systemctl reload nginx || true
    [ "$owns_backup" = "1" ] && rm -rf "$backup"
    return 1
  fi
}

write_nginx_domain_conf() {
  mkdir -p /etc/nginx/conf.d
  cat > /etc/nginx/conf.d/00-server-names-hash.conf <<'EOF'
server_names_hash_bucket_size 64;
EOF

  cat > "/etc/nginx/conf.d/${DOMAIN}.conf" <<EOF
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};

    root ${WEB_ROOT};
    index index.html;

    error_page 404 /404.html;

    location ${XHTTP_PATH} {
        proxy_pass http://127.0.0.1:${XHTTP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host ${DOMAIN};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location = /404.html {
        root ${WEB_ROOT};
        internal;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

write_nginx_panel_conf() {
  mkdir -p /etc/nginx/conf.d
  cat > "/etc/nginx/conf.d/${PANEL_DOMAIN}.conf" <<EOF
server {
    listen 443 ssl http2;
    server_name ${PANEL_DOMAIN};

    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};

    location / {
        proxy_pass https://127.0.0.1:${PANEL_PORT};
        proxy_http_version 1.1;
        proxy_ssl_verify off;
        proxy_set_header Host 127.0.0.1:${PANEL_PORT};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF
}

nginx_standard() {
  blue "配置标准 Nginx 443 分流"
  prompt_common
  [ -f "$CERT_FILE" ] || { red "证书不存在：$CERT_FILE"; return 1; }
  [ -f "$KEY_FILE" ] || { red "私钥不存在：$KEY_FILE"; return 1; }
  local nginx_snapshot
  nginx_snapshot="$(mktemp -d /tmp/xhttp-node-nginx-before.XXXXXX)"
  cp -a /etc/nginx "$nginx_snapshot/nginx"
  backup_now
  disable_default_nginx_site
  mkdir -p "$WEB_ROOT"
  if [ ! -f "$WEB_ROOT/index.html" ]; then
    echo "<!doctype html><meta charset=\"utf-8\"><title>${DOMAIN}</title><h1>${DOMAIN}</h1><p>OK</p>" > "$WEB_ROOT/index.html"
  fi
  chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || true
  write_nginx_domain_conf
  write_nginx_panel_conf
  if ! nginx_test_reload_with_rollback "$nginx_snapshot"; then
    rm -rf "$nginx_snapshot"
    return 1
  fi
  rm -rf "$nginx_snapshot"
  echo
  green "当前分流："
  echo "https://${DOMAIN}/            -> ${WEB_ROOT}"
  echo "https://${DOMAIN}${XHTTP_PATH} -> 127.0.0.1:${XHTTP_PORT}"
  echo "https://${PANEL_DOMAIN}/xui/  -> 127.0.0.1:${PANEL_PORT}"
  echo
  echo "下一步建议：8. 检查端口和服务状态；9. 测试网站 / 面板 / xhttp 路径"
}

nginx_xhttp_only() {
  blue "只配置 xhttp 分流"
  prompt_common
  local nginx_snapshot
  nginx_snapshot="$(mktemp -d /tmp/xhttp-node-nginx-before.XXXXXX)"
  cp -a /etc/nginx "$nginx_snapshot/nginx"
  backup_now
  disable_default_nginx_site
  mkdir -p "$WEB_ROOT"
  write_nginx_domain_conf
  if ! nginx_test_reload_with_rollback "$nginx_snapshot"; then
    rm -rf "$nginx_snapshot"
    return 1
  fi
  rm -rf "$nginx_snapshot"
}

nginx_panel_only() {
  blue "只配置面板反代"
  prompt_common
  local nginx_snapshot
  nginx_snapshot="$(mktemp -d /tmp/xhttp-node-nginx-before.XXXXXX)"
  cp -a /etc/nginx "$nginx_snapshot/nginx"
  backup_now
  write_nginx_panel_conf
  if ! nginx_test_reload_with_rollback "$nginx_snapshot"; then
    rm -rf "$nginx_snapshot"
    return 1
  fi
  rm -rf "$nginx_snapshot"
}

view_nginx_config() {
  load_config
  echo "配置文件："
  ls -l "/etc/nginx/conf.d/${DOMAIN}.conf" "/etc/nginx/conf.d/${PANEL_DOMAIN}.conf" 2>/dev/null || true
  echo
  nginx -T 2>/dev/null | sed -n "/server_name ${DOMAIN}/,/^}/p;/server_name ${PANEL_DOMAIN}/,/^}/p" || true
}

disable_panel_proxy() {
  load_config
  local path="/etc/nginx/conf.d/${PANEL_DOMAIN}.conf"
  [ -f "$path" ] || { yellow "未找到面板反代配置：$path"; return 0; }
  local nginx_snapshot
  nginx_snapshot="$(mktemp -d /tmp/xhttp-node-nginx-before.XXXXXX)"
  cp -a /etc/nginx "$nginx_snapshot/nginx"
  backup_now
  mv "$path" "${path}.disabled.$(date +%Y%m%d%H%M%S)"
  if ! nginx_test_reload_with_rollback "$nginx_snapshot"; then
    rm -rf "$nginx_snapshot"
    return 1
  fi
  rm -rf "$nginx_snapshot"
}

nginx_menu() {
  while true; do
    clear
    echo "Nginx 443 分流配置"
    echo
    echo "1. 配置标准结构（推荐）"
    echo "2. 只配置 xhttp 分流"
    echo "3. 只配置面板反代"
    echo "4. 查看当前 Nginx 分流配置"
    echo "5. 测试 Nginx 配置并重载"
    echo "6. 禁用面板 443 反代"
    echo "7. 恢复上一次配置备份"
    echo "0. 返回主菜单"
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) nginx_standard; pause ;;
      2) nginx_xhttp_only; pause ;;
      3) nginx_panel_only; pause ;;
      4) view_nginx_config; pause ;;
      5) nginx_test_reload_with_rollback; pause ;;
      6) disable_panel_proxy; pause ;;
      7) restore_latest_backup; pause ;;
      0) return ;;
      *) yellow "无效选择"; pause ;;
    esac
  done
}

static_menu() {
  load_config
  while true; do
    clear
    echo "静态网站配置"
    echo
    echo "1. 创建默认静态网站"
    echo "2. 导入已有静态网站目录"
    echo "3. 替换静态网站中的旧域名"
    echo "4. 查看当前静态网站目录"
    echo "0. 返回主菜单"
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1)
        prompt_default WEB_ROOT "请输入静态网站目录" "${WEB_ROOT:-/var/www/${DOMAIN:-site}}"
        mkdir -p "$WEB_ROOT"
        cat > "$WEB_ROOT/index.html" <<EOF
<!doctype html>
<html><head><meta charset="utf-8"><title>${DOMAIN:-site}</title></head>
<body><h1>${DOMAIN:-site}</h1><p>OK</p></body></html>
EOF
        chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || true
        save_config
        green "默认静态网站已创建：$WEB_ROOT"
        pause
        ;;
      2)
        local src
        prompt_default WEB_ROOT "请输入目标静态网站目录" "${WEB_ROOT:-/var/www/${DOMAIN:-site}}"
        read -r -p "请输入已有静态网站目录路径: " src
        [ -d "$src" ] || { red "目录不存在：$src"; pause; continue; }
        backup_path "$WEB_ROOT"
        mkdir -p "$WEB_ROOT"
        cp -a "$src"/. "$WEB_ROOT"/
        chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || true
        save_config
        green "导入完成：$WEB_ROOT"
        pause
        ;;
      3)
        local old new
        prompt_default WEB_ROOT "请输入静态网站目录" "${WEB_ROOT:-/var/www/${DOMAIN:-site}}"
        read -r -p "请输入旧域名: " old
        prompt_default new "请输入新域名" "${DOMAIN:-}"
        [ -n "$old" ] && [ -n "$new" ] || { red "域名不能为空。"; pause; continue; }
        OLD_DOMAIN="$old" NEW_DOMAIN="$new" WEB_ROOT="$WEB_ROOT" python3 <<'PY'
import os
root = os.environ["WEB_ROOT"]
old = os.environ["OLD_DOMAIN"]
new = os.environ["NEW_DOMAIN"]
for dirpath, _, filenames in os.walk(root):
    for name in filenames:
        path = os.path.join(dirpath, name)
        try:
            with open(path, "rb") as f:
                data = f.read()
            text = data.decode("utf-8")
        except Exception:
            continue
        if old in text:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text.replace(old, new))
PY
        green "替换完成。"
        pause
        ;;
      4)
        echo "当前目录：${WEB_ROOT:-未设置}"
        [ -n "${WEB_ROOT:-}" ] && find "$WEB_ROOT" -maxdepth 2 -type f 2>/dev/null | sort | sed -n '1,80p'
        pause
        ;;
      0) return ;;
      *) yellow "无效选择"; pause ;;
    esac
  done
}

check_panel_listen() {
  load_config
  blue "检查 3x-ui 面板监听"
  systemctl is-active x-ui || true
  ss -lntp | grep -E ":${PANEL_PORT}\\b" || true
  echo
  echo "本机访问面板："
  curl -k -sS -D - --max-time 8 "https://127.0.0.1:${PANEL_PORT}/xui/" -o /tmp/xhttp-node-panel-check 2>&1 | sed -n '1,14p' || true
  echo
  yellow "如果这里不通，请在 3x-ui 面板中设置：监听 127.0.0.1，端口 ${PANEL_PORT}，路径 /xui/"
}

print_xhttp_params() {
  load_config
  cat <<EOF
3x-ui xhttp 入站推荐填写：

协议：VLESS
监听 IP：127.0.0.1
端口：${XHTTP_PORT}
传输：xhttp
TLS / Security：none
Host：${DOMAIN}
Path：${XHTTP_PATH}

客户端参数：
地址：Cloudflare 优选 IP 或 ${DOMAIN}
端口：443
SNI：${DOMAIN}
Host：${DOMAIN}
Path：${XHTTP_PATH}
传输：xhttp
TLS：开启
EOF
}

check_services_ports() {
  load_config
  blue "检查端口和服务状态"
  echo "服务："
  systemctl is-active nginx x-ui 2>/dev/null || true
  echo
  echo "端口："
  ss -lntp | grep -E ":(443|${XHTTP_PORT}|${PANEL_PORT})\\b" || true
  echo
  echo "期望："
  echo "0.0.0.0:443          nginx"
  echo "127.0.0.1:${XHTTP_PORT}   xray xhttp 入站"
  echo "127.0.0.1:${PANEL_PORT}    x-ui 面板后端"
}

test_endpoints() {
  load_config
  blue "测试网站 / 面板 / xhttp 路径"
  echo "本机经 Nginx 测试静态网站："
  curl -k -I --max-time 10 --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/" || true
  echo
  echo "本机经 Nginx 测试 xhttp 路径（普通 curl 返回 404/空响应可能正常）："
  curl -k -i --max-time 10 --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}${XHTTP_PATH}" | sed -n '1,16p' || true
  echo
  echo "本机经 Nginx 测试面板："
  curl -k -I --max-time 10 --resolve "${PANEL_DOMAIN}:443:127.0.0.1" "https://${PANEL_DOMAIN}/xui/" || true
  echo
  read -r -p "是否也测试公网域名？[y/N]: " ok
  if [[ "$ok" =~ ^[Yy]$ ]]; then
    curl -I --max-time 20 "https://${DOMAIN}/" || true
    curl -I --max-time 20 "https://${PANEL_DOMAIN}/xui/" || true
  fi
}

install_shortcut() {
  blue "安装/修复快捷命令"
  mkdir -p "$INSTALL_DIR"
  local source_path
  source_path="$(readlink -f "$0")"
  if [ "$source_path" != "${INSTALL_DIR}/${APP_NAME}.sh" ]; then
    cp -a "$source_path" "${INSTALL_DIR}/${APP_NAME}.sh"
  fi
  chmod +x "${INSTALL_DIR}/${APP_NAME}.sh"
  ln -sf "${INSTALL_DIR}/${APP_NAME}.sh" "/usr/local/bin/${APP_NAME}"
  green "快捷命令已安装：${APP_NAME}"
  echo "以后可以直接运行：${APP_NAME}"
}

consistency_check() {
  load_config
  blue "检查 Nginx 与 3x-ui 当前状态是否匹配"
  local ok=1
  if ss -lntp | grep -q "127.0.0.1:${XHTTP_PORT}\\b"; then
    green "OK：xhttp 后端端口 127.0.0.1:${XHTTP_PORT} 正在监听"
  else
    red "警告：Nginx 指向 127.0.0.1:${XHTTP_PORT}，但没有看到该本机端口监听"
    ok=0
  fi
  if ss -lntp | grep -q "127.0.0.1:${PANEL_PORT}\\b"; then
    green "OK：面板后端端口 127.0.0.1:${PANEL_PORT} 正在监听"
  else
    red "警告：Nginx 指向 127.0.0.1:${PANEL_PORT}，但没有看到该本机端口监听"
    ok=0
  fi
  if ss -lntp | grep -q ":443\\b.*nginx"; then
    green "OK：443 由 nginx 监听"
  else
    red "警告：443 不是 nginx 监听，或没有监听"
    ok=0
  fi
  if grep -Rqs "proxy_pass http://127.0.0.1:${XHTTP_PORT}" /etc/nginx/conf.d; then
    green "OK：Nginx xhttp 反代端口匹配"
  else
    red "警告：没有找到 Nginx -> 127.0.0.1:${XHTTP_PORT} 的 xhttp 反代"
    ok=0
  fi
  if grep -Rqs "proxy_pass https://127.0.0.1:${PANEL_PORT}" /etc/nginx/conf.d; then
    green "OK：Nginx 面板反代端口匹配"
  else
    red "警告：没有找到 Nginx -> 127.0.0.1:${PANEL_PORT} 的面板反代"
    ok=0
  fi
  echo
  if [ "$ok" = "1" ]; then
    green "一致性检查通过。"
  else
    yellow "存在不匹配项。建议检查 3x-ui 面板监听，或重新执行 4 配置 Nginx 分流。"
  fi
}

main_menu() {
  need_root
  ensure_dirs
  load_config
  while true; do
    clear
    echo "xhttp-node 管理脚本"
    echo
    echo "1. 安装基础环境"
    echo "2. 安装/检查 3x-ui"
    echo "3. 配置 Cloudflare 域名和源站证书"
    echo "4. 配置 Nginx 443 分流"
    echo "5. 配置静态网站目录"
    echo "6. 检查 3x-ui 面板监听"
    echo "7. 输出 xhttp 入站填写参数"
    echo "8. 检查端口和服务状态"
    echo "9. 测试网站 / 面板 / xhttp 路径"
    echo "10. 备份当前配置"
    echo "11. 恢复上一次备份"
    echo "12. 安装/修复快捷命令"
    echo "13. 检查 Nginx 与 3x-ui 配置是否匹配"
    echo "0. 退出"
    echo
    read -r -p "请选择: " choice
    case "$choice" in
      1) install_base; pause ;;
      2) install_or_check_3xui; pause ;;
      3) cloudflare_menu ;;
      4) nginx_menu ;;
      5) static_menu ;;
      6) check_panel_listen; pause ;;
      7) print_xhttp_params; pause ;;
      8) check_services_ports; pause ;;
      9) test_endpoints; pause ;;
      10) backup_now; pause ;;
      11) restore_latest_backup; pause ;;
      12) install_shortcut; pause ;;
      13) consistency_check; pause ;;
      0) exit 0 ;;
      *) yellow "无效选择"; pause ;;
    esac
  done
}

main_menu "$@"
