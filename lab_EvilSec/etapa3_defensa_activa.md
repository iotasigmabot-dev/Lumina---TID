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

**Acción:** Editaremos la configuración del Wazuh Manager (que corre en el contenedor Docker) para que asocie la alerta `100010` (lectura de `/etc/shadow`) con la ejecución automática del script `firewall-drop` en el agente de la VM.

```bash
# 1. Definir la ruta del archivo de configuración del Manager
OSSEC_CONF_PATH="/home/ubuntu/wazuh-docker/single-node/config/wazuh_cluster/wazuh_manager.conf"
# Nota: Si el path difiere, buscar dónde se monta el volumen del manager en el docker-compose.

# 2. Verificar si el bloque de active-response ya existe para evitar duplicados
if ! sudo grep -q "<rules_id>100010</rules_id>" "$OSSEC_CONF_PATH" 2>/dev/null; then
  echo "[*] Agregando configuración de Active Response al Manager..."
  
  # Insertar la configuración antes del cierre del bloque </ossec_config>
  sudo sed -i '/<\/ossec_config>/i \
  <active-response>\n    <command>firewall-drop<\/command>\n    <location>local<\/location>\n    <rules_id>100010<\/rules_id>\n    <timeout>60<\/timeout>\n  <\/active-response>' "$OSSEC_CONF_PATH"
  
  echo "[OK] Configuración insertada."
else
  echo "[!] Active Response ya configurada previamente."
fi

# 3. Reiniciar el contenedor de Wazuh Manager para aplicar los cambios
cd /home/ubuntu/wazuh-docker/single-node
docker compose restart wazuh.manager

# Esperar a que el manager inicie completamente (aprox. 30 segundos)
echo "[*] Reiniciando Wazuh Manager... Esperando 30 segundos"
sleep 30
docker compose ps
```

**Checkpoint 3.5:**
- El archivo `wazuh_manager.conf` contiene el bloque `<active-response>` asociado a la regla `100010`.
- El contenedor `wazuh.manager` está en estado `running`.

---

### BLOQUE 3.6 — Ejecutar el PoC e Intento de Escalada de Privilegios (HOST ➔ VM)

**Dónde ejecutar:** Desde el HOST físico (conectando por SSH como usuario `victima`)

**Acción:** Conectarse vía SSH como el usuario sin privilegios y ejecutar el PoC para leer `/etc/shadow`.

```bash
# 1. Conectarse a la VM como victima
ssh victima@10.78.238.104
# (Ingresar contraseña: demo123)

# 2. Una vez dentro de la sesión SSH de victima, ejecutar la simulación de lectura de shadow:
python3 /opt/pocs/shadow_reader_demo.py
cat /etc/shadow
```

> **Qué observar en vivo:** Al ejecutar `cat /etc/shadow`, el comando fallará (o mostrará permiso denegado si no es root), pero el intento de lectura será capturado por `auditd`. En menos de 2 segundos, **tu sesión SSH se congelará por completo y se desconectará** debido a que la IP del Host ha sido bloqueada a nivel firewall.

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

### BLOQUE 3.8 — Resumen Final de la Demo (VM)

**Dónde ejecutar:** Terminal de la VM.

```bash
multipass exec tid-lab -- bash -c "
echo '=== RESUMEN DE DEFENSA ACTIVA TID ==='
echo ''
echo '--- Logs de Detección en Wazuh Manager ---'
sudo docker exec single-node-wazuh.manager-1 \
  tail -n 30 /var/ossec/logs/alerts/alerts.json | grep -E '100010|active_response'
echo ''
echo '--- Estado de Bloqueo Temporal (IPTables) ---'
sudo iptables -L -n | grep -E 'DROP|REJECT'
echo ''
echo '=== DEMO COMPLETADA EXITOSAMENTE ==='
"
```

---

## CRITERIOS DE ÉXITO DE LA ETAPA 3

| Componente | Evento | Acción Esperada | Estado en Dashboard |
|------------|--------|-----------------|---------------------|
| **CrowdSec** | DoS Nginx | IP del host bloqueada en IPTables | Alertas de escenario DoS procesadas |
| **Wazuh AR** | Lectura de `/etc/shadow` | Sesión SSH interrumpida por 60s | Regla 100010 disparada + Alerta AR |
