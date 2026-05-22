# ETAPA 3: Defensa Activa e Interrupción de la Kill Chain (TID)
## Plan para Gemini Flash — Contexto Autocontenido

> **REGLA CARDINAL**: Este plan se ejecuta desde el **HOST físico** (Parrot OS) y la **VM tid-lab**.
> Gemini Flash NO debe ejecutar comandos ofensivos de forma directa; todos los ataques se inician de la forma descripta en cada bloque y se verifica su bloqueo y contención.

---

## CONTEXTO DE ARQUITECTURA DEFENSIVA (ETAPA 3)

En esta etapa, activaremos los mecanismos de prevención activa en tiempo real:

1. **CrowdSec (Perímetro):** Desactivaremos la whitelist para la IP del host y verificaremos que el Bouncer de IPTables bloquea automáticamente al atacante al detectar el ataque DoS.
2. **Wazuh Active Response (Post-Breach):** Configuraremos el Manager de Wazuh para que ordene al Agente bloquear al atacante de inmediato si detecta la lectura no autorizada de `/etc/shadow` (CVE-2026-46333).

```
[HOST FÍSICO — Atacante] ──(Ataque DoS)──> [CrowdSec] ──> ¡BLOQUEO AUTOMÁTICO (IPTables Drop)!
[HOST FÍSICO — SSH session] ──(Lee /etc/shadow)──> [Wazuh Manager] ──> [Active Response] ──> ¡CONEXIÓN CORTADA!
```

---

## PARTE A: BLOQUEO PERIMETRAL (CROWDSEC VS NGINX DOS)

### BLOQUE 3.1 — Desactivar Whitelist en CrowdSec (VM)

**Dónde ejecutar:** Terminal de la VM (`multipass shell tid-lab`)

**Acción:** Comentar o eliminar la whitelist creada en la Etapa 1 para que CrowdSec pueda banear al host.

```bash
# Eliminar el archivo de whitelist
sudo rm -f /etc/crowdsec/parsers/s02-enrich/demo-whitelist.yaml

# Recargar el servicio CrowdSec
sudo systemctl reload crowdsec

# Confirmar que la whitelist ya no aparece en los parsers cargados
sudo cscli parsers list | grep -i whitelist || echo "[OK] Whitelist removida con éxito"
```

**Checkpoint 3.1:**
- CrowdSec recargó correctamente sin errores.
- El parser de whitelist ya no está listado.

---

### BLOQUE 3.2 — Ejecutar el Ataque DoS perimetral (HOST)

**Dónde ejecutar:** Terminal en el HOST físico.

**Acción:** Lanzar nuevamente el script de ataque DoS. Esta vez, el bouncer perimetral de CrowdSec estará atento.

```bash
SCRIPT_PATH="/home/carpeano/Documents/SISTEMAS/NETWORKING/Charla Evilsec/scripts/nginx_dos_demo.sh"

# Ejecutar el ataque
bash "$SCRIPT_PATH"
```

> **Qué observar en vivo:** El ataque comenzará a enviar peticiones, pero a las pocas decenas de solicitudes el script se congelará o empezará a arrojar errores de conexión (`Connection timed out` o `Connection refused`). Esto significa que el bloqueo de red se ha activado.

---

### BLOQUE 3.3 — Verificar Bloqueo en CrowdSec e IPTables (VM)

**Dónde ejecutar:** Terminal de la VM (`multipass shell tid-lab`)

**Acción:** Verificar que CrowdSec tomó la decisión de banear al atacante y que IPTables la está aplicando.

```bash
# 1. Verificar la decisión de baneo en CrowdSec
sudo cscli decisions list

# Esperado: Una línea mostrando la IP del HOST (10.78.238.1 o similar) con la acción "ban"

# 2. Verificar la regla activa en IPTables generada por el Bouncer
sudo iptables -L -n | grep -A 10 "crowdsec"
```

**Checkpoint 3.3:**
- `cscli decisions list` muestra un baneo activo para la IP del host.
- IPTables muestra reglas `DROP` para dicha IP.
- Si intentas hacer `ping` o `curl` desde el HOST hacia la VM, no habrá respuesta.

---

### BLOQUE 3.4 — Desbanear el Host para continuar la demo (VM)

> ⚠️ **CRÍTICO:** Debemos levantar el bloqueo del host para poder continuar con la simulación del Ataque 2.

**Dónde ejecutar:** Terminal de la VM (`multipass shell tid-lab`)

**Acción:** Eliminar manualmente la decisión de bloqueo en CrowdSec.

```bash
# Obtener la IP del host desde las variables de red o usar la IP detectada en cscli decisions list
# Reemplazar <IP-HOST> con el valor real (ej. 10.78.238.1)
IP_HOST="10.78.238.1"

# Eliminar el baneo
sudo cscli decisions delete --ip "$IP_HOST"

# Verificar que la lista de decisiones quedó limpia
sudo cscli decisions list

# Confirmar restauración de conectividad desde el HOST
# En el HOST: curl -I http://10.78.238.104/ (Debería responder HTTP 200 OK nuevamente)
```

---

## PARTE B: RESPUESTA ACTIVA EN HOST (WAZUH ACTIVE RESPONSE VS ESCALADA DE PRIVILEGIOS)

### BLOQUE 3.5 — Configurar Active Response en Wazuh Manager (VM)

**Dónde ejecutar:** Terminal de la VM (`multipass shell tid-lab`)

**Acción:** Configuraremos el Manager de Wazuh (contenedor Docker) para que ejecute una respuesta activa al detectar la alerta 100010 (acceso a `/etc/shadow`). La configuración se hace editando el `ossec.conf` dentro del contenedor via `docker cp`.

> ⚠️ **Por qué `docker cp` y no editar un volumen:** El `ossec.conf` del Manager en el despliegue single-node de Wazuh **no está expuesto como volumen editable** en el host. La forma robusta es copiarlo fuera, editarlo, y devolverlo.

```bash
# 1. Verificar que el script firewall-drop existe en el Agente nativo
sudo ls -lh /var/ossec/active-response/bin/firewall-drop
# Debe existir. Si no: sudo apt-get install --reinstall wazuh-agent
```

```bash
# 2. Crear el script de Active Response personalizado en el Agente
# Extrae la IP remota de la sesión SSH del usuario que disparó la alerta
sudo tee /var/ossec/active-response/bin/ssh-drop.sh > /dev/null << 'EOF'
#!/bin/bash
# Active Response: Bloquear IP remota de sesión SSH activa del usuario comprometido
LOCAL=`dirname $0`
. $LOCAL/ar-lib

ACTION=$1
USER=$2
IP=$3

# Si no viene IP en el evento, obtener la IP remota de las sesiones SSH activas del usuario victima
if [ -z "$IP" ] || [ "$IP" = "-" ]; then
    IP=$(who | grep "victima" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi

if [ -z "$IP" ]; then
    echo "[AR] No se pudo determinar la IP remota. Abortando." >> /var/ossec/logs/active-responses.log
    exit 1
fi

echo "[AR] ssh-drop: Bloqueando IP $IP por acceso a /etc/shadow" >> /var/ossec/logs/active-responses.log

if [ "$ACTION" = "add" ]; then
    /sbin/iptables -I INPUT -s "$IP" -j DROP
    /sbin/iptables -I FORWARD -s "$IP" -j DROP
elif [ "$ACTION" = "delete" ]; then
    /sbin/iptables -D INPUT -s "$IP" -j DROP 2>/dev/null
    /sbin/iptables -D FORWARD -s "$IP" -j DROP 2>/dev/null
fi
EOF
sudo chmod 750 /var/ossec/active-response/bin/ssh-drop.sh
sudo chown root:wazuh /var/ossec/active-response/bin/ssh-drop.sh
```

```bash
# 3. Extraer el ossec.conf del Manager desde el contenedor, agregar el bloque AR y devolverlo
cd ~/wazuh-docker/single-node

# Copiar ossec.conf fuera del contenedor
docker cp single-node-wazuh.manager-1:/var/ossec/etc/ossec.conf /tmp/wazuh_manager_ossec.conf

# Verificar que no exista ya el bloque para la regla 100010 (idempotente)
if ! grep -q "100010" /tmp/wazuh_manager_ossec.conf; then

  # Agregar el comando personalizado y la respuesta activa antes de </ossec_config>
  cat >> /tmp/wazuh_manager_ossec.conf << 'EOF'

  <!-- Active Response: bloqueo SSH por acceso a /etc/shadow -->
  <command>
    <name>ssh-drop</name>
    <executable>ssh-drop.sh</executable>
    <timeout_allowed>yes</timeout_allowed>
  </command>

  <active-response>
    <command>ssh-drop</command>
    <location>local</location>
    <rules_id>100010</rules_id>
    <timeout>60</timeout>
  </active-response>
EOF

  echo "[OK] Bloque AR agregado al ossec.conf del Manager."
else
  echo "[!] El bloque AR ya existe. No se modifica."
fi

# Devolver el archivo modificado al contenedor
docker cp /tmp/wazuh_manager_ossec.conf single-node-wazuh.manager-1:/var/ossec/etc/ossec.conf

# Recargar el Manager sin reiniciar el contenedor (conserva conexiones)
docker exec single-node-wazuh.manager-1 /var/ossec/bin/wazuh-control reload
```

**Checkpoint 3.5:**
```bash
# Verificar que el bloque AR quedó en el ossec.conf del contenedor
docker exec single-node-wazuh.manager-1 grep -A 5 "ssh-drop" /var/ossec/etc/ossec.conf
# Debe mostrar el bloque <active-response> y <command>

# Verificar que el Manager está running
docker compose ps
```

---

### BLOQUE 3.6 — Ejecutar el PoC e Intento de Escalada de Privilegios (HOST ➔ VM)

**Dónde ejecutar:** Desde el HOST físico (conectando por SSH como usuario `victima`)

**Acción:** Conectarse vía SSH como el usuario sin privilegios y ejecutar el PoC para leer `/etc/shadow`.

```bash
# 1. Conectarse a la VM como victima (desde el HOST)
ssh victima@10.78.238.104
# (Ingresar contraseña: demo123)

# 2. Una vez dentro de la sesión SSH de victima, ejecutar el PoC:
python3 /opt/pocs/shadow_reader_demo.py

# 3. Intentar leer /etc/shadow directamente:
cat /etc/shadow
```

> **Comportamiento esperado y por qué importa:**
> - `cat /etc/shadow` devolverá `Permission denied` — **esto es correcto**. El usuario `victima` no tiene privilegios para leer el archivo.
> - Sin embargo, `auditd` registra el intento de acceso al syscall `openat()` **antes** de que el kernel deniegue el permiso. La alerta de Wazuh (Regla 100010) se dispara igualmente.
> - **El punto de la demo:** TID detecta hasta los intentos *fallidos* de acceso a datos críticos. El atacante no necesita tener éxito para ser detectado y bloqueado.
> - En 2-5 segundos, el script `ssh-drop.sh` ejecutará el bloqueo y **la sesión SSH se congelará y desconectará** por completo.

---

### BLOQUE 3.7 — Verificar Bloqueo por Active Response en la VM (VM)

**Dónde ejecutar:** Terminal de la VM (`multipass shell tid-lab` a través de otra consola o sesión de administrador)

**Acción:** Validar que la regla de IPTables generada por Wazuh bloqueó la IP de origen del ataque.

```bash
# 1. Verificar logs de Active Response del agente de Wazuh
sudo tail -n 10 /var/ossec/logs/active-responses.log

# Esperado: Una entrada tipo "firewall-drop add - <IP-HOST>"

# 2. Verificar que la regla se agregó en IPTables
sudo iptables -L -n | grep -E "DROP|REJECT"
```

**Checkpoint 3.7:**
- El archivo `/var/ossec/logs/active-responses.log` contiene el registro del bloqueo en tiempo real.
- El atacante está bloqueado temporalmente (por 60 segundos, según la configuración del Bloque 3.5).

---

### BLOQUE 3.8 — Resumen Final de la Demo

**Dónde ejecutar:** Terminal en el HOST (comandos separados de `multipass exec` — sin bash anidado para evitar problemas de escaping).

```bash
echo "=== RESUMEN DE DEFENSA ACTIVA TID ==="

echo ""
echo "--- Alertas Wazuh: Regla 100010 (Shadow Access) + Active Response ---"
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 \
  python3 -c "
import json
with open('/var/ossec/logs/alerts/alerts.json') as f:
    for line in f:
        try:
            a = json.loads(line)
            rid = a.get('rule', {}).get('id', '')
            if rid in ['100010', '100011'] or 'active_response' in str(a):
                print(a['timestamp'], '| Rule', rid, '|', a['rule'].get('description',''))
        except: pass
" | tail -n 10

echo ""
echo "--- Logs de Active Response en el Agente ---"
multipass exec tid-lab -- sudo tail -n 5 /var/ossec/logs/active-responses.log

echo ""
echo "--- Decisiones CrowdSec activas ---"
multipass exec tid-lab -- sudo cscli decisions list

echo ""
echo "--- IPTables: reglas DROP activas ---"
multipass exec tid-lab -- sudo iptables -L INPUT -n | grep DROP

echo ""
echo "=== DEMO COMPLETADA EXITOSAMENTE ==="
```

---

## CRITERIOS DE ÉXITO DE LA ETAPA 3

| Componente | Evento | Acción Esperada | Estado en Dashboard |
|------------|--------|-----------------|---------------------|
| **CrowdSec** | DoS Nginx | IP del host bloqueada en IPTables | Alertas de escenario DoS procesadas |
| **Wazuh AR** | Lectura de `/etc/shadow` | Sesión SSH interrumpida por 60s | Regla 100010 disparada + Alerta AR |
