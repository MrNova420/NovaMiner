# NovaMiner
All one one automated advanced versus coin miner with multiple different miner and pools and also custom pool and ect can be used ,


# Nova All-in-One Verus Miner (Termux & Linux)

A fully integrated, advanced, automated Verus miner for Termux (Android) and Linux. Merged and refined from your prior projects (Novas-Auto-Verus-Miner, NovaVerusMiner, projectNM, automated-termux-mining, verus-mining-termux) into one production-ready suite.

Highlights
- Zero-interaction first run: auto-detect arch, auto-install miner (build from source or fetch from releases), set up config
- Interactive wizard for wallet/pool/mode (first run)
- Multi-miner capable via command templates (cpuminer-verus style default)
- Watchdog: auto-restart; Termux battery/thermal awareness; notifications via termux-api
- Persistent config, logs, run snapshot under ~/.nova_verus_miner
- Auto-update script hook

What’s new in this merge
- Removed manual URL prompts. The system auto-builds cpuminer-verus or auto-downloads from your repos (NovaVerusMiner, Novas-Auto-Verus-Miner) using standardized asset names.
- Standardized asset naming that the script expects (recommended):
  - cpuminer-verus-arm64, cpuminer-verus-armv7, cpuminer-verus-x86_64, cpuminer-verus-x86
  - verus-miner-arm64, verus-miner-armv7, verus-miner-x86_64, verus-miner-x86
- Robust fallback order: Build → Your Releases → Error

Requirements
- Termux (Android 7+) or Linux
- Internet access
- Termux users: termux-api app recommended for notifications and battery/thermal checks
- Build deps (installer handles these)

Quick Start (Termux)
1) Install Termux (and “Termux:API” app for notifications)
2) Run:
   pkg update -y && pkg upgrade -y
   pkg install -y git
   git clone https://github.com/YOUR_USERNAME/Nova-All-In-One-Verus-Miner.git
   cd Nova-All-In-One-Verus-Miner
   chmod +x install.sh nova_verus_miner.sh
   ./install.sh
3) Launch:
   ./nova_verus_miner.sh
   - Follow the wizard to enter your wallet and pool once
   - Start mining

Quick Start (Linux)
1) Run:
   sudo apt update && sudo apt install -y git
   git clone https://github.com/YOUR_USERNAME/Nova-All-In-One-Verus-Miner.git
   cd Nova-All-In-One-Verus-Miner
   chmod +x install.sh nova_verus_miner.sh
   ./install.sh
2) Launch:
   ./nova_verus_miner.sh

Miner Profiles
- cpuminer-verus (default template)
- custom (define your own command template with placeholders)
Placeholders: {WALLET} {POOL} {THREADS} {WORKER}
Default template:
  -a verus -o stratum+tcp://{POOL} -u {WALLET}.{WORKER} -p x -t {THREADS}

Watchdog
- Ensures miner stays alive, restarts when needed
- On Termux: pauses on low battery and can read thermal sensors (best-effort)
- Uses termux-notification if available

Files and Folders
- ~/.nova_verus_miner/config.conf
- ~/.nova_verus_miner/miners/ (installed miner binaries)
- ~/.nova_verus_miner/logs/ (miner.log, watchdog.log)
- ~/.nova_verus_miner/run.info
- ~/.nova_verus_miner/active_miner

Auto Update
- Script checks YOUR_USERNAME/Nova-All-In-One-Verus-Miner for VERSION
- Update target can be adjusted in nova_verus_miner.sh

Recommended release assets (for your repos)
- Upload prebuilt miners to NovaVerusMiner or Novas-Auto-Verus-Miner with names like:
  - cpuminer-verus-arm64, cpuminer-verus-armv7, cpuminer-verus-x86_64, cpuminer-verus-x86
  - verus-miner-arm64, verus-miner-armv7, verus-miner-x86_64, verus-miner-x86

License
MIT © 2025 MrNova420
