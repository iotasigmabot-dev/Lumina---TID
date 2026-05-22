#!/bin/bash
# extract_defense_logs.sh
# Extrae logs de detección y bloqueo (Wazuh y CrowdSec) desde la VM tid-lab

VM_NAME="tid-lab"

echo "==========================================================="
echo "🛡️  EXTRACCIÓN DE EVIDENCIA DE DEFENSA (DETECCIÓN Y BLOQUEO)"
echo "==========================================================="

echo -e "\n[1] CROWDSEC: Alertas recientes (Detección de DoS)"
echo "-----------------------------------------------------------"
multipass exec "$VM_NAME" -- sudo cscli alerts list --limit 5

echo -e "\n[2] CROWDSEC: Decisiones activas (Bloqueos en Bouncer)"
echo "-----------------------------------------------------------"
multipass exec "$VM_NAME" -- sudo cscli decisions list

echo -e "\n[3] WAZUH MANAGER: Alertas crudas (Regla 100010 y Active Response)"
echo "-----------------------------------------------------------"
# Buscamos en el alerts.json del manager usando un pequeño script de python 
# para formatear el JSON y hacerlo legible
multipass exec "$VM_NAME" -- sudo docker exec single-node-wazuh.manager-1 \
  python3 -c "
import json
try:
    with open('/var/ossec/logs/alerts/alerts.json') as f:
        for line in f:
            try:
                a = json.loads(line)
                rid = str(a.get('rule', {}).get('id', ''))
                if rid in ['100010', '100011'] or 'active_response' in str(a):
                    print(f\"[{a.get('timestamp', '')}] Regla: {rid} | Nivel: {a.get('rule', {}).get('level', '')} | {a.get('rule', {}).get('description', '')}\")
                    if 'srcip' in a.get('data', {}):
                        print(f\"    IP Atacante: {a['data']['srcip']}\")
            except: pass
except Exception as e:
    print('Error leyendo logs:', e)
" | tail -n 10

echo -e "\n[4] WAZUH AGENT: Ejecución de Active Response"
echo "-----------------------------------------------------------"
multipass exec "$VM_NAME" -- sudo tail -n 5 /var/ossec/logs/active-responses.log

echo -e "\n[5] FIREWALL (IPTABLES): Reglas DROP inyectadas"
echo "-----------------------------------------------------------"
multipass exec "$VM_NAME" -- sudo iptables -L INPUT -n | grep DROP

echo -e "\n==========================================================="
echo "✅ Extracción finalizada."
