#!/bin/bash
VM_IP=$(multipass info tid-lab | awk '/IPv4/ {print $2}' | head -n 1)
HOST_IFACE=$(ip route get "$VM_IP" | grep -oP 'dev \K\S+')
BASE_IP=$(echo "$VM_IP" | cut -d. -f1-3)

# Find existing attack IPs and delete them
EXISTING=$(ip addr show "$HOST_IFACE" | grep "inet ${BASE_IP}" | awk '{print $2}' | cut -d/ -f1 | grep -v "^${BASE_IP}\.1$")
for IP in $EXISTING; do
  echo "Deleting existing attacker IP: $IP"
  sudo -n ip addr del ${IP}/24 dev $HOST_IFACE
done

# Assign a new attack IP
for oct in $(seq 50 99); do
  candidate="${BASE_IP}.${oct}"
  if ! ip addr show "$HOST_IFACE" | grep -q "$candidate"; then
    sudo -n ip addr add "${candidate}/24" dev "$HOST_IFACE"
    ATTACK_IP="$candidate"; break
  fi
done
echo "IP atacante rotada/asignada: $ATTACK_IP"

echo ""
echo "--- PREFLIGHT CHECKS ---"
echo "1. VM corriendo:"
multipass info tid-lab | grep State

echo "2. Servicios críticos:"
for svc in nginx crowdsec crowdsec-firewall-bouncer wazuh-agent auditd; do
  echo "$svc: $(multipass exec tid-lab -- systemctl is-active $svc 2>/dev/null)"
done

echo "3. Wazuh containers:"
multipass exec tid-lab -- sudo docker ps --format "{{.Names}}: {{.Status}}" 2>/dev/null

echo "4. NGINX HTTP:"
curl -s -o /dev/null -w "NGINX: %{http_code}\n" --max-time 3 http://$VM_IP/

echo "5. CrowdSec status:"
multipass exec tid-lab -- sudo cscli decisions list

echo "6. Auditd reglas:"
multipass exec tid-lab -- sudo auditctl -l | grep -E "shadow|ssh_key"

echo "7. AR config:"
multipass exec tid-lab -- sudo docker exec single-node-wazuh.manager-1 grep "100010" /var/ossec/etc/ossec.conf 2>/dev/null && echo "AR: OK" || echo "AR: FALTA"

echo "8. IP atacante llega a VM:"
curl --interface $ATTACK_IP -s -o /dev/null -w "IP atacante → VM: %{http_code}\n" --max-time 3 http://$VM_IP/

echo "9. URL Wazuh Dashboard:"
echo "Wazuh: https://$VM_IP  (admin / SecretPassword)"
