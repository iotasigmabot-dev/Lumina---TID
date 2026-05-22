#!/bin/bash
set -e

echo "=== STARTING WAZUH SETUP ==="

cd ~
if [ ! -d "wazuh-docker" ]; then
  echo "[*] Cloning wazuh-docker repository..."
  git clone https://github.com/wazuh/wazuh-docker.git -b v4.8.0
fi

cd wazuh-docker/single-node

echo "[*] Generating certificates..."
docker compose -f generate-indexer-certs.yml run --rm generator

echo "[*] Launching Wazuh stack..."
docker compose up -d

echo "[*] Waiting for Wazuh Manager to initialize (approx 1-2 minutes)..."
for i in {1..30}; do
  if docker compose logs wazuh.manager 2>&1 | grep -q "Started wazuh-manager"; then
    echo "[+] Wazuh Manager is up!"
    break
  fi
  echo -n "."
  sleep 10
done
echo ""

echo "[*] Installing Wazuh Agent..."
# Import GPG key properly (as root to avoid directory lock/permission error)
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
sudo chmod 644 /usr/share/keyrings/wazuh.gpg

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt-get update

WAZUH_MANAGER="127.0.0.1" WAZUH_AGENT_NAME="tid-lab-ubuntu" sudo -E apt-get install -y wazuh-agent

echo "[*] Starting Wazuh Agent..."
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent

echo "=== WAZUH SETUP COMPLETE ==="
