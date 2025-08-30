#!/usr/bin/env bash
# install.sh - Installer for Nova All-in-One Verus Miner (Termux & Linux)
# Idempotent: safe to re-run.

set -euo pipefail

echo "[*] Starting installer..."

# Detect Termux vs Linux
TERMUX=0
if command -v termux-info >/dev/null 2>&1 || [[ -n "${PREFIX:-}" && "$PREFIX" == *com.termux* ]]; then
  TERMUX=1
  echo "[*] Detected Termux."
else
  echo "[*] Detected Linux."
fi

if [ "$TERMUX" -eq 1 ]; then
  pkg update -y || true
  pkg upgrade -y || true
  pkg install -y git curl jq bc coreutils proot tar unzip \
    clang make autoconf automake libtool pkg-config cmake \
    openssl libcurl libjansson hwloc termux-api || true
else
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y git curl jq bc coreutils tar unzip \
      build-essential clang autoconf automake libtool pkg-config cmake \
      libssl-dev libcurl4-openssl-dev libjansson-dev libhwloc-dev
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf -y install git curl jq bc coreutils tar unzip \
      @development-tools clang autoconf automake libtool pkgconf-pkg-config cmake \
      openssl-devel libcurl-devel jansson-devel hwloc-devel
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm git curl jq bc coreutils tar unzip \
      base-devel clang autoconf automake libtool pkgconf cmake \
      openssl curl jansson hwloc
  else
    echo "[!] Unsupported package manager. Please install build tools, curl, jq, bc."
  fi
fi

CONFIG_DIR="$HOME/.nova_verus_miner"
MINERS_DIR="$CONFIG_DIR/miners"
LOG_DIR="$CONFIG_DIR/logs"

mkdir -p "$CONFIG_DIR" "$MINERS_DIR" "$LOG_DIR"

CFG="$CONFIG_DIR/config.conf"
if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<'EOF'
# Nova Verus Miner Config
WALLET=""
POOL="na.luckpool.net:3956"
THREADS=0
WORKER=""
MODE="balanced"           # lowpower/balanced/boosted/custom
MINER_PROFILE="cpuminer-verus"  # cpuminer-verus/custom
CUSTOM_TEMPLATE=""
MINER_NAME=""             # set automatically when installed
MINER_PATH=""             # set automatically when installed
EOF
  echo "[*] Wrote default config to $CFG"
fi

echo "[✓] Install complete. Run: ./nova_verus_miner.sh"
