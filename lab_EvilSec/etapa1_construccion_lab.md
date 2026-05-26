# ETAPA 1 — Plan de Construcción del Laboratorio TID
## Charla Evilsec | 26 de Mayo 2026

> **INSTRUCCIONES PARA GEMINI FLASH:**
> Este plan está dividido en **9 bloques atómicos**. Cada bloque es independiente y auto-contenido.
> - Ejecuta **UN BLOQUE A LA VEZ**.
> - Al terminar cada bloque, verifica el checkpoint antes de continuar.
> - Si un comando falla, NO improvises. Reporta el error exacto y detente.
> - Variables importantes están marcadas con `<MAYUSCULAS>`. Reemplazalas con los valores reales.

---

## CONTEXTO DEL LABORATORIO

### Stack tecnológico

| Componente | Versión / Tipo | Rol |
|------------|---------------|-----|
| Multipass | Instalado en el HOST | Gestión de la VM |
| Docker Engine | Oficial (GPG method) | Runtime para Wazuh |
| Wazuh Stack | Single-Node Docker | SIEM + Detección |
| Wazuh Agent | Nativo Ubuntu | Monitoreo de la VM |
| CrowdSec | Última estable | Prevención perimetral |
| cs-firewall-bouncer | IPTables | Ejecutor de bloqueos |
| **NGINX 1.29.x** | **Vulnerable CVE-2026-42945** | **Superficie de ataque (INTENCIONAL)** |
| Usuario `victima` | sin privilegios | Superficie para CVE-2026-46333 |

### Arquitectura de red

```
[HOST FÍSICO — atacante]
    IP: 192.168.64.1 (gateway Multipass)

          ↕ Red Multipass (192.168.64.0/24)

[VM: tid-lab — Ubuntu 24.04]
    IP: 192.168.64.X  ← obtener con: multipass info tid-lab
    Puerto 443  → Wazuh Dashboard (HTTPS)
    Puerto 80   → NGINX (HTTP vulnerable)
    Puerto 22   → SSH
    Puerto 1514 → Wazuh Agent
```

### CVEs implementadas intencionalmente

| CVE | Componente | Tipo | Activación |
|-----|-----------|------|-----------|
| **CVE-2026-42945** | NGINX 1.29.x | Heap buffer overflow (DoS) | Bloque rewrite con regex unnamed groups + `?` |
| **CVE-2026-46333** | Kernel Ubuntu 24.04 sin parchear | Race condition (info disclosure) | PoC Qualys desde usuario `victima` |

---

## 🚀 MÉTODO AUTOMATIZADO (RECOMENDADO)

Para centralizar el manejo y evitar saturar la memoria (OOM), aquí tienes el script completo y unificado. Este script destruye la VM actual, crea una nueva con **6GB de RAM** y **4GB de SWAP**, y aplica límites estrictos a los contenedores Docker de Wazuh.

Guarda el siguiente bloque de código en un archivo llamado `rebuild_tid_lab.sh` y ejecútalo con `bash rebuild_tid_lab.sh`:

```bash
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

IP_HOST=\$(ip route | grep default | awk '{print \$3}')
echo "Configurando whitelist para IP_HOST: \$IP_HOST"
multipass exec tid-lab -- bash -c "sudo tee /etc/crowdsec/parsers/s02-enrich/demo-whitelist.yaml > /dev/null << 'EOF'
name: crowdsecurity/demo-whitelist
description: \"Whitelist para IP del host presentador\"
filter: \"evt.Meta.source_ip in ['\$IP_HOST']\"
whitelist:
  reason: \"Host del presentador\"
  ip:
    - \"\$IP_HOST\"
EOF"
multipass exec tid-lab -- sudo systemctl reload crowdsec

echo "=== 8. NGINX vulnerable ==="
multipass exec tid-lab -- bash -c 'sudo curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg'
multipass exec tid-lab -- bash -c 'echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/ubuntu \$(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list'
multipass exec tid-lab -- sudo apt-get update
multipass exec tid-lab -- bash -c 'sudo apt-get install -y nginx=1.29.0-1~noble'
multipass exec tid-lab -- sudo apt-mark hold nginx

multipass exec tid-lab -- bash -c "sudo tee /etc/nginx/conf.d/vulnerable-app.conf > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;
    location /app/ {
        rewrite ^/app/([^/]+)/?(.*)?\$ /index.html?path=\$1&sub=\$2 last;
    }
    location /redirect/ {
        rewrite ^/redirect/(.+?)/([^/]*)/?\$ /dest/\$1/\$2? permanent;
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
```

---

## BLOQUE 0 — Verificación Pre-Construcción (HOST)

**Dónde ejecutar:** Terminal en el HOST

```bash
multipass version
multipass list
# Si existe tid-lab anterior:
# multipass stop tid-lab && multipass delete tid-lab && multipass purge
```

**Checkpoint 0:**
- `multipass version` devuelve versión válida
- `multipass list` no muestra `tid-lab`

---

## BLOQUE 1 — Crear la VM (HOST)

**Dónde ejecutar:** Terminal en el HOST

```bash
multipass launch 24.04 \
  --name tid-lab \
  --memory 6G \
  --cpus 2 \
  --disk 44G
```

> Tiempo estimado: 3-7 minutos

```bash
# GUARDAR ESTE VALOR — se usa en todos los bloques siguientes
multipass info tid-lab | grep IPv4

# Entrar a la VM
multipass shell tid-lab
```

**Checkpoint 1:**
- `multipass info tid-lab` muestra `State: Running`
- IPv4 devuelve IP del rango `192.168.64.x`

---

## BLOQUE 1.5 — Configurar SWAP (VM)

**Dónde ejecutar:** Dentro de `multipass shell tid-lab` (o usando `multipass exec`)

> ⚠️ **CRÍTICO:** Wazuh, CrowdSec y Docker consumen una cantidad de memoria considerable que supera fácilmente los 4GB de RAM de la VM. Configurar un archivo swap de 4GB es indispensable para prevenir bloqueos de CPU y kernel panic por falta de memoria (OOM).

```bash
# Crear un archivo de swap de 4GB
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Hacerlo persistente tras reinicios
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

**Checkpoint 1.5:**
- `free -h` muestra la sección `Swap` con un total de `4.0Gi` (o similar).

---

## BLOQUE 2 — Instalar Dependencias Base (VM)

**Dónde ejecutar:** Dentro de `multipass shell tid-lab`

### 2A — Actualizar sistema y paquetes base

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y \
  ca-certificates curl git wget gnupg lsb-release \
  iptables jq net-tools python3 python3-pip
```

### 2B — Instalar Docker Engine (método GPG oficial)

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### 2C — Configurar Docker sin sudo

```bash
sudo usermod -aG docker $USER
sudo systemctl enable docker && sudo systemctl start docker
```

> ⚠️ **IMPORTANTE:** Para que el grupo `docker` tome efecto hay que salir y volver a entrar a la VM. NO usar `newgrp docker` — abre una sub-shell y rompe el contexto de los bloques siguientes.

```bash
exit
# En el HOST:
multipass shell tid-lab
```

**Checkpoint 2:**
```bash
docker --version        # Docker 26.x.x o superior
docker compose version  # Docker Compose 2.x.x
docker run hello-world  # "Hello from Docker!"
```

---

## BLOQUE 3 — Desplegar Wazuh Stack (VM)

**Dónde ejecutar:** Dentro de `multipass shell tid-lab`

### 3A — Fix de memoria para OpenSearch

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### 3B — Clonar y desplegar

```bash
cd ~
git clone https://github.com/wazuh/wazuh-docker.git -b v4.8.0
cd wazuh-docker/single-node

# Generar certificados SSL
docker compose -f generate-indexer-certs.yml run --rm generator

# Levantar el stack (5-10 minutos)
docker compose up -d
```

### 3C — Monitorear arranque

```bash
docker compose ps
docker compose logs -f wazuh.manager
# Esperar "Started wazuh-manager" → Ctrl+C para salir
```

**Checkpoint 3:**
```bash
docker compose ps
# Los 3 contenedores en estado "running":
# single-node-wazuh.manager-1
# single-node-wazuh.indexer-1
# single-node-wazuh.dashboard-1
```

Desde el HOST → `https://<IP-VM>` → Login: `admin` / `SecretPassword` → Dashboard debe cargar.

---

## BLOQUE 4 — Instalar Agente Wazuh (VM)

**Dónde ejecutar:** Dentro de `multipass shell tid-lab`

### 4A — Agregar repositorio oficial

> Método `--dearmor` — más robusto en Ubuntu 24.04 que `--no-default-keyring`.

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | \
  sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
sudo chmod 644 /usr/share/keyrings/wazuh.gpg

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
  https://packages.wazuh.com/4.x/apt/ stable main" | \
  sudo tee /etc/apt/sources.list.d/wazuh.list

sudo apt-get update
```

### 4B — Instalar agente apuntando al Manager local

```bash
WAZUH_MANAGER="127.0.0.1" \
WAZUH_AGENT_NAME="tid-lab-ubuntu" \
sudo -E apt-get install wazuh-agent=4.8.0-1 -y
```

### 4C — Iniciar servicio

```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

**Checkpoint 4:**
```bash
sudo systemctl status wazuh-agent
# Active: active (running)
```

Dashboard Wazuh → **Server Management → Endpoints Summary** → `tid-lab-ubuntu` en estado **Active** (verde).

---

## BLOQUE 5 — Instalar CrowdSec + Bouncer (VM)

**Dónde ejecutar:** Dentro de `multipass shell tid-lab`

```bash
# Instalar CrowdSec
curl -s https://install.crowdsec.net | sudo sh
sudo apt-get install crowdsec -y

# Instalar Bouncer IPTables
sudo apt-get install crowdsec-firewall-bouncer-iptables -y

# Verificar colecciones
sudo cscli collections list
```

**Checkpoint 5:**
```bash
sudo systemctl status crowdsec                   # active (running)
sudo systemctl status crowdsec-firewall-bouncer  # active (running)
sudo cscli metrics                               # parseo activo de auth.log
```

---

## BLOQUE 6 — Estrategia de IP para la Demo (CAMBIO DE ESTRATEGIA)

> ⚠️ **ESTRATEGIA ACTUALIZADA:** La whitelist de host ya **no es necesaria** para la demo.
> En lugar de eso, la Etapa 2 usa una **IP virtual atacante** (`ip addr add`) que es diferente
> a la IP de gestión nativa del HOST. CrowdSec baneará solo la IP del ataque, nunca la de gestión.
>
> **Ventaja:** El bloqueo es 100% real y demostrable — no hay nada en lista blanca.
> La audiencia ve un ban auténtico mientras el presentador mantiene acceso SSH intacto.

**No se requiere ejecutar ningún comando en este bloque.**

La IP virtual atacante se crea en el momento de la demo (Etapa 2, Paso 0.4) con:
```bash
ATTACK_IP="10.78.238.50"
HOST_IFACE=$(ip route get $VM_IP | grep -oP 'dev \K\S+')
sudo ip addr add ${ATTACK_IP}/24 dev $HOST_IFACE
```

Y se elimina al finalizar la demo:
```bash
sudo ip addr del ${ATTACK_IP}/24 dev $HOST_IFACE
```

**Checkpoint 6:** No aplica. Continuar con Bloque 7.

---

## BLOQUE 7 — Instalar NGINX 1.29.x Vulnerable (CVE-2026-42945) (VM)

**Dónde ejecutar:** Dentro de `multipass shell tid-lab`

### 7A — Agregar repositorio oficial Nginx mainline

```bash
sudo curl -fsSL https://nginx.org/keys/nginx_signing.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
  http://nginx.org/packages/mainline/ubuntu \
  $(lsb_release -cs) nginx" | \
  sudo tee /etc/apt/sources.list.d/nginx.list

sudo apt-get update
```

### 7B — Instalar versión vulnerable y bloquear actualizaciones

```bash
# Ver versiones disponibles y copiar el string exacto de la columna 3
apt-cache madison nginx | head -5
```

> ⚠️ El wildcard `nginx=1.29.*` no siempre funciona en apt. Usar la versión exacta del output anterior.

```bash
# Ejemplo: si apt-cache madison muestra "1.29.0-1~noble"
# Reemplazar <VERSION_EXACTA> con el valor real
sudo apt-get install -y nginx=<VERSION_EXACTA>
sudo apt-mark hold nginx
```

### 7C — Configurar bloque vulnerable (CVE-2026-42945)

```bash
sudo tee /etc/nginx/conf.d/vulnerable-app.conf > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;

    # VULNERABLE — CVE-2026-42945
    # Unnamed capture groups ($1, $2) con modificador ? en regex
    location /app/ {
        rewrite ^/app/([^/]+)/?(.*)?$ /index.html?path=$1&sub=$2 last;
    }

    location /redirect/ {
        rewrite ^/redirect/(.+?)/([^/]*)/?$ /dest/$1/$2? permanent;
    }

    location / {
        root /var/www/html;
        index index.html;
    }

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;
}
EOF
```

### 7D — Limitar recursos de NGINX (Prevenir congelamiento de la VM)

> ⚠️ **CRÍTICO:** Como el ataque explota un consumo de CPU infinito (catastrophic backtracking), debemos limitar a NGINX para que no congele el resto de los servicios de la VM (Wazuh, SSH, Multipass) durante el DoS.

```bash
# 1. Forzar a NGINX a usar solo 1 CPU (worker_processes 1 en lugar de auto)
sudo sed -i 's/worker_processes  auto;/worker_processes  1;/g' /etc/nginx/nginx.conf

# 2. Establecer una cuota máxima de CPU del 50% vía SystemD
sudo mkdir -p /etc/systemd/system/nginx.service.d
sudo tee /etc/systemd/system/nginx.service.d/limit.conf > /dev/null << 'EOF'
[Service]
CPUQuota=50%
EOF
sudo systemctl daemon-reload
```

### 7E — Página ficticia y arranque

```bash
sudo tee /var/www/html/index.html > /dev/null << 'EOF'
<!DOCTYPE html><html><body>
<h1>CorpApp Internal Portal</h1>
<p>Authentication required.</p>
</body></html>
EOF

sudo nginx -t          # Verificar sintaxis
sudo systemctl enable nginx
sudo systemctl start nginx
```

**Checkpoint 7:**
```bash
nginx -v
# nginx version: nginx/1.29.x

sudo systemctl status nginx
# active (running)

# Desde el HOST:
curl -I http://<IP-VM>/
# HTTP/1.1 200 OK | Server: nginx/1.29.x
```

---

## BLOQUE 8 — Crear Usuario Víctima (CVE-2026-46333) (VM)

**Dónde ejecutar:** Dentro de `multipass shell tid-lab`

### 8A — Crear usuario sin privilegios

```bash
sudo adduser --disabled-password --gecos "Demo Victim User" victima
echo "victima:demo123" | sudo chpasswd
```

### 8B — Verificar que NO tiene sudo

```bash
sudo -l -U victima
# User victima is not allowed to run sudo on tid-lab
```

### 8C — Preparar directorio de PoCs

```bash
sudo mkdir -p /opt/pocs
sudo chown ubuntu:ubuntu /opt/pocs
cd /opt/pocs

# Intentar clonar PoC oficial de Qualys
git clone https://github.com/qualys/ssh-keysign-pwn.git 2>/dev/null && \
  echo "PoC oficial disponible" || \
  echo "PoC oficial no disponible — usar script fallback"

# Script de demostración (fallback si el repo oficial no está)
cat > /opt/pocs/shadow_reader_demo.py << 'PYEOF'
#!/usr/bin/env python3
"""
Demo CVE-2026-46333 (ssh-keysign-pwn) — Race condition PoC simulation
"""
import os, subprocess

print("[*] CVE-2026-46333 — ssh-keysign-pwn")
print(f"[*] Running as: {os.getenv('USER')} (uid={os.getuid()})")
result = subprocess.run(['id'], capture_output=True, text=True)
print(f"[*] {result.stdout.strip()}")
print("[!] Triggering ptrace race condition on /usr/lib/openssh/ssh-keysign...")
print("[!] Target files: /etc/shadow + /etc/ssh/ssh_host_*_key")
PYEOF
chmod +x /opt/pocs/shadow_reader_demo.py
sudo chmod o+rx /opt/pocs
```

**Checkpoint 8:**
```bash
id victima
# uid=1001(victima) gid=1001(victima) groups=1001(victima)

ls -la /opt/pocs/
# Muestra al menos shadow_reader_demo.py

su - victima -c "id && echo OK"
# uid=1001(victima)...  OK
```

---

## BLOQUE 9 — Configurar FIM en Wazuh (VM)

**Dónde ejecutar:** Dentro de `multipass shell tid-lab`

**Objetivo:** Wazuh detecta acceso a `/etc/shadow` y `/etc/ssh/*key` (CVE-2026-46333) + crash de NGINX (CVE-2026-42945).

### 9A — Instalar auditd y configurar reglas de auditoría

```bash
sudo apt-get install -y auditd audispd-plugins

sudo tee /etc/audit/rules.d/tid-demo.rules > /dev/null << 'EOF'
# CVE-2026-46333 — Acceso a /etc/shadow
-w /etc/shadow -p r -k shadow_access
# CVE-2026-46333 — Acceso a SSH private keys
-w /etc/ssh/ssh_host_rsa_key -p r -k ssh_key_access
-w /etc/ssh/ssh_host_ed25519_key -p r -k ssh_key_access
# NGINX — Cambios en error log (crash indicator)
-w /var/log/nginx/error.log -p w -k nginx_error
EOF

sudo systemctl enable auditd
sudo systemctl start auditd
sudo augenrules --load
```

### 9B — Configurar FIM en el agente Wazuh

> ⚠️ Usar `tee -a` (append) en `ossec.conf` genera XML inválido si se ejecuta más de una vez, lo que rompe el agente silenciosamente. Se verifica primero si ya existe el bloque antes de agregarlo.

```bash
# Solo agregar si el bloque no existe ya
if ! sudo grep -q "etc/shadow" /var/ossec/etc/ossec.conf; then
  sudo tee -a /var/ossec/etc/ossec.conf > /dev/null << 'EOF'
<ossec_config>
  <syscheck>
    <directories realtime="yes" report_changes="yes" check_all="yes">/etc/shadow</directories>
    <directories realtime="yes" report_changes="yes" check_all="yes">/etc/ssh</directories>
  </syscheck>
</ossec_config>
EOF
  echo "[+] Bloque syscheck agregado"
else
  echo "[!] Bloque syscheck ya existe — no se modifica"
fi

sudo systemctl restart wazuh-agent
sleep 15
sudo systemctl status wazuh-agent
```

**Checkpoint 9:**
```bash
# Reglas de audit cargadas
sudo auditctl -l | grep -E "shadow|ssh_key|nginx"
# Debe mostrar 4 reglas

# Test: generar evento de acceso a shadow
sudo cat /etc/shadow > /dev/null 2>&1
sleep 5
sudo ausearch -k shadow_access | tail -3
# Debe mostrar registro de acceso

# En Wazuh Dashboard → Security Events → buscar "shadow"
# Debe aparecer alerta de FIM
```

---

## VERIFICACIÓN FINAL — Ejecutar al Terminar los 9 Bloques

```bash
echo "=== VERIFICACION FINAL — LABORATORIO TID ==="

echo ""
echo "--- Docker: Wazuh Stack ---"
cd ~/wazuh-docker/single-node && docker compose ps

echo ""
echo "--- Servicios Nativos ---"
for svc in wazuh-agent crowdsec crowdsec-firewall-bouncer nginx auditd; do
    status=$(systemctl is-active $svc)
    echo "  $svc: $status"
done

echo ""
echo "--- NGINX Version (debe ser 1.29.x) ---"
nginx -v 2>&1

echo ""
echo "--- Usuario victima ---"
id victima 2>/dev/null || echo "ERROR: usuario victima no existe"

echo ""
echo "--- CrowdSec Whitelist ---"
sudo cscli parsers list | grep -i whitelist

echo ""
echo "--- Reglas Audit ---"
sudo auditctl -l | grep -E "shadow|ssh_key"

echo ""
echo "--- IP de la VM ---"
hostname -I

echo ""
echo "=== FIN VERIFICACION ==="
```

**Resultado esperado:**
```
Docker containers: 3/3 running (Up)
wazuh-agent: active
crowdsec: active
crowdsec-firewall-bouncer: active
nginx: active
auditd: active
nginx version: nginx/1.29.x
victima: uid=1001(victima) ...
whitelist: crowdsecurity/demo-whitelist
audit rules: 4 reglas
```

---

## NOTAS DE TROUBLESHOOTING PARA GEMINI FLASH

| Error | Causa probable | Solución |
|-------|---------------|---------|
| Wazuh containers no arrancan | `vm.max_map_count` incorrecto | Re-ejecutar Bloque 3A y reiniciar docker compose |
| Agente Wazuh no aparece en dashboard | Tiempo de registro | Esperar 3 min, luego `journalctl -u wazuh-agent -n 30` |
| NGINX 1.29.x no disponible | Repositorio actualizado | Reportar versión disponible más cercana |
| PoC Qualys no disponible | Repo privado/eliminado | Usar `/opt/pocs/shadow_reader_demo.py` como fallback |
| CrowdSec bloquea inesperadamente | Whitelist no aplicada | `sudo cscli decisions delete --all` y verificar whitelist |
| `newgrp docker` no funciona | Sesión no reiniciada | Salir de la VM y volver a entrar: `exit` → `multipass shell tid-lab` |
