# Runbook de Laboratorio TID (Threat Informed Defense)

## Análisis de la Propuesta y Enfoque

**Conceptos y Enfoque (Profiling Evilsec):**
*   **Estética y Tono:** Hacker/underground, pragmático, "Menos humo. Más defensa real". Ideal para conectar con audiencias técnicas y ofensivas.
*   **Mensaje Principal:** La ciberdefensa efectiva no requiere necesariamente de presupuestos millonarios si se cuenta con inteligencia de amenazas y una mentalidad proactiva (Threat-Informed Defense).
*   **Estrategia:** *Living off the Land (LotL)* defensivo. Usar herramientas open-source (CrowdSec, Wazuh) para construir capacidades empresariales de prevención y detección.

**Mejoras Estratégicas al Plan de NotebookLM:**
1.  **Simplicidad para la Demostración:** Intentar desplegar Wazuh, OpenVAS, TheHive y n8n en una sola VM local consumirá demasiados recursos (RAM/CPU) y añadirá múltiples puntos de falla durante una charla en vivo. Reduciremos la pila a los componentes *Core TID*: **Wazuh (Detección/SIEM) + CrowdSec (Prevención/Intel) + Atomic Red Team (Simulación de Brecha)**.
2.  **Ejecución de BAS (Breach & Attack Simulation):** En lugar de montar MITRE CALDERA (que requiere configurar un servidor C2 y agentes en la VM), usaremos **Atomic Red Team** ejecutando las pruebas remotamente vía SSH desde el Host, o mediante scripts bash directos. Esto garantiza que la demo fluya rápida y sin problemas de conectividad o dependencias complejas.
3.  **Gestión Inteligente del Bloqueo:** Un problema clásico en estas demos: si CrowdSec bloquea la IP de tu Host durante el escaneo inicial de Nmap, no podrás conectar por SSH para lanzar el ataque de Atomic Red Team después. El runbook incluye los pasos precisos para "des-banear" tu IP o crear listas blancas dinámicas para que la demo no se detenga.

---

## Nivel 1 (L1): Arquitectura y Flujo Estratégico

### Arquitectura Lógica del Laboratorio
*   **Atacante / Red Team (Host Físico):**
    *   **OS:** Tu sistema operativo principal (Linux/Parrot/Ubuntu).
    *   **Rol:** Emular los TTPs (Tactics, Techniques, and Procedures) del actor de amenazas.
    *   **Herramientas Clave:** Nmap/Hydra (para generar "ruido" perimetral), Atomic Red Team (para emular técnicas específicas), Cliente SSH.
*   **Defensor / Blue Team (Máquina Virtual):**
    *   **OS:** Ubuntu Server 22.04 LTS (o 24.04). Sin interfaz gráfica para ahorrar recursos.
    *   **Rol:** El activo corporativo objetivo, protegido y monitorizado bajo un enfoque TID.
    *   **Herramientas Clave:** Docker Compose, Wazuh (Servidor y Agente local), CrowdSec + IPTables Bouncer.

### Narrativa y Flujo de la Demostración (Pipeline TID)
1.  **El Ruido (Ataque Oportunista):** El atacante escanea agresivamente o intenta fuerza bruta contra la VM.
2.  **Prevención Basada en Intel:** CrowdSec analiza los logs y consulta su red de inteligencia. Detecta el comportamiento anómalo y corta el acceso en la capa de red (IPTables), demostrando cómo limpiar el "ruido".
3.  **La Brecha (Simulación Emulada):** Simulando un escenario de "*Assume Breach*" (donde el atacante ya está dentro), se ejecuta una técnica silenciosa de recolección de credenciales usando Atomic Red Team.
4.  **Detección Mapeada:** Wazuh correlaciona la ejecución interna, mapeándola en tiempo real con la matriz MITRE ATT&CK, enviando una alerta de alta fidelidad al tablero defensivo.

---

## Nivel 2 (L2): Construcción e Implementación (Setup Previo a la Charla)

### 1. Preparación de la Máquina Virtual con Multipass
Dado que ya tienes Multipass instalado, es la herramienta perfecta para desplegar este laboratorio en segundos, manteniendo el enfoque "LotL" y CLI.

1.  Lanzar la instancia de Ubuntu 24.04 con los recursos necesarios (4GB RAM, 2 vCPU, 20GB disco):
    ```bash
    multipass launch 24.04 --name tid-lab --memory 4G --cpus 2 --disk 20G
    ```
2.  Obtener la dirección IP de la VM (anótala para los pasos de la demo):
    ```bash
    multipass info tid-lab
    ```
3.  Acceder a la terminal de la VM:
    ```bash
    multipass shell tid-lab
    ```
4.  Instalar dependencias base en la VM:
    ```bash
    sudo apt update && sudo apt install -y curl git wget docker.io docker-compose ufw iptables jq
    ```

### 2. Despliegue de Wazuh (Detección / SIEM)
Para no saturar la VM, usaremos el despliegue Docker "Single-Node" de Wazuh.
1.  Clonar el repositorio oficial de despliegue en Docker:
    ```bash
    git clone https://github.com/wazuh/wazuh-docker.git -b v4.8.0
    cd wazuh-docker/single-node
    ```
2.  Generar los certificados y levantar los contenedores:
    ```bash
    docker-compose -f generate-indexer-certs.yml run --rm generator
    docker-compose up -d
    ```
3.  Instalar el **Agente de Wazuh** en el sistema base de la propia VM (para que monitoree a Ubuntu). Desde el dashboard de Wazuh, usa la opción "Add Agent" y sigue las instrucciones para Linux, apuntando a `127.0.0.1` o a la IP local de la VM.

### 3. Instalación de CrowdSec (Prevención Proactiva)
1.  Instalar el motor de seguridad de CrowdSec:
    ```bash
    curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash
    sudo apt-get install crowdsec -y
    ```
2.  Instalar el "Bouncer" de Firewall (el que ejecuta el bloqueo real):
    ```bash
    sudo apt-get install crowdsec-firewall-bouncer-iptables -y
    ```
3.  Validar que CrowdSec está leyendo los logs de SSHD por defecto:
    ```bash
    sudo cscli metrics
    ```

### 4. Preparación del Host (Herramientas Ofensivas)
1.  Descargar Atomic Red Team:
    ```bash
    git clone https://github.com/redcanaryco/atomic-red-team.git
    ```
2.  Localizar la técnica exacta que se va a usar. Para Linux, la **T1003.008 (OS Credential Dumping: /etc/passwd and /etc/shadow)** es rápida y muy visual.
    *   *Path en el repo:* `atomic-red-team/atomics/T1003.008/T1003.008.md`

---

## Nivel 3 (L3): Runbook de Ejecución de la Demo (Día del Evento)

> **[IMPORTANTE]** Mantén abierta una ventana del navegador en tu Host con el Dashboard de Wazuh (`https://<IP-VM>`) y una terminal local lista para atacar.

### Fase 1: El Contexto (1 minuto)
1.  Muestra la matriz MITRE ATT&CK brevemente en las diapositivas.
2.  Abre el dashboard de Wazuh. Muestra a la audiencia que está en "limpio", sin alertas recientes.

### Fase 2: Bloqueo de Ruido Perimetral (3 minutos)
1.  **[Host - Atacante]** Intenta un escaneo agresivo o fuerza bruta contra la VM. *Hydra* suele disparar CrowdSec más rápido que Nmap:
    ```bash
    hydra -l root -p password ssh://<IP-VM>
    ```
2.  **[Host - Atacante]** Intenta hacer un ping rápido. Debería fallar (Time out), indicando que has sido bloqueado.
    ```bash
    ping <IP-VM>
    ```
3.  **[VM - Defensor]** (Desde otra terminal en tu Host, usa `multipass shell tid-lab` para entrar a la VM):
    Muestra cómo la inteligencia de CrowdSec tomó la decisión:
    ```bash
    sudo cscli decisions list
    ```
4.  **[VM - Defensor]** Remueve el baneo para poder continuar con la demo:
    ```bash
    sudo cscli decisions delete -i <IP-TU-HOST>
    ```

### Fase 3: Simulación de Brecha (Atomic Red Team) (3 minutos)
1.  **[Host - Atacante]** Explica que la Defensa Informada en Amenazas asume que "el perímetro eventualmente caerá".
2.  Lanza el test simulado (ejecutando directamente un comando que mapea a la técnica de robo de credenciales):
    ```bash
    ssh usuario@<IP-VM> 'cat /etc/passwd > /tmp/passwd.bak && cat /etc/shadow > /tmp/shadow.bak'
    ```

### Fase 4: Optimización y Visibilidad (2 minutos)
1.  **[Host - Navegador]** Ve a la interfaz web de Wazuh.
2.  Navega a **Security events**.
3.  Abre la alerta recién generada y destaca:
    *   **Rule ID / Descripción:** Muestra cómo el SIEM entendió la acción.
    *   **MITRE ATT&CK:** Señala los metadatos de la alerta donde aparece mapeada la Táctica (Credential Access) y la Técnica (OS Credential Dumping).
4.  **Conclusión:** Finaliza explicando que TID te permite construir, medir y probar defensas contra TTPs reales sin gastar miles de dólares, enfocando el presupuesto de "tiempo" en lo que de verdad importa.
