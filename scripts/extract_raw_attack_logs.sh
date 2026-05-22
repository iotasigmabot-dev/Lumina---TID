#!/bin/bash
# extract_raw_attack_logs.sh
# Extrae logs crudos de los ataques (Nginx y Auditd) desde la VM tid-lab

VM_NAME="tid-lab"

echo "==========================================================="
echo "🔍 EXTRACCIÓN DE LOGS CRUDOS DE ATAQUE (EVIDENCIA OFENSIVA)"
echo "==========================================================="

echo -e "\n[1] NGINX: Tráfico del Ataque DoS (últimas 15 líneas)"
echo "-----------------------------------------------------------"
# Mostramos el final del access.log donde se ve la inundación de peticiones
multipass exec "$VM_NAME" -- sudo tail -n 15 /var/log/nginx/access.log

echo -e "\n[2] AUDITD: Intentos de acceso a /etc/shadow"
echo "-----------------------------------------------------------"
# Usamos ausearch interpretando los valores (-i) para que sea legible, 
# filtrando por el archivo /etc/shadow
multipass exec "$VM_NAME" -- sudo ausearch -f /etc/shadow -i 2>/dev/null | tail -n 25

echo -e "\n==========================================================="
echo "✅ Extracción finalizada."
