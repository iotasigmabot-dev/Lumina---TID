#!/bin/bash
# Demo CVE-2026-46333 — ssh-keysign-pwn
# Ejecuta el ataque de escalada de privilegios y disparo de Wazuh

echo "[*] Preparando entorno de ataque (Escalada de Privilegios)..."

echo "[*] Asegurando que el usuario victima esté desbloqueado antes de empezar..."
multipass exec tid-lab -- sudo usermod -U victima 2>/dev/null || true

echo "[*] Configurando llaves SSH para el ataque..."
multipass exec tid-lab -- bash -c "
# Preparar clave SSH para victima si no existe
if [ ! -f /tmp/evil_key ]; then
    ssh-keygen -t ed25519 -f /tmp/evil_key -N '' -q
fi
PUB_KEY=\$(cat /tmp/evil_key.pub)

# Configurar authorized_keys
sudo mkdir -p /home/victima/.ssh
echo \"\$PUB_KEY\" | sudo tee /home/victima/.ssh/authorized_keys > /dev/null
sudo chown -R victima:victima /home/victima/.ssh
sudo chmod 700 /home/victima/.ssh
sudo chmod 600 /home/victima/.ssh/authorized_keys
"

echo "==========================================================="
echo "[*] Iniciando ataque SSH local como usuario comprometido 'victima'"
echo "==========================================================="

multipass exec tid-lab -- bash -c "
ssh -i /tmp/evil_key -o StrictHostKeyChecking=no -o BatchMode=yes victima@127.0.0.1 'python3 /opt/pocs/shadow_reader_demo.py'
echo '[*] Trigger de Active Response enviado (Auditoría de /etc/shadow)'
"

echo "==========================================================="
echo "[*] Ataque completado. Verifica el dashboard de Wazuh."
