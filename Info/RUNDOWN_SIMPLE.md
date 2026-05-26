=========================================
      EVILSEC TID LAB - RUNDOWN
=========================================
ver IP atacante:
ip -br addr show mpqemubr0

-----------------------------------------
[ PRE-FLIGHT: VERIFICACION COMPLETA ]
-----------------------------------------
Correr todo este bloque de una vez. Cada línea debe devolver `OK` / `200` / `active`.

```bash
# 0. Variables dinámicas (base de todo el pre-flight):
VM_IP=$(multipass info tid-lab | awk '/IPv4/ {print $2}' | head -n 1)
HOST_IFACE=$(ip route get "$VM_IP" | grep -oP 'dev \K\S+')
BASE_IP=$(echo "$VM_IP" | cut -d. -f1-3)

# 1. IP atacante — detectar la actual o asignar la siguiente libre (.50→.99):
EXISTING=$(ip addr show "$HOST_IFACE" | grep "inet ${BASE_IP}" \
  | awk '{print $2}' | cut -d/ -f1 | grep -v "^${BASE_IP}\.1$" | head -1)
if [ -n "$EXISTING" ]; then
  ATTACK_IP="$EXISTING"
  echo "IP atacante activa: $ATTACK_IP"
else
  for oct in $(seq 50 99); do
    candidate="${BASE_IP}.${oct}"
    if ! ip addr show "$HOST_IFACE" | grep -q "$candidate"; then
      sudo ip addr add "${candidate}/24" dev "$HOST_IFACE"
      ATTACK_IP="$candidate"; break
    fi
  done
  echo "IP atacante asignada: $ATTACK_IP"
fi
```
> **Rotar (si está baneada)**: 
> ```bash
> sudo ip addr del ${ATTACK_IP}/24 dev $HOST_IFACE
> ```
> → volver a correr el bloque anterior para asignar la siguiente libre

```bash
# 2. VM corriendo:
multipass info tid-lab | grep State
# Esperado: State: Running

# 3. Servicios críticos (todos deben decir "active"):
for svc in nginx crowdsec crowdsec-firewall-bouncer wazuh-agent auditd; do
  echo "$svc: $(multipass exec tid-lab -- systemctl is-active $svc 2>/dev/null)"
done

# 4. Wazuh containers (3/3 Up):
multipass exec tid-lab -- sudo docker ps --format "{{.Names}}: {{.Status}}" 2>/dev/null

# 5. NGINX responde HTTP 200:
curl -s -o /dev/null -w "NGINX: %{http_code}\n" --max-time 3 http://$VM_IP/

# 6. CrowdSec pizarra limpia:
multipass exec tid-lab -- sudo cscli decisions list
# Esperado: No active decisions

# 7. Auditd — reglas shadow y ssh_key activas:
multipass exec tid-lab -- sudo auditctl -l | grep -E "shadow|ssh_key"
# Esperado: 3 líneas

# 8. Wazuh Active Response configurado:
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 \
  grep "100010" /var/ossec/etc/ossec.conf 2>/dev/null && echo "AR: OK" || echo "AR: FALTA"

# 9. Usuario victima DESBLOQUEADO:
multipass exec tid-lab -- bash -c "echo 'victima:demo123' | sudo chpasswd && echo 'victima: OK'"

# 10. IP atacante llega a la VM sin ban (HTTP 200):
curl --interface $ATTACK_IP -s -o /dev/null -w "IP atacante → VM: %{http_code}\n" --max-time 3 http://$VM_IP/

# 11. URL Wazuh Dashboard:
echo "Wazuh: https://$VM_IP  (admin / SecretPassword)"
```

-----------------------------------------
[ ETAPA 1: BUILD / SETUP ]
-----------------------------------------
```bash
# Reconstruir lab desde cero:
bash "/home/carpeano/Documents/SISTEMAS/NETWORKING/Charla Evilsec/scripts/rebuild_tid_lab.sh"

# Shell interactiva en la VM:
multipass shell tid-lab
```
> **Dashboard Wazuh** → `https://<VM_IP>`  (admin / SecretPassword)
> **Security Events** → `rule.id: 100010`  |  `custom-shadow-lock (AR)`


-----------------------------------------
[ ETAPA 2 & 3: ATAQUES Y DEFENSA ACTIVA ]
-----------------------------------------
### --- ATAQUE 1: DoS NGINX & BLOQUEO CROWDSEC ---

```bash
# Lanzar ataque:
bash "/home/carpeano/Documents/SISTEMAS/NETWORKING/Charla Evilsec/scripts/nginx_dos_demo.sh"

# Mostrar alertas de CrowdSec:
multipass exec tid-lab -- sudo cscli alerts list

# Confirmar baneo de IP Atacante en CrowdSec:
multipass exec tid-lab -- sudo cscli decisions list

# Comprobar bloqueo perimetral (Timeout):
VM_IP=$(multipass info tid-lab | awk '/IPv4/ {print $2}' | head -n 1)
BASE_IP=$(echo "$VM_IP" | cut -d. -f1-3)
HOST_IFACE=$(ip route get "$VM_IP" | grep -oP 'dev \K\S+')
ATTACK_IP=$(ip -4 addr show dev "$HOST_IFACE" | grep inet | awk '{print $2}' | cut -d/ -f1 | grep "^${BASE_IP}" | grep -v "${BASE_IP}.1$" | head -n 1)
curl --interface "$ATTACK_IP" --max-time 3 "http://$VM_IP/"

# Comprobar acceso de gestión (HTTP 200):
VM_IP=$(multipass info tid-lab | awk '/IPv4/ {print $2}' | head -n 1)
curl -I "http://$VM_IP/"
```

### --- ATAQUE 2: ESCALADA DE PRIVILEGIOS & WAZUH ---

```bash
# Ejecutar PoC /etc/shadow:
bash "/home/carpeano/Documents/SISTEMAS/NETWORKING/Charla Evilsec/scripts/privilege_escalation_demo.sh"

# Extraer alerta crítica de Wazuh en tiempo real (Lectura /etc/shadow):
multipass exec tid-lab -- bash -c "sudo docker exec single-node-wazuh.manager-1 grep -a -E '\"id\":\"(100010)\"' /var/ossec/logs/alerts/alerts.json | tail -n 1 | jq ."

# Validar que Active Response bloqueó la cuenta:
multipass exec tid-lab -- sudo tail -n 10 /var/ossec/logs/active-responses.log

# Confirmar estado de la cuenta en el sistema (debe tener '!' en el hash):
multipass exec tid-lab -- bash -c "sudo grep '^victima:' /etc/shadow | cut -d: -f1-2"
```

-----------------------------------------
[ ETAPA 4: EXTRACCIÓN DE EVIDENCIAS ]
-----------------------------------------
> **NOTA**: En la carpeta `evidencias/` ya se encuentra el **PLAN B**
> con los JSONs y logs completos en caso de fallo del lab.

```bash
# Para mostrar las evidencias de CrowdSec en la terminal:
cat "/home/carpeano/Documents/SISTEMAS/NETWORKING/Charla Evilsec/evidencias/crowdsec_alerts_cscli.json" | jq .

# Si el lab está sano, extraer en vivo:
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 cat /var/ossec/logs/alerts/alerts.json > wazuh_alerts_dump.json
multipass exec tid-lab -- sudo cscli alerts list -o json > crowdsec_alerts_dump.json
```

-----------------------------------------
[ TROUBLESHOOTING DE EMERGENCIA ]
-----------------------------------------
```bash
# Matar QEMU:
sudo pkill -9 qemu

# Limpiar todos los baneos de CrowdSec:
multipass exec tid-lab -- sudo cscli decisions delete --all
```
