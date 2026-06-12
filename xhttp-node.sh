#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="xhttp-node"
INSTALL_DIR="/usr/local/xhttp-node"
CONFIG_DIR="/etc/xhttp-node"
CONFIG_FILE="${CONFIG_DIR}/config.env"
BACKUP_DIR="/root/xhttp-node-backups"

DOMAIN=""
PANEL_DOMAIN=""
XHTTP_PATH=""
XHTTP_PORT=""
PANEL_PORT=""
PANEL_SCHEME=""
PANEL_PUBLIC_PATH=""
PANEL_BACKEND_PATH=""
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
}

save_config() {
  ensure_dirs
  local q_domain q_panel_domain q_xhttp_path q_xhttp_port q_panel_port q_panel_scheme q_panel_public_path q_panel_backend_path q_web_root q_cert_file q_key_file
  q_domain="$(printf "%s" "$DOMAIN" | sed "s/'/'\\\\''/g")"
  q_panel_domain="$(printf "%s" "$PANEL_DOMAIN" | sed "s/'/'\\\\''/g")"
  q_xhttp_path="$(printf "%s" "$XHTTP_PATH" | sed "s/'/'\\\\''/g")"
  q_xhttp_port="$(printf "%s" "$XHTTP_PORT" | sed "s/'/'\\\\''/g")"
  q_panel_port="$(printf "%s" "$PANEL_PORT" | sed "s/'/'\\\\''/g")"
  q_panel_scheme="$(printf "%s" "$PANEL_SCHEME" | sed "s/'/'\\\\''/g")"
  q_panel_public_path="$(printf "%s" "$PANEL_PUBLIC_PATH" | sed "s/'/'\\\\''/g")"
  q_panel_backend_path="$(printf "%s" "$PANEL_BACKEND_PATH" | sed "s/'/'\\\\''/g")"
  q_web_root="$(printf "%s" "$WEB_ROOT" | sed "s/'/'\\\\''/g")"
  q_cert_file="$(printf "%s" "$CERT_FILE" | sed "s/'/'\\\\''/g")"
  q_key_file="$(printf "%s" "$KEY_FILE" | sed "s/'/'\\\\''/g")"
  cat > "$CONFIG_FILE" <<EOF
DOMAIN='${q_domain}'
PANEL_DOMAIN='${q_panel_domain}'
XHTTP_PATH='${q_xhttp_path}'
XHTTP_PORT='${q_xhttp_port}'
PANEL_PORT='${q_panel_port}'
PANEL_SCHEME='${q_panel_scheme}'
PANEL_PUBLIC_PATH='${q_panel_public_path}'
PANEL_BACKEND_PATH='${q_panel_backend_path}'
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
  if [ -n "$default_value" ]; then
    read -r -p "${label} [默认: ${default_value}]: " value
    if [ -z "$value" ]; then value="$default_value"; fi
  else
    read -r -p "${label} [无默认，必须输入]: " value
  fi
  value="$(printf "%s" "$value" | LC_ALL=C tr -d '[:cntrl:]')"
  printf -v "$var_name" '%s' "$value"
}

prompt_common() {
  load_config
  detect_xui_panel_settings || true
  prompt_default DOMAIN "请输入主域名" "${DOMAIN:-}"
  prompt_default PANEL_DOMAIN "请输入面板域名" "${PANEL_DOMAIN:-}"
  prompt_default XHTTP_PATH "请输入 xhttp 路径" "${XHTTP_PATH:-}"
  prompt_default XHTTP_PORT "请输入 xhttp 本机端口" "${XHTTP_PORT:-}"
  prompt_default PANEL_PUBLIC_PATH "请输入面板公网路径" "${PANEL_PUBLIC_PATH:-}"
  if [ -n "${PANEL_PORT:-}" ] && [ -n "${PANEL_SCHEME:-}" ] && [ -n "${PANEL_BACKEND_PATH:-}" ]; then
    yellow "面板后端从 3x-ui 当前配置读取：${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH}"
  else
    red "没有读取到 3x-ui 面板后端配置。"
    red "请先执行 2 安装/检查 3x-ui，或用 x-ui -> 10 查看当前设置。"
    return 1
  fi
  prompt_default WEB_ROOT "请输入静态网站目录" "${WEB_ROOT:-}"
  prompt_default CERT_FILE "请输入证书路径" "${CERT_FILE:-}"
  prompt_default KEY_FILE "请输入私钥路径" "${KEY_FILE:-}"
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
  [[ "$PANEL_PUBLIC_PATH" == /* ]] || { red "面板公网路径必须以 / 开头。"; return 1; }
  [[ "$PANEL_BACKEND_PATH" == /* ]] || { red "面板后端路径必须以 / 开头。"; return 1; }
  [[ "$PANEL_PUBLIC_PATH" == */ ]] || PANEL_PUBLIC_PATH="${PANEL_PUBLIC_PATH}/"
  [[ "$PANEL_BACKEND_PATH" == */ ]] || PANEL_BACKEND_PATH="${PANEL_BACKEND_PATH}/"
  [[ "$PANEL_SCHEME" == "http" || "$PANEL_SCHEME" == "https" ]] || { red "面板后端协议只能是 http 或 https。"; return 1; }
  validate_port "$XHTTP_PORT" || { red "xhttp 端口无效。"; return 1; }
  validate_port "$PANEL_PORT" || { red "面板端口无效。"; return 1; }
}

detect_xui_panel_settings() {
  command -v python3 >/dev/null 2>&1 || return 1
  local detected
  detected="$(python3 <<'PY' 2>/dev/null || true
import os
import shlex
import sqlite3

db_candidates = [
    "/etc/x-ui/x-ui.db",
    "/usr/local/x-ui/bin/x-ui.db",
    "/usr/local/x-ui/x-ui.db",
]

def norm_key(value):
    return "".join(ch for ch in str(value).lower() if ch.isalnum())

def norm_path(value):
    value = (value or "/").strip() or "/"
    if not value.startswith("/"):
        value = "/" + value
    if not value.endswith("/"):
        value += "/"
    return value

def useful(value):
    if value is None:
        return ""
    value = str(value).strip()
    if value.lower() in {"", "null", "none", "<nil>"}:
        return ""
    return value

settings = {}
db_path = ""

for candidate in db_candidates:
    if not os.path.exists(candidate):
        continue
    try:
        conn = sqlite3.connect(f"file:{candidate}?mode=ro", uri=True)
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cur.fetchall()]
        for table in tables:
            if "setting" not in norm_key(table):
                continue
            quoted_table = '"' + table.replace('"', '""') + '"'
            try:
                cur.execute(f"PRAGMA table_info({quoted_table})")
                cols = [row[1] for row in cur.fetchall()]
            except Exception:
                continue
            lower_cols = {c.lower(): c for c in cols}
            key_col = lower_cols.get("key") or lower_cols.get("name")
            value_col = lower_cols.get("value")
            if not key_col or not value_col:
                continue
            quoted_key = '"' + key_col.replace('"', '""') + '"'
            quoted_value = '"' + value_col.replace('"', '""') + '"'
            try:
                cur.execute(f"SELECT {quoted_key}, {quoted_value} FROM {quoted_table}")
                for key, value in cur.fetchall():
                    settings[norm_key(key)] = useful(value)
            except Exception:
                continue
        conn.close()
        if settings:
            db_path = candidate
            break
    except Exception:
        continue

def pick(*keys):
    for key in keys:
        value = settings.get(norm_key(key))
        if value:
            return value
    return ""

port = pick("webPort", "web_port", "panelPort", "panel_port", "port")
try:
    port_num = int(port)
    if port_num < 1 or port_num > 65535:
        port = ""
except Exception:
    port = ""

raw_base_path = pick("webBasePath", "web_base_path", "basePath", "webPath", "path")
base_path = norm_path(raw_base_path) if raw_base_path else ""
cert_file = pick("webCertFile", "web_cert_file", "certFile", "cert_file")
key_file = pick("webKeyFile", "web_key_file", "keyFile", "key_file")
scheme = "https" if cert_file and key_file and os.path.exists(cert_file) and os.path.exists(key_file) else "http"

if port:
    print(f"DETECTED_PANEL_PORT={shlex.quote(port)}")
    if base_path:
        print(f"DETECTED_PANEL_BACKEND_PATH={shlex.quote(base_path)}")
    print(f"DETECTED_PANEL_SCHEME={shlex.quote(scheme)}")
    print(f"DETECTED_XUI_DB={shlex.quote(db_path)}")
PY
)"
  [ -n "$detected" ] || return 1
  eval "$detected"
  [ -n "${DETECTED_PANEL_PORT:-}" ] || return 1
  PANEL_PORT="$DETECTED_PANEL_PORT"
  if [ -n "${DETECTED_PANEL_BACKEND_PATH:-}" ]; then
    PANEL_BACKEND_PATH="$DETECTED_PANEL_BACKEND_PATH"
  fi
  PANEL_SCHEME="${DETECTED_PANEL_SCHEME:-http}"
  yellow "已读取 3x-ui 当前面板配置：${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH}"
  [ -n "${DETECTED_XUI_DB:-}" ] && yellow "配置来源：${DETECTED_XUI_DB}（只读）"
}

save_detected_xui_panel_settings() {
  load_config
  if detect_xui_panel_settings; then
    save_config
    green "已同步 3x-ui 面板后端默认值到 ${CONFIG_FILE}"
  else
    yellow "暂时没有读取到 3x-ui 面板端口；后续配置 Nginx 时会提示你手动确认。"
  fi
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
    save_detected_xui_panel_settings
    return 0
  fi
  yellow "未检测到 3x-ui。"
  read -r -p "是否使用官方脚本安装 3x-ui？[y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] || return 0
  bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
  save_detected_xui_panel_settings
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
  prompt_default DOMAIN "请输入主域名" "${DOMAIN:-}"
  prompt_default PANEL_DOMAIN "请输入面板域名" "${PANEL_DOMAIN:-}"
  detect_xui_panel_settings || true
  save_config

  echo
  echo "认证方式："
  echo "1. Cloudflare Global API Key + 账号邮箱（推荐）"
  echo "2. Cloudflare API Token (Bearer，需要能创建 Origin CA 证书)"
  echo "3. Cloudflare Origin CA Key（旧方式；如果后台显示已弃用/禁用，请不要选）"
  read -r -p "请选择 [默认: 1]: " auth_mode
  auth_mode="${auth_mode:-1}"
  read -r -s -p "请输入 Cloudflare 密钥/Token: " cf_secret
  echo
  cf_email=""
  if [ "$auth_mode" = "1" ]; then
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
    headers["X-Auth-Email"] = email
    headers["X-Auth-Key"] = secret
elif mode == "2":
    headers["Authorization"] = f"Bearer {secret}"
elif mode == "3":
    headers["X-Auth-User-Service-Key"] = secret
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
    print()
    print("Cloudflare 认证失败排查：")
    print("- 使用 Global API Key 时，请选择 1，并填写这个 Cloudflare 账号的登录邮箱。")
    print("- 使用 API Token 时，请选择 2；只带 DNS Edit 权限的 Token 通常不够。")
    print("- 如果后台显示 Origin CA Key 已弃用/禁用，请不要选择 3。")
    raise SystemExit(1)

data = json.loads(body)
if not data.get("success"):
    errors = data.get("errors") or []
    print(json.dumps(errors, ensure_ascii=False))
    for err in errors:
        code = err.get("code")
        msg = err.get("message", "")
        if code == 1010 or "not part of your account" in msg:
            print()
            print("提示：Cloudflare 认为这个域名不在当前账号下面。")
            print(f"请确认 {domain} 确实在你输入邮箱对应的 Cloudflare 账号中，")
            print("并且 Global API Key 也来自同一个账号。")
        if code == 9106:
            print()
            print("提示：Authentication failed。请确认选择的认证方式和密钥类型一致。")
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
    headers["X-Auth-Email"] = email
    headers["X-Auth-Key"] = secret
elif mode == "2":
    headers["Authorization"] = f"Bearer {secret}"
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
  prompt_default DOMAIN "请输入主域名" "${DOMAIN:-}"
  prompt_default PANEL_DOMAIN "请输入面板域名" "${PANEL_DOMAIN:-}"
  local src_cert src_key
  prompt_default src_cert "请输入已有证书文件路径" "${CERT_FILE:-}"
  prompt_default src_key "请输入已有私钥文件路径" "${KEY_FILE:-}"
  detect_xui_panel_settings || true
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
  local panel_location
  panel_location="$PANEL_PUBLIC_PATH"
  if [ "$PANEL_BACKEND_PATH" = "/" ]; then
    panel_location="/"
  fi
  cat > "/etc/nginx/conf.d/${PANEL_DOMAIN}.conf" <<EOF
server {
    listen 443 ssl http2;
    server_name ${PANEL_DOMAIN};

    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};

    location = ${PANEL_PUBLIC_PATH%/} {
        return 301 ${PANEL_PUBLIC_PATH};
    }

    location ${panel_location} {
        proxy_pass ${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH};
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
  echo "https://${PANEL_DOMAIN}${PANEL_PUBLIC_PATH}  -> ${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH}"
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
        prompt_default WEB_ROOT "请输入静态网站目录" "${WEB_ROOT:-}"
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
        prompt_default WEB_ROOT "请输入目标静态网站目录" "${WEB_ROOT:-}"
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
        prompt_default WEB_ROOT "请输入静态网站目录" "${WEB_ROOT:-}"
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
  detect_xui_panel_settings || true
  blue "检查 3x-ui 面板监听"
  echo "当前 xhttp-node 面板配置："
  echo "公网入口：https://${PANEL_DOMAIN}${PANEL_PUBLIC_PATH}"
  echo "后端地址：${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH}"
  echo
  systemctl is-active x-ui || true
  ss -lntp | grep -E ":${PANEL_PORT}\\b" || true
  echo
  echo "公网访问面板链接："
  echo "https://${PANEL_DOMAIN}${PANEL_PUBLIC_PATH}"
  echo
  echo "本机直连检测地址："
  echo "${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH}"
  echo
  echo "检测本机面板："
  curl -k -sS -D - --max-time 8 "${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH}" -o /tmp/xhttp-node-panel-check 2>&1 | sed -n '1,14p' || true
  echo
  yellow "如果本机检测不通，请确认 3x-ui 当前端口、SSL 状态和 Web Base Path。"
  yellow "脚本会优先读取 3x-ui 当前配置；如果读取不到，请用 x-ui -> 10 查看真实端口和路径后手动填写。"
  yellow "如果本机通但公网不通，请执行 4 配置 Nginx 443 分流，或检查 Cloudflare DNS/小云朵。"
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
  detect_xui_panel_settings || true
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
  echo "${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH}    x-ui 面板后端"
}

test_endpoints() {
  load_config
  detect_xui_panel_settings || true
  blue "测试网站 / 面板 / xhttp 路径"
  echo "本机经 Nginx 测试静态网站："
  curl -k -I --max-time 10 --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/" || true
  echo
  echo "本机经 Nginx 测试 xhttp 路径（普通 curl 返回 404/空响应可能正常）："
  curl -k -i --max-time 10 --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}${XHTTP_PATH}" | sed -n '1,16p' || true
  echo
  echo "本机经 Nginx 测试面板："
  curl -k -I --max-time 10 --resolve "${PANEL_DOMAIN}:443:127.0.0.1" "https://${PANEL_DOMAIN}${PANEL_PUBLIC_PATH}" || true
  echo
  read -r -p "是否也测试公网域名？[y/N]: " ok
  if [[ "$ok" =~ ^[Yy]$ ]]; then
    curl -I --max-time 20 "https://${DOMAIN}/" || true
    curl -I --max-time 20 "https://${PANEL_DOMAIN}${PANEL_PUBLIC_PATH}" || true
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
  detect_xui_panel_settings || true
  blue "检查 Nginx 与 3x-ui 当前状态是否匹配"
  local ok=1
  if ss -lntp | grep -q "127.0.0.1:${XHTTP_PORT}\\b"; then
    green "OK：xhttp 后端端口 127.0.0.1:${XHTTP_PORT} 正在监听"
  else
    red "警告：Nginx 指向 127.0.0.1:${XHTTP_PORT}，但没有看到该本机端口监听"
    ok=0
  fi
  if ss -lntp | grep -q ":${PANEL_PORT}\\b"; then
    green "OK：面板后端端口 ${PANEL_PORT} 正在监听"
  else
    red "警告：Nginx 指向 127.0.0.1:${PANEL_PORT}，但没有看到该端口监听"
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
  if grep -Rqs "proxy_pass ${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH}" /etc/nginx/conf.d; then
    green "OK：Nginx 面板反代端口匹配"
  else
    red "警告：没有找到 Nginx -> ${PANEL_SCHEME}://127.0.0.1:${PANEL_PORT}${PANEL_BACKEND_PATH} 的面板反代"
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
