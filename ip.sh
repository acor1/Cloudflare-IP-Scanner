#!/bin/bash
set -euo pipefail


GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
PURPLE="\033[1;35m"
RED="\033[1;31m"
BOLD="\033[1m"
RESET="\033[0m"
CHECKMARK="✔"
CROSS="❌"
SPINNER=("|" "/" "-" "\\")

clear

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


( if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null 2>&1
    sudo apt install -y nodejs >/dev/null 2>&1
  fi ) & loading $! "Checking Node.js"


( [ ! -f package.json ] && npm init -y >/dev/null 2>&1
  npm install node-fetch@2 cli-progress p-limit >/dev/null 2>&1 ) & loading $! "Installing Dependencies"


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
async function getIranNodes() {
  const res = await fetch('https://check-host.net/nodes/hosts');
  const data = await res.json();
  return Object.keys(data.nodes).filter(k => k.startsWith('ir'));
}
async function checkIP(ip, nodes) {
  try {
    const query = nodes.map(n => `node=${n}`).join('&');
    const res = await fetch(`https://check-host.net/check-ping?host=${ip}&${query}`, {
      headers: { 'Accept': 'application/json' }
    });
    const data = await res.json();
    const reqId = data.request_id;
    if (!reqId) return false;
    await new Promise(r => setTimeout(r, 4000));
    const result = await fetch(`https://check-host.net/check-result/${reqId}`, {
      headers: { 'Accept': 'application/json' }
    }).then(r => r.json());
    return nodes.every(n => result[n]?.[0]?.every(r => Array.isArray(r) && r[0] === 'OK'));
  } catch {
    return false;
  }
}

(async () => {
  const input = process.env.RANGE_INPUT;
  const [startIP, endIP] = input.trim().split('-');
  const start = ip2dec(startIP);
  const end = ip2dec(endIP);
  const total = end - start + 1;

  const irNodes = await getIranNodes();
  if (!irNodes.length) return console.error("\u001b[31m❌ No IR nodes found\u001b[0m");

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
      const ok = await checkIP(ip, irNodes);
      if (ok) reachable.push(ip);
      bar.increment();
    }));
  }

  await Promise.all(tasks);
  bar.stop();
  reachable.sort((a, b) => ip2dec(a) - ip2dec(b));
  fs.writeFileSync('reachable.txt', reachable.join('\n') + '\n');
  console.log("\n\u001b[1;32m✅ Scan complete. Results saved to reachable.txt\u001b[0m");
  console.log("\u001b[35m👤 Developed by acor1\u001b[0m\n");
})();
EOF


while true; do
  echo -e "\n${BOLD}${CYAN}📋 Main Menu:${RESET}"
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
        read -rp $'\033[1;36m📍 Enter IP range (e.g. 168.100.6.0-168.100.6.255): \033[0m' ip_range
        if [[ $ip_range =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}-([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          RANGE_INPUT="$ip_range" node check-ir.js
          break
        else
          echo -e "${RED}❌ Invalid IP range format. Use format: start-end (e.g. 192.168.1.1-192.168.1.255)${RESET}"
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

