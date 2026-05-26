# ETAPA 2: Ataque con Defensa Activa (Demostración Unificada)
## Charla Evilsec | 26 de Mayo 2026

> **ESTRATEGIA DE DEMOSTRACIÓN:**
> El ataque se lanza **una única vez** usando una **IP virtual rotante** (`ip addr add`) en el HOST.
> La IP de gestión SSH (interfaz nativa de Multipass) **nunca es la misma que la IP atacante**,
> por lo que el ban de CrowdSec **bloquea al "atacante" pero el presentador mantiene acceso SSH**.
> Esto demuestra que el bloqueo perimetral es real y preciso — no un teatro.

---

## ARQUITECTURA DE INTERFACES (CLAVE PARA ENTENDER LA DEMO)

```
HOST FÍSICO (Linux)
│
├── Interfaz mpqemubr0 (bridge Multipass) → IP: 10.78.238.1 (gateway)
│        ↑
│        └── Esta es la IP de GESTIÓN. Desde aquí se hace SSH.
│            CrowdSec tiene whitelist de esta IP. NUNCA se banea.
│
└── IP virtual temporal → ej: 10.78.238.50/24 (añadida a mpqemubr0)
         ↑
         └── Esta es la IP ATACANTE. Se usa SOLO para lanzar el ataque.
             CrowdSec la banea. Al demostrar el ban, se elimina la IP virtual
             y se rota a otra si se necesita atacar de nuevo.

VM: tid-lab
├── IP: 10.78.238.95
├── Puerto 80  → NGINX (vulnerable, superficie de ataque)
├── Puerto 443 → Wazuh Dashboard
└── Puerto 22  → SSH (acceso de gestión del presentador)
```

**El mensaje para la audiencia:** *"El atacante usó una IP diferente a la mía. Fui baneado con éxito. Pero yo, como administrador, mantengo acceso completo desde mi interfaz de gestión."*

---

## PRE-DEMO: Verificaciones y Preparación

### Paso 0.1 — Verificar estado general del lab (HOST)

```bash
# Obtener IP actual de la VM (confirmar que es correcta)
VM_IP=$(multipass info tid-lab | awk '/IPv4/ {print $2}' | head -n 1)
echo "VM IP: $VM_IP"

# Verificar conectividad básica
curl -s -o /dev/null -w "%{http_code}" http://$VM_IP/
# Esperado: 200
```

### Paso 0.2 — Asegurar que el usuario víctima está desbloqueado (HOST)

```bash
# Desbloquear cuenta victima antes de la demo
multipass exec tid-lab -- sudo usermod -U victima

# Confirmar estado: no debe tener '!' en el hash de shadow
multipass exec tid-lab -- sudo grep '^victima:' /etc/shadow | cut -d: -f1-2
# Si el hash empieza con '!', la cuenta estaba bloqueada — usermod -U lo arregla
```

### Paso 0.3 — Confirmar que CrowdSec está activo y sin decisiones previas (HOST)

```bash
# Sin decisiones activas (pizarra limpia para la demo)
multipass exec tid-lab -- sudo cscli decisions list
# Esperado: "No active decisions"

# Si hay decisiones viejas, limpiar:
# multipass exec tid-lab -- sudo cscli decisions delete --all

# Confirmar servicios críticos
multipass exec tid-lab -- systemctl is-active crowdsec crowdsec-firewall-bouncer nginx
# Esperado: active active active
```

### Paso 0.4 — Crear la IP virtual atacante en el HOST

> **POR QUÉ:** Necesitamos que el ataque llegue desde una IP diferente a la de gestión (10.78.238.1).
> CrowdSec baneará esta IP virtual, NO la de gestión.

```bash
# Identificar la interfaz del bridge de Multipass
HOST_IFACE=$(ip route get $VM_IP | grep -oP 'dev \K\S+')
echo "Interfaz: $HOST_IFACE"
# Típicamente: mpqemubr0 o similar

# Añadir IP virtual a la interfaz (la IP atacante — ajustar si .50 ya está en uso)
ATTACK_IP="10.78.238.50"
sudo ip addr add ${ATTACK_IP}/24 dev $HOST_IFACE 2>/dev/null || echo "[!] IP ya existe — ok, continuar"

# Confirmar que la IP atacante puede llegar a la VM
curl --interface $ATTACK_IP -s -o /dev/null -w "%{http_code}" http://$VM_IP/
# Esperado: 200 (aún no está baneada)
```

---

## ATAQUE 1: DoS NGINX + BLOQUEO CROWDSEC (CVE-2026-42945)

### Bloque 2.1 — Lanzar el ataque DoS desde la IP virtual (HOST)

> ⚠️ ESTE ES EL BLOQUE DE ATAQUE. Se lanza el script desde la IP virtual atacante.

```bash
VM_IP=$(multipass info tid-lab | awk '/IPv4/ {print $2}' | head -n 1)
ATTACK_IP="10.78.238.50"

echo "INICIO ATAQUE: $(date)"
echo "IP Atacante: $ATTACK_IP → IP Víctima: $VM_IP"

# Lanzar el ataque usando la IP virtual como interfaz de origen
bash "/home/carpeano/Documents/SISTEMAS/NETWORKING/Charla Evilsec/scripts/nginx_dos_demo.sh"
# El script nginx_dos_demo.sh debe usar: curl --interface $ATTACK_IP ...
# Si el script no usa --interface, ejecutar manualmente:
# for i in $(seq 1 200); do
#   curl --interface $ATTACK_IP -s -o /dev/null "http://$VM_IP/app/test/payload$i/"
# done
```

> **Lo que se verá en vivo:** A los pocos segundos, las requests del script empezarán
> a devolver `Connection refused` o `timeout` — el bouncer de CrowdSec está actuando.

### Bloque 2.2 — Verificar que el ataque fue detectado y bloqueado (VM)

```bash
# Desde otra terminal en el HOST — mantiene acceso por SSH de gestión:
multipass exec tid-lab -- sudo cscli alerts list
# Debe mostrar: Ip:10.78.238.50 | crowdsecurity/http-probing o http-crawl-non_statics | ban:1

multipass exec tid-lab -- sudo cscli decisions list
# Debe mostrar: 10.78.238.50 | ban | 4h
```

### Bloque 2.3 — Demostrar el bloqueo diferenciado (HOST)

```bash
VM_IP=$(multipass info tid-lab | awk '/IPv4/ {print $2}' | head -n 1)
ATTACK_IP="10.78.238.50"

echo "=== DEMOSTRANDO BLOQUEO ==="

echo ""
echo "--- IP ATACANTE ($ATTACK_IP) → Bloqueada ---"
curl --interface $ATTACK_IP --max-time 3 "http://$VM_IP/" 2>&1
# Esperado: curl: (28) Connection timed out o (7) Connection refused

echo ""
echo "--- IP GESTIÓN (default) → Acceso normal ---"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" "http://$VM_IP/"
# Esperado: HTTP Status: 200

echo ""
echo "--- SSH de gestión → Sigue funcionando ---"
multipass exec tid-lab -- echo "SSH: OK - El atacante está baneado, el admin mantiene acceso"
```

> **Para la audiencia:** *"Esto es la defensa perimetral en acción. El atacante fue baneado
> en la red, pero yo como administrador tengo una IP diferente y mantengo control total."*

### Bloque 2.4 — Verificar reglas de iptables generadas por CrowdSec (VM)

```bash
multipass exec tid-lab -- sudo iptables -L -n | grep -A 5 "crowdsec\|CROWDSEC"
# Muestra reglas DROP para 10.78.238.50 insertadas por el bouncer
```

---

## ATAQUE 2: ESCALADA DE PRIVILEGIOS + WAZUH ACTIVE RESPONSE (CVE-2026-46333)

> **CONTEXTO:** El atacante, ya baneado en el perímetro web, intentó un vector diferente:
> comprometer una cuenta interna (`victima`) y leer `/etc/shadow` para obtener hashes de contraseñas.
> Wazuh lo detecta y activa una respuesta automática.

### Bloque 2.5 — Verificar configuración del Active Response (HOST)

```bash
# Confirmar que la regla 100010 está configurada en el Manager
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 \
  grep -A 5 "100010" /var/ossec/etc/ossec.conf
# Debe mostrar el bloque <active-response> ligado a la regla 100010

# Confirmar que el script de AR existe en el agente
multipass exec tid-lab -- sudo ls -lh /var/ossec/active-response/bin/
# Debe mostrar: disable-account o custom-shadow-lock u otro script configurado
```

### Bloque 2.6 — Ejecutar el PoC de escalada de privilegios (HOST ➔ VM)

> ⚠️ ATAQUE 2. Simula que el atacante comprometió la cuenta `victima` y escala privilegios.

```bash
# Opción A: Ejecutar el script de demo del HOST directamente
bash "/home/carpeano/Documents/SISTEMAS/NETWORKING/Charla Evilsec/scripts/privilege_escalation_demo.sh"

# Opción B: Si se quiere demostrar desde SSH como victima:
# ssh victima@$VM_IP  (contraseña: demo123)
# Una vez dentro:
#   python3 /opt/pocs/shadow_reader_demo.py
#   cat /etc/shadow   ← disparará auditd → Wazuh Rule 100010
```

### Bloque 2.7 — Verificar detección y Active Response de Wazuh (HOST)

```bash
# 1. Alerta de Wazuh (Rule 100010 — Shadow Access)
multipass exec tid-lab -- bash -c \
  "sudo docker exec single-node-wazuh.manager-1 grep -a '\"id\":\"100010\"' \
  /var/ossec/logs/alerts/alerts.json | tail -n 1 | jq ."

# 2. Log del Active Response en el agente
multipass exec tid-lab -- sudo tail -n 10 /var/ossec/logs/active-responses.log
# Esperado: Registro de bloqueo (disable-account o ssh-drop ejecutado)

# 3. Confirmar que la cuenta victima fue bloqueada
multipass exec tid-lab -- bash -c "sudo grep '^victima:' /etc/shadow | cut -d: -f1-2"
# Esperado: victima:!$hash...  (el '!' indica cuenta bloqueada)
```

> **Para la audiencia:** *"El SIEM detectó el acceso a /etc/shadow, mapeó la técnica a
> T1003.008 (Credential Dumping), y en segundos ejecutó una respuesta activa automática:
> la cuenta del atacante fue bloqueada. El breakout time defensivo fue menor a 10 segundos."*

---

## POST-DEMO: Restaurar el Entorno

```bash
# 1. Eliminar IP virtual atacante
sudo ip addr del 10.78.238.50/24 dev $HOST_IFACE 2>/dev/null

# 2. Limpiar baneos de CrowdSec
multipass exec tid-lab -- sudo cscli decisions delete --all

# 3. Desbloquear cuenta victima para repetir si es necesario
multipass exec tid-lab -- sudo usermod -U victima

# 4. Confirmar restauración
multipass exec tid-lab -- sudo cscli decisions list
multipass exec tid-lab -- sudo grep '^victima:' /etc/shadow | cut -d: -f1-2
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" "http://$VM_IP/"
```

---

## CRITERIOS DE ÉXITO DE LA ETAPA 2

| Ataque | Evidencia | Estado Esperado |
|--------|-----------|-----------------|
| DoS NGINX | `cscli decisions list` | IP atacante (10.78.238.50) baneada |
| DoS NGINX | `curl --interface $ATTACK_IP` | Connection timeout |
| DoS NGINX | `curl` desde IP gestión | HTTP 200 OK |
| Shadow Access | Wazuh Rule 100010 | Alerta visible en JSON |
| Shadow Access | `active-responses.log` | Script AR ejecutado |
| Shadow Access | `/etc/shadow` | Cuenta `victima` con `!` en hash |

---

## TROUBLESHOOTING DE EMERGENCIA

```bash
# Si CrowdSec bloqueó también la IP de gestión por accidente:
multipass exec tid-lab -- sudo cscli decisions delete --all

# Si la VM no responde (congelada por DoS):
sudo kill -9 $(pgrep -f "qemu-system-x86_64.*tid-lab")
sudo systemctl restart snap.multipass.multipassd

# Si la cuenta victima quedó bloqueada y necesitás repetir:
multipass exec tid-lab -- sudo usermod -U victima

# Reiniciar CrowdSec si hay comportamiento inesperado:
multipass exec tid-lab -- sudo systemctl restart crowdsec
```
