#!/bin/bash
set -e

echo "=== 1. Destruyendo tid-lab ==="
multipass stop tid-lab || true
multipass delete tid-lab || true
multipass purge

echo "=== 2. Creando tid-lab ==="
multipass launch 24.04 --name tid-lab --memory 6G --cpus 2 --disk 44G
IP_VM=$(multipass info tid-lab | grep IPv4 | awk '{print $2}')
echo "IP asignada: $IP_VM"

echo "=== 2.5 Configurando SWAP (4GB) ==="
multipass exec tid-lab -- sudo fallocate -l 4G /swapfile
multipass exec tid-lab -- sudo chmod 600 /swapfile
multipass exec tid-lab -- sudo mkswap /swapfile
multipass exec tid-lab -- sudo swapon /swapfile
multipass exec tid-lab -- bash -c "echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab"

echo "=== 3. Instalando Dependencias ==="
multipass exec tid-lab -- sudo apt-get update
multipass exec tid-lab -- sudo apt-get upgrade -y
multipass exec tid-lab -- sudo apt-get install -y ca-certificates curl git wget gnupg lsb-release iptables jq net-tools python3 python3-pip

echo "=== 4. Instalando Docker ==="
multipass exec tid-lab -- bash -c 'sudo install -m 0755 -d /etc/apt/keyrings && sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && sudo chmod a+r /etc/apt/keyrings/docker.asc'
multipass exec tid-lab -- bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null'
multipass exec tid-lab -- sudo apt-get update
multipass exec tid-lab -- sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
multipass exec tid-lab -- sudo usermod -aG docker ubuntu
multipass exec tid-lab -- sudo systemctl enable docker
multipass exec tid-lab -- sudo systemctl start docker

echo "=== 5. Desplegando Wazuh y Limitando Recursos Docker ==="
multipass exec tid-lab -- sudo sysctl -w vm.max_map_count=262144
multipass exec tid-lab -- bash -c 'echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf'
multipass exec tid-lab -- bash -c 'cd ~ && git clone https://github.com/wazuh/wazuh-docker.git -b v4.8.0'

multipass exec tid-lab -- bash -c "cat << 'EOF' > ~/wazuh-docker/single-node/docker-compose.override.yml
version: '3.7'
services:
  wazuh.indexer:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G
  wazuh.manager:
    deploy:
      resources:
        limits:
          cpus: '0.8'
          memory: 1.5G
  wazuh.dashboard:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
EOF"

multipass exec tid-lab -- bash -c 'cd ~/wazuh-docker/single-node && sudo docker compose -f generate-indexer-certs.yml run --rm generator && sudo docker compose up -d'

echo "=== 6. Wazuh Agent ==="
multipass exec tid-lab -- bash -c 'curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg && sudo chmod 644 /usr/share/keyrings/wazuh.gpg'
multipass exec tid-lab -- bash -c 'echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list'
multipass exec tid-lab -- sudo apt-get update
multipass exec tid-lab -- bash -c 'WAZUH_MANAGER="127.0.0.1" WAZUH_AGENT_NAME="tid-lab-ubuntu" sudo -E apt-get install wazuh-agent=4.8.0-1 -y'
multipass exec tid-lab -- sudo systemctl daemon-reload
multipass exec tid-lab -- sudo systemctl enable wazuh-agent
multipass exec tid-lab -- sudo systemctl start wazuh-agent

echo "=== 7. CrowdSec ==="
multipass exec tid-lab -- bash -c 'curl -s https://install.crowdsec.net | sudo sh && sudo apt-get install crowdsec crowdsec-firewall-bouncer-iptables -y'

# Reconfigurar bouncer para bloquear SOLO port 80 (HTTP), no SSH.
# Esto es CRÍTICO para el lab: permite hacer unban via multipass exec
# incluso con el ban activo, sin necesidad de matar QEMU.
multipass exec tid-lab -- sudo bash -c "
  # Crear cadena custom solo para HTTP
  iptables -N CROWDSEC-HTTP 2>/dev/null || iptables -F CROWDSEC-HTTP
  iptables -D INPUT -p tcp --dport 80 -j CROWDSEC-HTTP 2>/dev/null
  iptables -I INPUT -p tcp --dport 80 -j CROWDSEC-HTTP

  # Redirigir bouncer a la cadena custom (solo port 80, no INPUT completo)
  sed -i 's/^iptables_chains:/iptables_chains_DISABLED:/' /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
  sed -i 's/  - INPUT/  # - INPUT/' /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
  python3 -c \"
with open('/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml','r') as f:
    c = f.read()
c = c.replace('iptables_chains_DISABLED:\n  # - INPUT', 'iptables_chains:\n  - CROWDSEC-HTTP')
with open('/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml','w') as f:
    f.write(c)
\"
  # Deshabilitar persistencia: bans no sobreviven reinicios
  sed -i 's/^disable_iptables_restore:.*/disable_iptables_restore: true/' /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
  systemctl restart crowdsec-firewall-bouncer
"

IP_HOST=$(ip route | grep default | awk '{print $3}')
echo "Configurando whitelist para IP_HOST: $IP_HOST"
multipass exec tid-lab -- bash -c "sudo tee /etc/crowdsec/parsers/s02-enrich/demo-whitelist.yaml > /dev/null << 'EOF'
name: crowdsecurity/demo-whitelist
description: \"Whitelist para IP del host presentador\"
filter: \"evt.Meta.source_ip in ['$IP_HOST']\"
whitelist:
  reason: \"Host del presentador\"
  ip:
    - \"$IP_HOST\"
EOF"
multipass exec tid-lab -- sudo systemctl reload crowdsec

echo "=== 8. NGINX vulnerable ==="
multipass exec tid-lab -- bash -c 'sudo curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg'
multipass exec tid-lab -- bash -c 'echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list'
multipass exec tid-lab -- sudo apt-get update
multipass exec tid-lab -- bash -c 'sudo apt-get install -y nginx=1.29.0-1~noble'
multipass exec tid-lab -- sudo apt-mark hold nginx

multipass exec tid-lab -- bash -c "sudo tee /etc/nginx/conf.d/vulnerable-app.conf > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;
    location /app/ {
        rewrite ^/app/([^/]+)/?(.*)?$ /index.html?path=\$1&sub=\$2 last;
    }
    location /redirect/ {
        rewrite ^/redirect/(.+?)/([^/]*)/?$ /dest/\$1/\$2? permanent;
    }
    location / {
        root /var/www/html;
        index index.html;
    }
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;
}
EOF"

echo "=== Aplicando FIX recursos NGINX ==="
multipass exec tid-lab -- sudo sed -i 's/worker_processes  auto;/worker_processes  1;/g' /etc/nginx/nginx.conf
multipass exec tid-lab -- sudo mkdir -p /etc/systemd/system/nginx.service.d
multipass exec tid-lab -- bash -c "sudo tee /etc/systemd/system/nginx.service.d/limit.conf > /dev/null << 'EOF'
[Service]
CPUQuota=50%
EOF"
multipass exec tid-lab -- sudo systemctl daemon-reload

multipass exec tid-lab -- bash -c "sudo mkdir -p /var/www/html && sudo tee /var/www/html/index.html > /dev/null << 'EOF'
<!DOCTYPE html><html><body><h1>CorpApp Internal Portal</h1><p>Authentication required.</p></body></html>
EOF"
multipass exec tid-lab -- sudo nginx -t
multipass exec tid-lab -- sudo systemctl enable nginx
multipass exec tid-lab -- sudo systemctl restart nginx

echo "=== 9. Usuario Víctima y PoC ==="
multipass exec tid-lab -- bash -c 'sudo adduser --disabled-password --gecos "Demo Victim User" victima'
multipass exec tid-lab -- bash -c 'echo "victima:demo123" | sudo chpasswd'
multipass exec tid-lab -- sudo mkdir -p /opt/pocs
multipass exec tid-lab -- sudo chown ubuntu:ubuntu /opt/pocs

multipass exec tid-lab -- bash -c "cat > /opt/pocs/shadow_reader_demo.py << 'PYEOF'
#!/usr/bin/env python3
import os, subprocess
print('[*] CVE-2026-46333 — ssh-keysign-pwn')
print(f'[*] Running as: {os.getenv(\"USER\")} (uid={os.getuid()})')
result = subprocess.run(['id'], capture_output=True, text=True)
print(f'[*] {result.stdout.strip()}')
print('[!] Triggering ptrace race condition on /usr/lib/openssh/ssh-keysign...')
print('[!] Target files: /etc/shadow + /etc/ssh/ssh_host_*_key')
subprocess.run(['cat', '/etc/shadow'], stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
PYEOF"
multipass exec tid-lab -- chmod +x /opt/pocs/shadow_reader_demo.py
multipass exec tid-lab -- sudo chmod o+rx /opt/pocs

echo "=== 10. Auditd y FIM ==="
multipass exec tid-lab -- sudo apt-get install -y auditd audispd-plugins
multipass exec tid-lab -- bash -c "sudo tee /etc/audit/rules.d/tid-demo.rules > /dev/null << 'EOF'
-w /etc/shadow -p r -k shadow_access
-w /etc/ssh/ssh_host_rsa_key -p r -k ssh_key_access
-w /etc/ssh/ssh_host_ed25519_key -p r -k ssh_key_access
-w /var/log/nginx/error.log -p w -k nginx_error
EOF"
multipass exec tid-lab -- sudo systemctl enable auditd
multipass exec tid-lab -- sudo systemctl start auditd
multipass exec tid-lab -- sudo augenrules --load

multipass exec tid-lab -- bash -c "if ! sudo grep -q 'etc/shadow' /var/ossec/etc/ossec.conf; then
  sudo sed -i '/<syscheck>/a \    <directories realtime=\"yes\" report_changes=\"yes\" check_all=\"yes\">/etc/shadow</directories>\n    <directories realtime=\"yes\" report_changes=\"yes\" check_all=\"yes\">/etc/ssh</directories>' /var/ossec/etc/ossec.conf
fi"
multipass exec tid-lab -- sudo systemctl restart wazuh-agent

echo "=== COMPLETO ==="
