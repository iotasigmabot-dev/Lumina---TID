#!/bin/bash
# Recupera acceso a tid-lab cuando el ban de CrowdSec bloquea SSH.
# Mata QEMU, inicia la VM limpia, y aplica el fix ANTES de que el bouncer
# restaure las reglas de iptables desde disco.

VM="tid-lab"
VM_IP="10.78.238.95"

echo "[1/4] Matando QEMU para forzar reboot limpio del kernel..."
sudo pkill -9 qemu 2>/dev/null
sleep 2

echo "[2/4] Iniciando $VM..."
multipass start "$VM" &
START_PID=$!

echo "[3/4] Esperando SSH (intentando cada 0.5s, timeout 90s)..."
for i in $(seq 1 180); do
    if multipass exec "$VM" -- echo "OK" 2>/dev/null | grep -q "OK"; then
        echo "    → SSH disponible después de $((i/2)) segundos"
        break
    fi
    sleep 0.5
done

echo "[4/4] Aplicando fix: deshabilitar restauración de iptables del bouncer..."
multipass exec "$VM" -- sudo systemctl stop crowdsec-firewall-bouncer
multipass exec "$VM" -- sudo iptables -F INPUT
# (No hacemos flush de FORWARD para no romper el enrutamiento de Docker/Wazuh)
multipass exec "$VM" -- sudo sed -i \
    's/^disable_iptables_restore:.*/disable_iptables_restore: true/' \
    /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
multipass exec "$VM" -- sudo cscli decisions delete -i "$VM_IP" 2>/dev/null || true
multipass exec "$VM" -- sudo cscli decisions delete -i "10.78.238.1" 2>/dev/null || true
multipass exec "$VM" -- sudo systemctl start crowdsec-firewall-bouncer

echo ""
echo "=== Verificando acceso ==="
HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "http://$VM_IP/")
if [ "$HTTP" = "200" ]; then
    echo "[✓] Acceso restaurado — HTTP $HTTP"
else
    echo "[!] HTTP $HTTP — verificar manualmente"
fi

wait $START_PID
