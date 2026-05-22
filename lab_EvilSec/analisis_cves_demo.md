# Análisis CVE — Selección para Demo TID (Evilsec)

## Evaluación de Candidatos

### Criterios de selección para una demo en vivo (15 min)

| Criterio | Peso |
|----------|------|
| Reproducible sin compilar código | Alto |
| Resultado visible en < 30 segundos | Alto |
| Detectable por Wazuh o CrowdSec | Alto |
| Impacto narrativo ("wow factor") | Medio |
| Requiere versión antigua/downgrade | Riesgo |
| Dependencia de condición de carrera | Riesgo |

---

## NGINX — Evaluación de las 3 CVEs

### ✅ CVE-2026-42945 — NGINX Rift (SELECCIONADA)
- **Tipo:** Heap buffer overflow en ngx_http_rewrite_module
- **Activación:** Configuración de NGINX con regex rewrite usando grupos sin nombre (`$1`, `$2`) + `?`
- **Para la demo:** Instalar NGINX 1.29.x (vulnerable) + configurar un bloque rewrite intencionalmente vulnerable. El atacante envía requests HTTP malformados que crashean el worker process.
- **Resultado visible:** El proceso NGINX muere → Wazuh alerta (servicio caído) → CrowdSec detecta el patrón de requests anómalos → la IP queda baneada.
- **MITRE ATT&CK:** T1190 (Exploit Public-Facing Application)
- **Por qué es perfecta:**
  - RCE solo funciona sin ASLR. En Ubuntu 24.04, ASLR está activo, por lo que demostrar DoS (crash) es suficiente y más seguro.
  - El DoS es 100% reproducible y visual: el worker cae, el dashboard de Wazuh lo muestra.
  - CrowdSec puede detectar el patrón de requests antes de que llegue al crash.
  - **Afecta NGINX 0.6.27-1.30.0** → instalar 1.29.x deliberadamente.

### ❌ CVE-2026-40460 — IP Spoofing en HTTP/3 QUIC (DESCARTADA)
- Requiere módulo HTTP/3 QUIC activo (experimental, no instalado por defecto).
- El efecto es evasión de rate limiting, muy difícil de visualizar en vivo.
- No genera alertas claras en Wazuh.

### ❌ CVE-2026-42926 — HTTP/2 Traffic Injection (DESCARTADA)
- Requiere configuración `proxy_http_version 2` con `proxy_set_body` simultáneamente.
- El efecto (frames HTTP/2 corruptos al upstream) es invisible sin herramientas de análisis de red.
- No recomendada para demo visual.

---

## Linux Kernel — Evaluación de las 3 CVEs

### ✅ CVE-2026-46333 — ssh-keysign-pwn (SELECCIONADA)
- **Tipo:** Race condition en `__ptrace_may_access()` al salir un proceso suid/sgid
- **Activación:** Correr el PoC público mientras un proceso privilegiado (como `chage` o `ssh-keysign`) está finalizando.
- **Para la demo:** Crear un usuario sin privilegios dentro de la VM. Descargar el PoC de Qualys. Ejecutarlo. En segundos: contenido de `/etc/shadow` y clave privada SSH del host visibles en pantalla.
- **Resultado visible:** El PoC imprime en terminal las líneas de `/etc/shadow` (hashes de contraseñas) + la private key SSH → **impacto visual inmediato y devastador**.
- **MITRE ATT&CK:** T1003.008 (OS Credential Dumping: /etc/shadow) + T1552.004 (Unsecured Credentials: Private Keys)
- **Por qué es perfecta:**
  - PoC público disponible. Sin compilación. Solo Python o un binario.
  - El resultado es inmediato y visualmente impactante: hashes de contraseñas reales en pantalla.
  - Wazuh puede detectar el acceso a `/etc/shadow` via Audit rules o File Integrity Monitoring.
  - **No requiere downgrade de kernel** → Ubuntu 24.04 LTS sin parchear tiene el kernel vulnerable.
  - Qualys fue quien la reportó → credibilidad máxima de la fuente.

### ⚠️ CVE-2026-31431 — Copy Fail (ALTERNATIVA — más compleja)
- **Tipo:** Logic flaw en algif_aead (AF_ALG crypto subsystem) + splice()
- **Activación:** Script Python de 732 bytes que hace un write de 4 bytes al page cache.
- **Para la demo:** Muy potente (escala a root completo). Pero tiene riesgo: puede desestabilizar el kernel de la VM si algo sale mal. Si la VM se cae durante la demo, es catastrófico.
- **Decisión:** Usar como demo secundaria o de "encore" solo si hay tiempo. NO como demo principal.

### ❌ CVE-2026-43284 — Dirty Frag/Fragnesia (DESCARTADA)
- Involucra subsistemas IPsec/ESP y RxRPC (interfaces de red específicas).
- Requiere configuración especial de red que no tenemos en Multipass.
- No hay PoC público estable aún para Ubuntu 24.04.

---

## Selección Final: El Arco Narrativo de la Demo

```
ACTO 1 — ATAQUE EXTERNO (desde el Host)
[T1190] CVE-2026-42945 — NGINX Rift
├── Desde el HOST: curl / exploit HTTP request → nginx worker crash
├── CrowdSec detecta el patrón anómalo → banea la IP del host
└── Wazuh alerta: "Nginx process terminated unexpectedly"

         ↓ "El perímetro cayó. Asumimos brecha."

ACTO 2 — POST-BREACH (dentro de la VM, como usuario sin privilegios)
[T1003.008 + T1552.004] CVE-2026-46333 — ssh-keysign-pwn
├── ssh ubuntu@<IP-VM> (acceso como usuario normal)
├── Ejecutar PoC → /etc/shadow aparece en terminal
├── Clave privada SSH del servidor expuesta en terminal
└── Wazuh alerta: "Unauthorized access to /etc/shadow"

         ↓ "Esto es lo que TID detecta. Esto es lo que Rubén no puede prevenir."
```


---


## Mapeo MITRE ATT&CK para el Dashboard de Wazuh

| CVE | Técnica MITRE | ID |
|-----|---------------|----|
| CVE-2026-42945 | Exploit Public-Facing Application | T1190 |
| CVE-2026-46333 | OS Credential Dumping: /etc/shadow | T1003.008 |
| CVE-2026-46333 | Unsecured Credentials: Private Keys | T1552.004 |

---

## Ventaja Narrativa para la Charla

> **"Esto no son Atomic Red Team scripts de 2022. Esto es lo que los atacantes están usando HOY, esta semana. CVE-2026-42945 fue reportada explotada en la wild hace 3 días. CVE-2026-46333 fue publicada el 15 de mayo. Y nosotros ya tenemos detección activa."**

Esto diferencia tu charla de los demás oradores que hablan de frameworks o IA: vos mostrás detección y respuesta de amenazas **actuales, reales y en vivo**.
