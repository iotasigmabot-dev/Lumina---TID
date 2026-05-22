#!/bin/bash
set -e

echo "=== STARTING BASE LAB SETUP ==="

# 1. Update and install base packages
echo "[*] Updating system and installing base packages..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y \
  ca-certificates curl git wget gnupg lsb-release \
  iptables jq net-tools python3 python3-pip auditd audispd-plugins

# 2. Install Docker
echo "[*] Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Configure Docker permissions
sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker

# 3. Configure vm.max_map_count
echo "[*] Configuring vm.max_map_count for Elasticsearch/OpenSearch..."
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

echo "=== BASE SETUP COMPLETE ==="
