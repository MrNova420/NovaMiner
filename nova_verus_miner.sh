#!/usr/bin/env bash
# Nova All-in-One Verus Miner (fully automated)
# Merged and refined from your repos. Termux + Linux support.

set -euo pipefail

APP_NAME="Nova Verus Miner"
APP_VERSION="2.1.0"
CONFIG_DIR="$HOME/.nova_verus_miner"
CONFIG_FILE="$CONFIG_DIR/config.conf"
LOG_DIR="$CONFIG_DIR/logs"
RUN_INFO_FILE="$CONFIG_DIR/run.info"
MINERS_DIR="$CONFIG_DIR/miners"
ACTIVE_MINER_FILE="$CONFIG_DIR/active_miner"
WATCHDOG_PID_FILE="$CONFIG_DIR/watchdog.pid"
MINER_LOG="$LOG_DIR/miner.log"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"

# Repo used for script updates (set this to your new repo)
GITHUB_UPDATES_REPO="YOUR_USERNAME/Nova-All-In-One-Verus-Miner"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; NC='\033[0m'

TERMUX=0; CPU_ARCH="unknown"; ROOT=0
WALLET=""; POOL=""; THREADS=0; WORKER=""; MODE="balanced"
MINER_PROFILE="cpuminer-verus"; CUSTOM_TEMPLATE=""
MINER_NAME=""; MINER_PATH=""
START_TIME=0

cecho() { local c="$1"; shift; echo -e "${c}$*${NC}"; }
pause() { read -rp "Press Enter to continue..."; }

print_banner() {
  clear
  echo -e "${GREEN}===================================================="
  echo -e "  $APP_NAME"
  echo -e "  Version: $APP_VERSION"
  echo -e "  Config:  $CONFIG_DIR"
  echo -e "====================================================${NC}"
}

detect_env() {
  if command -v termux-info >/dev/null 2>&1 || [[ -n "${PREFIX:-}" && "$PREFIX" == *com.termux* ]]; then TERMUX=1; fi
  [ "$(id -u)" -eq 0 ] && ROOT=1 || ROOT=0
  case "$(uname -m)" in
    aarch64) CPU_ARCH="arm64" ;;
    armv7l|armv8l|arm) CPU_ARCH="armv7" ;;
    x86_64) CPU_ARCH="x86_64" ;;
    i686|i386) CPU_ARCH="x86" ;;
    *) CPU_ARCH="unknown" ;;
  esac
}

check_deps() {
  local deps=(curl jq bc sed awk grep)
  local missing=0
  for d in "${deps[@]}"; do
    command -v "$d" >/dev/null 2>&1 || { cecho "$RED" "[!] Missing dependency: $d"; missing=1; }
  done
  [ $missing -eq 1 ] && { cecho "$YELLOW" "[*] Please run ./install.sh"; exit 1; }
}

load_config() {
  [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || true
  WALLET="${WALLET:-}"
  POOL="${POOL:-na.luckpool.net:3956}"
  THREADS="${THREADS:-0}"
  WORKER="${WORKER:-}"
  MODE="${MODE:-balanced}"
  MINER_PROFILE="${MINER_PROFILE:-cpuminer-verus}"
  CUSTOM_TEMPLATE="${CUSTOM_TEMPLATE:-}"
  MINER_NAME="${MINER_NAME:-}"
  MINER_PATH="${MINER_PATH:-}"
  [ -z "$WORKER" ] && WORKER="$(hostname 2>/dev/null || echo device)"
  if [ "$THREADS" -eq 0 ]; then
    if command -v nproc >/dev/null 2>&1; then THREADS=$(nproc); else THREADS=2; fi
  fi
  if [ -f "$ACTIVE_MINER_FILE" ]; then MINER_NAME="$(cat "$ACTIVE_MINER_FILE")"; MINER_PATH="$MINERS_DIR/$MINER_NAME"; fi
}

save_config() {
  cat > "$CONFIG_FILE" <<EOF
WALLET="$WALLET"
POOL="$POOL"
THREADS=$THREADS
WORKER="$WORKER"
MODE="$MODE"
MINER_PROFILE="$MINER_PROFILE"
CUSTOM_TEMPLATE="$CUSTOM_TEMPLATE"
MINER_NAME="$MINER_NAME"
MINER_PATH="$MINER_PATH"
EOF
  [ -n "$MINER_NAME" ] && echo "$MINER_NAME" > "$ACTIVE_MINER_FILE" || true
}

validate_wallet() { [[ "$WALLET" =~ ^R[a-zA-Z0-9]{33,35}$ ]]; }
validate_pool() { [[ "$POOL" =~ ^[a-zA-Z0-9\.\-]+:[0-9]{1,5}$ ]]; }
validate_threads() { [[ "$THREADS" =~ ^[0-9]+$ ]] && [ "$THREADS" -ge 1 ]; }

profile_template() {
  case "$MINER_PROFILE" in
    cpuminer-verus) echo "-a verus -o stratum+tcp://{POOL} -u {WALLET}.{WORKER} -p x -t {THREADS}" ;;
    custom)         echo "$CUSTOM_TEMPLATE" ;;
    *)              echo "-a verus -o stratum+tcp://{POOL} -u {WALLET}.{WORKER} -p x -t {THREADS}" ;;
  esac
}

build_command() {
  local tmpl; tmpl="$(profile_template)"
  tmpl="${tmpl//\{WALLET\}/$WALLET}"
  tmpl="${tmpl//\{POOL\}/$POOL}"
  tmpl="${tmpl//\{THREADS\}/$THREADS}"
  tmpl="${tmpl//\{WORKER\}/$WORKER}"
  echo "$tmpl"
}

miners_list() { find "$MINERS_DIR" -maxdepth 1 -type f -perm -u+x -printf "%f\n" 2>/dev/null || true; }

set_active_miner() {
  local name="$1"
  if [ -x "$MINERS_DIR/$name" ]; then
    MINER_NAME="$name"; MINER_PATH="$MINERS_DIR/$name"
    echo "$MINER_NAME" > "$ACTIVE_MINER_FILE"
    save_config
    cecho "$GREEN" "[✓] Active miner: $MINER_NAME"
  else
    cecho "$RED" "[!] Miner not found: $name"
  fi
}

# Automatic installation: Build first, then attempt prebuilt downloads from your repos
auto_install_miners() {
  if [ -n "$(miners_list)" ]; then return 0; fi
  cecho "$CYAN" "[*] No miners installed. Starting automatic installation (arch: $CPU_ARCH)..."
  if attempt_build_cpuminer_verus; then
    return 0
  fi
  cecho "$YELLOW" "[i] Build failed or unavailable. Trying prebuilt releases from your repos..."
  if try_download_from_your_releases "cpuminer-verus"; then return 0; fi
  if try_download_from_your_releases "verus-miner"; then return 0; fi
  cecho "$RED" "[!] Automated installation failed. Please add a miner to $MINERS_DIR manually."
  return 1
}

try_download_from_your_releases() {
  local base_name="$1"
  local arch="$CPU_ARCH"
  local repos=("MrNova420/NovaVerusMiner" "MrNova420/Novas-Auto-Verus-Miner" "YOUR_USERNAME/Nova-All-In-One-Verus-Miner")
  local asset
  asset="${base_name}-${arch}"
  for repo in "${repos[@]}"; do
    local url="https://github.com/${repo}/releases/latest/download/${asset}"
    local out="$MINERS_DIR/${base_name}-${arch}"
    cecho "$CYAN" "[*] Fetching $asset from $repo ..."
    if curl -fsSL -o "$out" "$url"; then
      chmod +x "$out"
      set_active_miner "$(basename "$out")"
      cecho "$GREEN" "[✓] Installed from releases: $repo ($asset)"
      return 0
    fi
  done
  return 1
}

attempt_build_cpuminer_verus() {
  cecho "$CYAN" "[*] Building cpuminer-verus from source..."
  local build_dir="$CONFIG_DIR/build_cpuminer"
  rm -rf "$build_dir"; mkdir -p "$build_dir"
  cd "$build_dir"

  set +e
  git clone --depth=1 https://github.com/monkins1010/cpuminer-verus.git src 2>/dev/null
  if [ ! -d src ]; then
    git clone --depth=1 https://github.com/monkins1010/cpuminer-multi.git src 2>/dev/null
  fi
  set -e
  if [ ! -d src ]; then
    cecho "$YELLOW" "[i] Could not clone cpuminer-verus sources."
    return 1
  fi

  cd src
  if [ -f "./build.sh" ]; then chmod +x ./build.sh; ./build.sh || true; fi
  if [ -f "./autogen.sh" ]; then chmod +x autogen.sh; ./autogen.sh || true; fi
  if [ -f "./configure" ]; then ./configure CFLAGS="-O3" || true; fi
  if command -v make >/dev/null 2>&1; then make -j"$(nproc 2>/dev/null || echo 2)" || true; fi

  local bin
  bin=$(find . -type f -perm -u+x -name "cpuminer*" -o -name "verus*" | head -n1 || true)
  if [ -z "$bin" ]; then
    cecho "$YELLOW" "[i] Build produced no usable binary."
    return 1
  fi

  local name="cpuminer-verus-built"
  cp "$bin" "$MINERS_DIR/$name"
  chmod +x "$MINERS_DIR/$name"
  set_active_miner "$name"
  cecho "$GREEN" "[✓] Built and installed miner: $name"
  return 0
}

ensure_miner() {
  if [ -n "$MINER_PATH" ] && [ -x "$MINER_PATH" ]; then return 0; fi
  auto_install_miners || { cecho "$RED" "[!] No miner available."; exit 1; }
  # Refresh MINER_NAME/PATH from active file
  if [ -f "$ACTIVE_MINER_FILE" ]; then MINER_NAME="$(cat "$ACTIVE_MINER_FILE")"; MINER_PATH="$MINERS_DIR/$MINER_NAME"; fi
}

write_run_info() {
  local status="${1:-unknown}"
  local err="${2:-0}"
  local runtime=0
  if [ "$START_TIME" -ne 0 ]; then runtime=$(( $(date +%s) - START_TIME )); fi

  local cpu_model mem_total mem_free
  cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | xargs || echo "N/A")
  mem_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "N/A")
  mem_free=$(grep MemFree /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "N/A")
  local hash_rate="N/A"
  if [ -f "$MINER_LOG" ]; then
    hash_rate=$(tail -n 50 "$MINER_LOG" | grep -oE '[0-9]+(\.[0-9]+)?[kM]?H/s' | tail -n1)
    [ -z "$hash_rate" ] && hash_rate="N/A"
  fi
  cat > "$RUN_INFO_FILE" <<EOF
Timestamp: $(date +"%Y-%m-%d %H:%M:%S")
Status: $status
Error: $err
RuntimeSeconds: $runtime
CPU: $cpu_model
MemTotalKB: $mem_total
MemFreeKB: $mem_free
Wallet: $WALLET
Pool: $POOL
Threads: $THREADS
Mode: $MODE
Miner: $MINER_NAME
HashRateApprox: $hash_rate
EOF
}

notify_user() {
  local msg="$1"
  if [ $TERMUX -eq 1 ] && command -v termux-notification >/dev/null 2>&1; then
    termux-notification --title "$APP_NAME" --content "$msg" --priority high || true
  fi
  echo "$(date '+%F %T') $msg" >> "$WATCHDOG_LOG"
}

start_miner() {
  ensure_miner
  validate_wallet || { cecho "$RED" "[!] Invalid wallet."; return 1; }
  validate_pool || { cecho "$RED" "[!] Invalid pool (host:port)."; return 1; }
  validate_threads || { cecho "$RED" "[!] Invalid thread count."; return 1; }

  if [ -f "$CONFIG_DIR/miner.pid" ] && kill -0 "$(cat "$CONFIG_DIR/miner.pid")" 2>/dev/null; then
    cecho "$YELLOW" "[*] Miner already running (PID $(cat "$CONFIG_DIR/miner.pid"))."
    return 0
  fi

  mkdir -p "$LOG_DIR"; : > "$MINER_LOG"

  local t="$THREADS"
  case "$MODE" in
    lowpower) t=1 ;;
    balanced) t=$(( THREADS > 1 ? THREADS/2 : 1 )) ;;
    boosted)  t="$THREADS" ;;
    custom)   t="$THREADS" ;;
  endac
  local cmd_args; cmd_args="$(build_command)"
  cmd_args="${cmd_args//\{THREADS\}/$t}"

  cecho "$GREEN" "[*] Starting miner: $MINER_NAME"
  nohup "$MINER_PATH" $cmd_args >>"$MINER_LOG" 2>&1 &
  local pid=$!
  echo "$pid" > "$CONFIG_DIR/miner.pid"
  START_TIME=$(date +%s)
  write_run_info "running" 0
  cecho "$GREEN" "[✓] Miner started (PID $pid). Logs: $MINER_LOG"
}

stop_miner() {
  local pid_file="$CONFIG_DIR/miner.pid"
  if [ -f "$pid_file" ]; then
    local pid; pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      cecho "$YELLOW" "[*] Stopping miner (PID $pid)..."
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
      rm -f "$pid_file"
      START_TIME=0
      write_run_info "stopped" 0
      cecho "$GREEN" "[✓] Miner stopped."
      return 0
    fi
  fi
  cecho "$YELLOW" "[*] Miner not running."
}

miner_status() {
  local pid_file="$CONFIG_DIR/miner.pid"
  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo -e "${GREEN}Miner running (PID $(cat "$pid_file"))${NC}"
    echo "Wallet: $WALLET"
    echo "Pool: $POOL"
    echo "Threads: $THREADS (mode: $MODE)"
    echo "Miner: $MINER_NAME"
    echo "Log tail:"
    tail -n 15 "$MINER_LOG" || true
  else
    cecho "$RED" "Miner is not running."
  fi
}

restart_miner() { stop_miner; sleep 1; start_miner; }

watchdog_loop() {
  echo $$ > "$WATCHDOG_PID_FILE"
  notify_user "Watchdog started."
  while true; do
    local pid_file="$CONFIG_DIR/miner.pid"
    if [ ! -f "$pid_file" ] || ! kill -0 "$(cat "$pid_file")" 2>/dev/null; then
      cecho "$RED" "[!] Miner not running, restarting..."
      echo "$(date '+%F %T') [restart]" >> "$WATCHDOG_LOG"
      start_miner || true
      notify_user "Miner restarted by watchdog"
    fi
    if [ $TERMUX -eq 1 ] && command -v termux-battery-status >/dev/null 2>&1; then
      local info level plugged
      info="$(termux-battery-status 2>/dev/null || echo '{}')"
      level="$(echo "$info" | jq -r '.percentage // 100' 2>/dev/null)"
      plugged="$(echo "$info" | jq -r '.plugged // "unknown"' 2>/dev/null)"
      if [ "$plugged" != "true" ] && [ "$level" -lt 15 ]; then
        cecho "$YELLOW" "[!] Low battery ($level%). Pausing miner."
        stop_miner
        notify_user "Miner paused: low battery ($level%)"
        sleep 120
      fi
    fi
    sleep 60
  done
}

start_watchdog() {
  if [ -f "$WATCHDOG_PID_FILE" ] && kill -0 "$(cat "$WATCHDOG_PID_FILE")" 2>/dev/null; then
    cecho "$YELLOW" "[*] Watchdog already running (PID $(cat "$WATCHDOG_PID_FILE"))."
    return
  fi
  nohup bash -c "$(declare -f watchdog_loop start_miner stop_miner notify_user write_run_info build_command profile_template validate_wallet validate_pool validate_threads ensure_miner cecho); watchdog_loop" >> "$WATCHDOG_LOG" 2>&1 &
  sleep 1
  cecho "$GREEN" "[✓] Watchdog started."
}

stop_watchdog() {
  if [ -f "$WATCHDOG_PID_FILE" ]; then
    local wpid; wpid="$(cat "$WATCHDOG_PID_FILE")"
    kill "$wpid" 2>/dev/null || true
    sleep 1
    kill -9 "$wpid" 2>/dev/null || true
    rm -f "$WATCHDOG_PID_FILE"
    cecho "$GREEN" "[✓] Watchdog stopped."
  else
    cecho "$YELLOW" "[*] Watchdog not running."
  fi
}

prompt_wallet() {
  while true; do
    read -rp "Enter Verus wallet address (starts with R): " WALLET
    validate_wallet && { cecho "$GREEN" "[✓] Wallet OK."; break; } || cecho "$RED" "[!] Invalid wallet."
  done
}

prompt_pool() {
  while true; do
    read -rp "Enter pool (host:port), e.g., na.luckpool.net:3956: " POOL
    validate_pool && { cecho "$GREEN" "[✓] Pool OK."; break; } || cecho "$RED" "[!] Invalid pool format."
  done
}

prompt_threads() {
  local max=1
  command -v nproc >/dev/null 2>&1 && max="$(nproc)"
  while true; do
    read -rp "Threads (1-$max, Enter for auto=$max): " t
    if [ -z "$t" ]; then THREADS="$max"; break; fi
    [[ "$t" =~ ^[0-9]+$ ]] && [ "$t" -ge 1 ] && { THREADS="$t"; break; } || cecho "$RED" "Invalid."
  done
}

configure_mode() {
  echo "Select mining mode:"
  echo "  1) Low Power"
  echo "  2) Balanced"
  echo "  3) Boosted"
  echo "  4) Custom"
  read -rp "Choose [1-4]: " m
  case "$m" in
    1) MODE="lowpower" ;;
    2) MODE="balanced" ;;
    3) MODE="boosted" ;;
    4) MODE="custom" ;;
    *) MODE="balanced" ;;
  esac
  cecho "$GREEN" "[✓] Mode: $MODE"
}

configure_profile() {
  echo "Miner profile:"
  echo "  1) cpuminer-verus (default template)"
  echo "  2) custom (enter full template with placeholders)"
  read -rp "Choose [1-2]: " p
  case "$p" in
    1) MINER_PROFILE="cpuminer-verus"; CUSTOM_TEMPLATE="";;
    2) MINER_PROFILE="custom"; read -rp "Enter custom command template: " CUSTOM_TEMPLATE;;
    *) MINER_PROFILE="cpuminer-verus";;
  esac
  cecho "$GREEN" "[✓] Profile: $MINER_PROFILE"
}

configure_settings() {
  prompt_wallet
  prompt_pool
  prompt_threads
  configure_mode
  configure_profile
  save_config
  cecho "$GREEN" "[✓] Configuration saved."
  pause
}

check_script_update() {
  cecho "$CYAN" "[*] Checking for updates..."
  local latest
  latest="$(curl -fsSL "https://raw.githubusercontent.com/$GITHUB_UPDATES_REPO/main/VERSION" 2>/dev/null || true)"
  if [ -z "$latest" ]; then cecho "$YELLOW" "[i] Could not fetch latest version."; return 1; fi
  if [ "$latest" != "$APP_VERSION" ]; then cecho "$GREEN" "[✓] New version available: $latest"; return 0; else cecho "$GREEN" "[✓] Up to date."; return 1; fi
}

update_script() {
  local url="https://raw.githubusercontent.com/$GITHUB_UPDATES_REPO/main/nova_verus_miner.sh"
  cecho "$CYAN" "[*] Updating from $url ..."
  curl -fsSL "$url" -o "$CONFIG_DIR/nova_verus_miner.sh.tmp" || { cecho "$RED" "[!] Download failed."; return 1; }
  mv "$CONFIG_DIR/nova_verus_miner.sh.tmp" "$0"
  chmod +x "$0"
  cecho "$GREEN" "[✓] Script updated. Please restart."
  exit 0
}

select_miner_menu() {
  print_banner
  echo -e "${CYAN}Installed miners:${NC}"
  local list; list="$(miners_list)"
  if [ -z "$list" ]; then echo "None installed."; else echo "$list"; fi
  read -rp "Enter miner filename to activate (or blank to cancel): " sel
  [ -z "$sel" ] && return
  set_active_miner "$sel"
  pause
}

main_menu() {
  while true; do
    print_banner
    echo -e "${CYAN}1) Configure Wallet/Pool/Mode"
    echo -e "2) Install/Select Miner"
    echo -e "3) Start Miner"
    echo -e "4) Stop Miner"
    echo -e "5) Restart Miner"
    echo -e "6) Miner Status"
    echo -e "7) Show Run Info"
    echo -e "8) Start Watchdog"
    echo -e "9) Stop Watchdog"
    echo -e "10) Check for Script Update"
    echo -e "0) Exit${NC}"
    read -rp "Choose: " ch
    case "$ch" in
      1) configure_settings ;;
      2)
         echo "a) Auto-install miners now"
         echo "b) Select active miner"
         read -rp "Choose [a/b]: " s
         case "$s" in
           a) auto_install_miners; pause ;;
           b) select_miner_menu ;;
           *) ;;
         esac
         ;;
      3) start_miner; pause ;;
      4) stop_miner; pause ;;
      5) restart_miner; pause ;;
      6) miner_status; pause ;;
      7) print_banner; [ -f "$RUN_INFO_FILE" ] && cat "$RUN_INFO_FILE" || echo "No run info."; pause ;;
      8) start_watchdog; pause ;;
      9) stop_watchdog; pause ;;
      10) if check_script_update; then update_script; else pause; fi ;;
      0) stop_miner; cecho "$GREEN" "Goodbye!"; exit 0 ;;
      *) cecho "$YELLOW" "Invalid."; pause ;;
    esac
  done
}

# Entry
detect_env
check_deps
load_config
main_menu
