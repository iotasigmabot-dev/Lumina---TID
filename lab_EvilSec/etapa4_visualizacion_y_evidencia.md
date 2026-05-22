# ETAPA 4: Visualización y Recolección de Evidencia

Esta etapa final del laboratorio se enfoca en demostrar el impacto de los ataques y la efectividad de las defensas de TID utilizando interfaces gráficas (Dashboards) y extracción automatizada de logs crudos.

---

## 1. Visualización en Dashboards (Interfaces Gráficas)

### 1.1 Dashboard de Wazuh (SIEM & XDR)

Wazuh proporciona una interfaz web completa basada en OpenSearch Dashboards para visualizar alertas de seguridad, métricas de MITRE ATT&CK e información de integridad de archivos.

**Cómo acceder:**
1. Obtén la IP de la máquina virtual (si no la recuerdas, ejecuta `multipass info tid-lab` en tu host).
2. Abre tu navegador web y navega a `https://<IP_DE_LA_VM>` (ej. `https://10.78.238.104`).
3. Acepta la advertencia de certificado autofirmado.
4. **Credenciales por defecto:**
   - **Usuario:** `admin`
   - **Contraseña:** `SecretPassword`

**Qué buscar en la demo:**
- Ve al módulo **Security events**.
- Observa las alertas de Nivel 10 asociadas a la lectura de `/etc/shadow` (Regla `100010` o `100011`).
- Ve al módulo **MITRE ATT&CK** y muestra cómo los eventos se mapean a tácticas como *Credential Access* y *Privilege Escalation*.

---

### 1.2 Consola de CrowdSec (Inteligencia Comunitaria)

Si tienes una cuenta gratuita en la [Consola de CrowdSec](https://app.crowdsec.net/), puedes enrolar esta instancia local para ver alertas y telemetría en la nube de forma centralizada.

**Cómo enrolar la instancia (VM):**
1. Inicia sesión en [app.crowdsec.net](https://app.crowdsec.net/).
2. Haz clic en **"Add Instance"** y copia el comando de enrolamiento (`cscli console enroll <TU_CLAVE>`).
3. Entra a la VM (`multipass shell tid-lab`) y ejecuta el comando copiado usando `sudo`:
   ```bash
   sudo cscli console enroll <TU_CLAVE>
   sudo systemctl reload crowdsec
   ```
4. Vuelve a la consola web y acepta la nueva instancia.

**Qué buscar en la demo:**
- Verás tu instancia `tid-lab` conectada.
- Podrás revisar las alertas generadas por el ataque DoS.
- Podrás observar la inteligencia comunitaria (CTI) compartida por otros usuarios de CrowdSec.

---

## 2. Extracción Automatizada de Logs Crudos

Para apoyar la presentación con evidencia técnica dura, se han creado dos scripts en la carpeta `scripts/` que extraen automáticamente los logs de los ataques y las defensas desde la VM hacia el Host.

### 2.1 Extracción de Logs Ofensivos (El Ataque)

Este script muestra cómo el atacante dejó huellas en los logs del servidor web (NGINX) y a nivel del sistema operativo mediante las llamadas al sistema (Auditd).

**Ejecución desde el HOST:**
```bash
./scripts/extract_raw_attack_logs.sh
```

**Salida Esperada:**
1. **NGINX:** Muestra la inundación de peticiones HTTP 400 (resultado del DoS).
2. **AUDITD:** Muestra los eventos decodificados indicando que un usuario (`uid` = victima) intentó ejecutar el syscall `openat` sobre el archivo `/etc/shadow`.

---

### 2.2 Extracción de Logs Defensivos (La Respuesta TID)

Este script consolida la reacción de los órganos de defensa: las alertas, las decisiones de bloqueo y las reglas inyectadas en el firewall.

**Ejecución desde el HOST:**
```bash
./scripts/extract_defense_logs.sh
```

**Salida Esperada:**
1. **CROWDSEC Alertas & Decisiones:** Lista de detecciones del escenario `http-bad-user-agent` o `http-crawl-non_statics` y el baneo aplicado a la IP atacante.
2. **WAZUH Manager:** Las alertas en formato JSON (simplificadas) mostrando que la regla `100010` fue disparada.
3. **WAZUH Agente:** El log del script de respuesta activa (`ssh-drop.sh`) ejecutado en el endpoint.
4. **IPTABLES:** Las reglas `DROP` insertadas en el firewall del sistema protegiendo a la VM de nuevas peticiones de la IP hostil.
