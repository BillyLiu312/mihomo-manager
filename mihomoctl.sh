#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="${MIHOMO_HOME:-$HOME/.config/mihomo}"
BIN="${MIHOMO_BIN:-$CONFIG_DIR/clash-linux}"
CONFIG_FILE="${MIHOMO_CONFIG:-$CONFIG_DIR/config.yaml}"
ENV_FILE="${MIHOMO_ENV:-$CONFIG_DIR/subscription.env}"
LOG_FILE="${MIHOMO_LOG:-$CONFIG_DIR/mihomo.log}"
PID_FILE="${MIHOMO_PID:-$CONFIG_DIR/mihomo.pid}"
MIXED_PORT="${MIHOMO_PORT:-7890}"
DEFAULT_UA="${MIHOMO_USER_AGENT:-Clash.Meta}"

usage() {
  cat <<'USAGE'
mihomoctl - small Clash/Mihomo manager for remote Linux servers

Usage:
  ./mihomoctl.sh init
  ./mihomoctl.sh set-url 'https://example.com/api/v1/client/subscribe?token=xxx&flag=clash'
  ./mihomoctl.sh set-token NEW_TOKEN
  ./mihomoctl.sh fetch
  ./mihomoctl.sh start
  ./mihomoctl.sh stop
  ./mihomoctl.sh restart
  ./mihomoctl.sh status
  ./mihomoctl.sh logs [-f] [-n 100]
  ./mihomoctl.sh test [URL]
  ./mihomoctl.sh env
  ./mihomoctl.sh run COMMAND [ARGS...]
  ./mihomoctl.sh update-geodata
  ./mihomoctl.sh config

Environment overrides:
  MIHOMO_HOME        default: ~/.config/mihomo
  MIHOMO_BIN         default: ~/.config/mihomo/clash-linux
  MIHOMO_CONFIG      default: ~/.config/mihomo/config.yaml
  MIHOMO_PORT        default: 7890

Notes:
  - Tokens are stored in ~/.config/mihomo/subscription.env with chmod 600.
  - start uses nohup and writes logs to ~/.config/mihomo/mihomo.log.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

init_dirs() {
  mkdir -p "$CONFIG_DIR"
  touch "$LOG_FILE"
  chmod 700 "$CONFIG_DIR" 2>/dev/null || true
  chmod 600 "$ENV_FILE" "$LOG_FILE" 2>/dev/null || true
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
  SUB_URL="${SUB_URL:-}"
  USER_AGENT="${USER_AGENT:-$DEFAULT_UA}"
}

quote_value() {
  printf "%q" "$1"
}

save_env_var() {
  local key="$1"
  local value="$2"
  local tmp
  init_dirs
  tmp="$(mktemp "$CONFIG_DIR/.subscription.env.XXXXXX")"
  local found=0

  if [[ -f "$ENV_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in
        "$key="*)
          printf "%s=%s\n" "$key" "$(quote_value "$value")" >> "$tmp"
          found=1
          ;;
        *)
          printf "%s\n" "$line" >> "$tmp"
          ;;
      esac
    done < "$ENV_FILE"
  fi

  if [[ "$found" -eq 0 ]]; then
    printf "%s=%s\n" "$key" "$(quote_value "$value")" >> "$tmp"
  fi

  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

mask_url() {
  sed -E 's/(token=)[^&[:space:]]+/\1***MASKED***/g' <<< "${1:-}"
}

ensure_clash_flag() {
  local url="$1"
  case "$url" in
    *"flag="*) printf "%s" "$url" ;;
    *"?"*) printf "%s&flag=clash" "$url" ;;
    *) printf "%s?flag=clash" "$url" ;;
  esac
}

download_to() {
  local url="$1"
  local out="$2"
  local ua="${3:-$DEFAULT_UA}"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 2 -A "$ua" -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -U "$ua" -O "$out" "$url"
  else
    die "curl or wget is required"
  fi
}

validate_config() {
  local file="$1"
  [[ -s "$file" ]] || die "downloaded config is empty: $file"

  if grep -Eq '^(proxies|proxy-groups|rules|mixed-port|port|socks-port|redir-port|tproxy-port):' "$file"; then
    return 0
  fi

  local first
  first="$(head -c 120 "$file" | tr -d '\r\n' || true)"
  if grep -Eq '^(ss|ssr|vmess|vless|trojan)://' <<< "$first" || grep -Eq '^[A-Za-z0-9+/=]{80,}$' <<< "$first"; then
    die "subscription looks like raw/base64 node list, not Clash/Mihomo YAML. Use a Clash/Mihomo subscription URL, usually with &flag=clash."
  fi

  info "warning: config was downloaded, but YAML shape was not recognized. Continuing anyway."
}

running_pid() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      printf "%s" "$pid"
      return 0
    fi
  fi
  return 1
}

cmd_init() {
  init_dirs
  if [[ ! -f "$ENV_FILE" ]]; then
    {
      printf "SUB_URL=\n"
      printf "USER_AGENT=%s\n" "$(quote_value "$DEFAULT_UA")"
    } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
  fi
  info "initialized $CONFIG_DIR"
  info "binary expected at: $BIN"
}

cmd_set_url() {
  [[ $# -eq 1 ]] || die "usage: $0 set-url 'SUBSCRIPTION_URL'"
  local url
  url="$(ensure_clash_flag "$1")"
  save_env_var SUB_URL "$url"
  save_env_var USER_AGENT "$DEFAULT_UA"
  info "subscription URL saved: $(mask_url "$url")"
}

cmd_set_token() {
  [[ $# -eq 1 ]] || die "usage: $0 set-token NEW_TOKEN"
  load_env
  [[ -n "$SUB_URL" ]] || die "no SUB_URL saved yet. Run set-url first."
  [[ "$SUB_URL" == *"token="* ]] || die "saved SUB_URL has no token= parameter. Use set-url instead."

  local token="$1"
  local prefix rest suffix new_url
  prefix="${SUB_URL%%token=*}token="
  rest="${SUB_URL#*token=}"
  if [[ "$rest" == *"&"* ]]; then
    suffix="&${rest#*&}"
  else
    suffix=""
  fi
  new_url="$(ensure_clash_flag "${prefix}${token}${suffix}")"
  save_env_var SUB_URL "$new_url"
  info "token replaced: $(mask_url "$new_url")"
  info "run './mihomoctl.sh fetch' then './mihomoctl.sh restart' to apply it"
}

cmd_fetch() {
  init_dirs
  load_env
  [[ -n "$SUB_URL" ]] || die "SUB_URL is empty. Run set-url first."
  local tmp
  tmp="$(mktemp "$CONFIG_DIR/config.yaml.XXXXXX")"
  info "downloading config from: $(mask_url "$SUB_URL")"
  download_to "$SUB_URL" "$tmp" "$USER_AGENT"
  validate_config "$tmp"
  mv "$tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  info "config saved: $CONFIG_FILE"
}

cmd_start() {
  init_dirs
  [[ -x "$BIN" ]] || die "mihomo/clash binary not executable: $BIN"
  [[ -f "$CONFIG_FILE" ]] || die "config not found: $CONFIG_FILE. Run fetch first."

  if pid="$(running_pid)"; then
    info "already running, pid=$pid"
    return 0
  fi

  info "starting in background..."
  nohup "$BIN" -d "$CONFIG_DIR" >> "$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  sleep 1

  if kill -0 "$pid" 2>/dev/null; then
    info "started, pid=$pid, log=$LOG_FILE"
  else
    tail -n 80 "$LOG_FILE" >&2 || true
    die "failed to start"
  fi
}

cmd_stop() {
  if pid="$(running_pid)"; then
    info "stopping pid=$pid"
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$PID_FILE"
        info "stopped"
        return 0
      fi
      sleep 1
    done
    info "process still alive, sending SIGKILL"
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    info "stopped"
  else
    rm -f "$PID_FILE"
    info "not running"
  fi
}

cmd_restart() {
  cmd_stop
  cmd_start
}

cmd_status() {
  load_env
  echo "Config dir : $CONFIG_DIR"
  echo "Binary     : $BIN"
  echo "Config     : $CONFIG_FILE"
  echo "Log        : $LOG_FILE"
  echo "Subscribe  : $(mask_url "$SUB_URL")"
  echo "Proxy env  : http://127.0.0.1:$MIXED_PORT / socks5://127.0.0.1:$MIXED_PORT"

  if pid="$(running_pid)"; then
    echo "Status     : running, pid=$pid"
  else
    echo "Status     : stopped"
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep -E "(:$MIXED_PORT|:9090)" || true
  fi

  if [[ -f "$LOG_FILE" ]]; then
    echo
    echo "Recent log:"
    tail -n 20 "$LOG_FILE" || true
  fi
}

cmd_logs() {
  init_dirs
  local follow=0
  local lines=100
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--follow) follow=1; shift ;;
      -n|--lines)
        [[ $# -ge 2 ]] || die "-n requires a number"
        lines="$2"
        shift 2
        ;;
      *) die "unknown logs option: $1" ;;
    esac
  done
  if [[ "$follow" -eq 1 ]]; then
    tail -n "$lines" -f "$LOG_FILE"
  else
    tail -n "$lines" "$LOG_FILE"
  fi
}

cmd_env() {
  cat <<ENV
export HTTP_PROXY=http://127.0.0.1:$MIXED_PORT
export HTTPS_PROXY=http://127.0.0.1:$MIXED_PORT
export ALL_PROXY=socks5://127.0.0.1:$MIXED_PORT
export http_proxy=http://127.0.0.1:$MIXED_PORT
export https_proxy=http://127.0.0.1:$MIXED_PORT
export all_proxy=socks5://127.0.0.1:$MIXED_PORT
ENV
}

cmd_run() {
  [[ $# -ge 1 ]] || die "usage: $0 run COMMAND [ARGS...]"
  HTTP_PROXY="http://127.0.0.1:$MIXED_PORT" \
  HTTPS_PROXY="http://127.0.0.1:$MIXED_PORT" \
  ALL_PROXY="socks5://127.0.0.1:$MIXED_PORT" \
  http_proxy="http://127.0.0.1:$MIXED_PORT" \
  https_proxy="http://127.0.0.1:$MIXED_PORT" \
  all_proxy="socks5://127.0.0.1:$MIXED_PORT" \
  "$@"
}

cmd_test() {
  local url="${1:-https://api.openai.com/v1/models}"
  if ! pid="$(running_pid)"; then
    info "mihomo is not recorded as running. Testing anyway..."
  fi
  info "testing through proxy: $url"
  cmd_run curl -I --connect-timeout 10 "$url"
}

cmd_update_geodata() {
  init_dirs
  local geosite="$CONFIG_DIR/GeoSite.dat"
  local geoip="$CONFIG_DIR/GeoIP.dat"
  local base="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest"

  info "downloading GeoSite.dat"
  download_to "$base/geosite.dat" "$geosite.tmp" "$DEFAULT_UA"
  mv "$geosite.tmp" "$geosite"

  info "downloading GeoIP.dat"
  download_to "$base/geoip.dat" "$geoip.tmp" "$DEFAULT_UA"
  mv "$geoip.tmp" "$geoip"

  cp "$geosite" "$CONFIG_DIR/geosite.dat" 2>/dev/null || true
  cp "$geoip" "$CONFIG_DIR/geoip.dat" 2>/dev/null || true
  info "geodata updated in $CONFIG_DIR"
}

cmd_config() {
  load_env
  echo "CONFIG_DIR=$CONFIG_DIR"
  echo "BIN=$BIN"
  echo "CONFIG_FILE=$CONFIG_FILE"
  echo "ENV_FILE=$ENV_FILE"
  echo "LOG_FILE=$LOG_FILE"
  echo "PID_FILE=$PID_FILE"
  echo "MIXED_PORT=$MIXED_PORT"
  echo "SUB_URL=$(mask_url "$SUB_URL")"
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    help|-h|--help) usage ;;
    init) cmd_init "$@" ;;
    set-url) cmd_set_url "$@" ;;
    set-token) cmd_set_token "$@" ;;
    fetch) cmd_fetch "$@" ;;
    start) cmd_start "$@" ;;
    stop) cmd_stop "$@" ;;
    restart) cmd_restart "$@" ;;
    status) cmd_status "$@" ;;
    logs) cmd_logs "$@" ;;
    env) cmd_env "$@" ;;
    run) cmd_run "$@" ;;
    test) cmd_test "$@" ;;
    update-geodata) cmd_update_geodata "$@" ;;
    config) cmd_config "$@" ;;
    *) die "unknown command: $cmd. Run '$0 help'." ;;
  esac
}

main "$@"
