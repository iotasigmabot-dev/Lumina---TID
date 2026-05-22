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
  --memory 4G \
  --cpus 2 \
  --disk 20G
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
sudo -E apt-get install wazuh-agent -y
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

## BLOQUE 6 — Configurar Whitelist del Host en CrowdSec (VM)

**Dónde ejecutar:** Dentro de `multipass shell tid-lab`

> CRITICO: Sin este paso, CrowdSec bloqueará la IP del HOST durante la demo.

### 6A — Obtener IP del Host

```bash
ip route | grep default
# Resultado: "default via 192.168.64.1 dev ens3"
# La IP del HOST es 192.168.64.1
```

> ANOTAR: `<IP-HOST>` = el valor que aparece después de "via"

### 6B — Crear whitelist

> Reemplazar `192.168.64.1` con la IP real antes de ejecutar.

```bash
sudo tee /etc/crowdsec/parsers/s02-enrich/demo-whitelist.yaml > /dev/null << 'EOF'
name: crowdsecurity/demo-whitelist
description: "Whitelist para IP del host presentador — Demo Evilsec"
filter: "evt.Meta.source_ip in ['192.168.64.1']"
whitelist:
  reason: "Host del presentador"
  ip:
    - "192.168.64.1"
EOF

sudo systemctl reload crowdsec
```

**Checkpoint 6:**
```bash
sudo cscli parsers list | grep whitelist
# Debe aparecer: crowdsecurity/demo-whitelist
```

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

### 7D — Página ficticia y arranque

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
