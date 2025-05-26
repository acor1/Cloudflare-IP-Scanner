#!/bin/bash
set -euo pipefail

# 🎨 Terminal UI colors and icons
BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
PURPLE="\033[1;35m"
RED="\033[1;31m"
RESET="\033[0m"
CHECKMARK="✔"
CROSS="❌"
SPINNER=("|" "/" "-" "\\")

clear
# ✅ ACOR1 logo
echo -e "${CYAN}${BOLD}"
cat <<'EOF'
 █████╗  ██████╗  ██████╗ ██████╗  ██╗
██╔══██╗██╔════╝ ██╔════╝ ██╔══██╗ ██║
███████║██║  ███╗██║  ███╗██████╔╝ ██║
██╔══██║██║   ██║██║   ██║██╔═══╝  ╚═╝
██║  ██║╚██████╔╝╚██████╔╝██║      ██╗
╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝      ╚═╝
   🚀 Cloudflare IP range scanner by acor1 ☄️
EOF
echo -e "${RESET}"
echo
sleep 0.8

# Spinner loading function
loading() {
  local pid=$1 msg=$2
  i=0
  tput civis
  while kill -0 $pid 2>/dev/null; do
    printf "\r${YELLOW}${SPINNER[i++ % ${#SPINNER[@]}]} ${msg}...${RESET}"
    sleep 0.1
  done
  tput cnorm
  printf "\r${GREEN}${CHECKMARK} ${msg} completed.${RESET}\n"
}

# Node.js check
( if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null 2>&1
    sudo apt install -y nodejs >/dev/null 2>&1
  fi ) & loading $! "Checking Node.js"

# npm init + deps
( [ ! -f package.json ] && npm init -y >/dev/null 2>&1
  npm install node-fetch@2 cli-progress p-limit >/dev/null 2>&1 ) & loading $! "Installing Dependencies"

# Embed JS scanner directly
cat > check-ir.js << 'EOF'
const fetch = require('node-fetch');
const fs = require('fs');
const cliProgress = require('cli-progress');
const pLimit = require('p-limit').default;

function ip2dec(ip) {
  const parts = ip.split('.').map(Number);
  return (parts[0] << 24) + (parts[1] << 16) + (parts[2] << 8) + parts[3];
}
function dec2ip(dec) {
  return [(dec >> 24) & 255, (dec >> 16) & 255, (dec >> 8) & 255, dec & 255].join('.');
}
function getFlagEmoji(cc) {
  return cc.toUpperCase().replace(/./g, c => String.fromCodePoint(127397 + c.charCodeAt()));
}
function decodeBase64(b64) {
  return Buffer.from(b64, 'base64').toString('utf8');
}

(async () => {
  const input = process.env.RANGE_INPUT;
  const [startIP, endIP] = input.trim().split('-');
  const start = ip2dec(startIP);
  const end = ip2dec(endIP);
  const total = end - start + 1;

  // GeoIP
  try {
    const geo = await fetch(`http://ip-api.com/json/${startIP}`).then(r => r.json());
    if (geo.status === 'success') {
      const flag = getFlagEmoji(geo.countryCode || '');
      console.log(`\n\u001b[36m🌍 Country detected: ${flag} ${geo.country} (${geo.countryCode})\u001b[0m\n`);
    }
  } catch {}

  const checkHostApi = decodeBase64('aHR0cHM6Ly9jaGVjay1ob3N0Lm5ldA==');
  const nodesUrl = `${checkHostApi}/nodes/hosts`;
  const pingUrl = `${checkHostApi}/check-ping`;
  const resultUrl = `${checkHostApi}/check-result`;

  const irNodes = await fetch(nodesUrl)
    .then(r => r.json())
    .then(d => Object.keys(d.nodes).filter(k => k.startsWith('ir')));
  if (!irNodes.length) return console.error("\u001b[31m❌ No IR Test found\u001b[0m");

  const bar = new cliProgress.SingleBar({
    format: `  🚀 {bar} {percentage}% | {value}/{total} IPs`,
    barCompleteChar: '\u2588',
    barIncompleteChar: '\u2591',
    hideCursor: true
  });
  bar.start(total, 0);

  const reachable = [];
  const limit = pLimit(10);
  const tasks = [];

  for (let i = start; i <= end; i++) {
    const ip = dec2ip(i);
    tasks.push(limit(async () => {
      try {
        const query = irNodes.map(n => `node=${n}`).join('&');
        const res = await fetch(`${pingUrl}?host=${ip}&${query}`, {
          headers: { 'Accept': 'application/json' }
        });
        const data = await res.json();
        const reqId = data.request_id;
        if (!reqId) return;
        await new Promise(r => setTimeout(r, 4000));
        const result = await fetch(`${resultUrl}/${reqId}`, {
          headers: { 'Accept': 'application/json' }
        }).then(r => r.json());
        if (irNodes.every(n => result[n]?.[0]?.every(r => Array.isArray(r) && r[0] === 'OK')))
          reachable.push(ip);
      } catch {}
      bar.increment();
    }));
  }

  await Promise.all(tasks);
  bar.stop();
  reachable.sort((a, b) => ip2dec(a) - ip2dec(b));
  fs.writeFileSync('reachable.txt', reachable.join('\n') + '\n');
  console.log("\n\u001b[1;32m✅ Range Scan complete. Results saved to reachable.txt\u001b[0m");
  console.log("\u001b[35m👤 Developed by acor1\u001b[0m\n");
})();
EOF

# Menu loop
while true; do
  echo -e "\n${CYAN}${BOLD}📋 Main Menu:${RESET}"
  echo -e "${YELLOW}1) Start New IP Range Scan${RESET}"
  echo -e "${YELLOW}2) View reachable.txt${RESET}"
  echo -e "${YELLOW}0) Exit${RESET}"
  printf "${PURPLE}Select an option: ${RESET}"
  read -r option
  case $option in
    1)
      echo -e "\n${GREEN}🚀 Starting scanner...${RESET}\n"
      > reachable.txt
      while true; do
        read -rp $'\033[1;36m📍 Enter Cloudflare range (e.g. 168.100.6.0-168.100.6.255): \033[0m' ip_range
        if [[ $ip_range =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}-([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          RANGE_INPUT="$ip_range" node check-ir.js
          break
        else
          echo -e "${RED}❌ Invalid IP range format. Use format: start-end (e.g. 168.100.6.0-168.100.6.255)${RESET}"
        fi
      done
      ;;
    2)
      echo -e "\n${CYAN}📄 Contents of reachable.txt:${RESET}\n"
      if [ -s reachable.txt ]; then
        cat reachable.txt | nl
      else
        echo -e "${RED}No results yet. Run a scan first.${RESET}"
      fi
      ;;
    0)
      echo -e "${GREEN}👋 Goodbye.${RESET}"
      sleep 0.5
      clear
      exit 0
      ;;
    *)
      echo -e "${RED}❌ Invalid option.${RESET}"
      ;;
  esac
done
