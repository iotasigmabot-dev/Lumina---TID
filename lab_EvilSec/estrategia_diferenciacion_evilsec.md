# Estrategia de Diferenciación — Charla TID (Evilsec)

## Análisis del Ecosistema de Oradores

Antes de definir el posicionamiento, es crítico entender lo que el evento ya tiene cubierto.

| # | Orador | Perfil | Tema | Eje Central | Horizonte |
|---|--------|--------|------|-------------|-----------|
| 2 | Rubén | Magíster UBA, 20+ años, Docente | IA Agéntica + MITRE ATLAS | Nuevas superficies de ataque en IA autónoma | **Futuro** |
| 3 | Charles (INSSIDE) | SOC Leader 24x7, OT/IT | "¿Qué pasa después de una alerta?" | Operación reactiva: SIEM → Escalamiento → Contención | **Presente reactivo** |
| 4 | Agustín (INSSIDE) | CSIRT Leader, Forense | "¿Qué pasa después de una alerta?" | War Rooms, Forense, manejo de crisis | **Presente reactivo** |
| **TÚ** | **José** | **Practitioner ofensivo/defensivo** | **TID — Defensa Informada por Amenazas** | **?** | **?** |

---

## El Diagnóstico: Los Huecos Narrativos que Nadie Llena

Analizando el evento en su conjunto, **hay tres huecos enormes** que ninguno de los tres oradores toca:

### Hueco #1: La ESTRATEGIA (entre el Presente Reactivo y el Futuro)
Charles y Agustín operan *después* de que el fuego ya empezó. Rubén habla de los *incendios del futuro*. **Nadie habla de la arquitectura para que el fuego no ocurra.**  
> **Ese es tu territorio.**

### Hueco #2: El PRESUPUESTO REAL
Rubén propone MITRE ATLAS y sistemas de IA defensiva. Charles y Agustín trabajan desde un SOC corporativo 24x7. **Ninguno habla de cómo hace esto una empresa mediana, con presupuesto limitado y sin un SOC interno.**  
> **Ese es tu territorio.**

### Hueco #3: La VALIDACIÓN DE LOS CONTROLES
Charles y Agustín asumen que las alertas del SIEM son correctas y funcionan. Rubén asume que tienes controles para el futuro. **Nadie pregunta: "¿Cómo sabes que tus defensas actuales funcionan contra los ataques reales de hoy?"**  
> **Ese es tu territorio.**

---

## Tu Posicionamiento Único: "El Arquitecto del Medio"

Mientras los demás se posicionan en los extremos (operación reactiva diaria ↔ amenazas del futuro con IA), **tú ocupas el espacio estratégico del medio**: el arquitecto que diseña el sistema para que los controles funcionen *antes* de que llegue la alerta.

```
[RUBÉN]               [VOS]                [CHARLES & AGUSTÍN]
Futuro (IA)  ←←←  Estrategia TID (HOY)  →→→  Reacción (SOC/IR)
MITRE ATLAS       MITRE ATT&CK   LoL          SIEM / War Room
```

**Este es el elevator pitch que deberías articular verbalmente durante la charla:**

> *"Rubén les va a mostrar de dónde vienen las amenazas del futuro. Charles y Agustín les van a mostrar cómo apagar el incendio cuando ya está activo. Yo les voy a mostrar cómo construir el sistema para que el fuego no llegue a existir, sin gastar lo que no tienen."*

---

## Estrategia de Diferenciación por Orador

### vs. Rubén (2do Orador)
**El riesgo:** Ambos usan MITRE como framework. El público puede confundir las capas.  
**Tu movimiento:** Establecer la jerarquía de MITRE de forma explícita.

**Guión recomendado:**
> *"Rubén les habló de MITRE ATLAS, el framework para amenazas de IA. Pero existe un prerequisito que muchas organizaciones aún no cumplen: dominar MITRE ATT&CK, el framework de comportamiento táctico de los atacantes de HOY. No podés construir el segundo piso sin los cimientos."*

**Puntos clave de contraste:**
- Rubén habla de amenazas **en sistemas de IA**. Tú hablas de amenazas **contra sistemas existentes**.
- Rubén usa **MAESTRO + ATLAS** (6 dimensiones de modelado). Tú usas **ATT&CK** (mapeado a comportamiento real observable, con datos empíricos).
- Rubén es **académico/institucional** (UBA, Posgrado). Tú eres **practitioner de campo**. Resalta esto: sin diploma, con terminal abierta.

**Cita de contraste poderosa:**
> *"ATLAS es para defender tu IA. ATT&CK es para defender tu empresa. La mayoría todavía tiene pendiente lo segundo."*

---

### vs. Charles & Agustín (3er y 4to Oradores — INSSIDE)
**El riesgo:** Ellos usan un lema muy parecido: *"Menos teoría. Más experiencia de campo."*  
**Tu movimiento:** Eso es un problema y una oportunidad. Ellos te "pisaron" el lema. Necesitás **apropiarte del otro lado de la misma moneda** y hacerlo de forma explícita durante la charla.

**Guión recomendado:**
> *"Los chicos de INSSIDE les mostraron qué pasa DESPUÉS de la alerta. Impecable. Pero la pregunta que TID nos obliga a hacernos es: ¿cómo saben que esa alerta es correcta? ¿Cómo saben que su SIEM detecta el ataque real que les van a hacer mañana? Eso es BAS: Simulación de Brechas y Ataques. Y eso es lo que diferencia una defensa que PARECE funcionar de una que SABEMOS que funciona."*

**Puntos clave de contraste:**

| Dimensión | Charles & Agustín (SOC/IR) | Tú (TID) |
|-----------|---------------------------|----------|
| **Punto de entrada** | La alerta ya llegó | Antes de que llegue la alerta |
| **Postura** | Reactiva | Proactiva / Continua |
| **Validación** | "Confiamos en el SIEM" | "Validamos que el SIEM funciona (BAS)" |
| **Presupuesto** | SOC 24x7 corporativo | Open-source + LoL |
| **Framework** | Procesos SOC / CSIRT | MITRE ATT&CK + TID |
| **Audiencia target** | Analistas SOC L1/L2 | CISOs, líderes técnicos, equipos sin SOC |

**La conexión positiva (no confrontación):**
No lo plantees como competencia, sino como **complemento arquitectónico**. Durante tu demo, al momento de mostrar cómo CrowdSec filtra el ruido, podés decir:

> *"Esto es lo que le regalamos a Charles y Agustín antes de que arranque su turno de guardia: menos ruido, más señal. TID no reemplaza al SOC. TID hace que el SOC valga la pena."*

---

## La Demo Como Elemento Diferenciador

Aquí está tu ventaja más contundente: **ninguno de los otros dos oradores va a hacer una demo técnica en vivo**.

- Rubén presentará **teoría y modelado** (MAESTRO, ATLAS, superficies de ataque de IA).
- Charles y Agustín presentarán **casos operativos y lecciones aprendidas** (narrativa de incidentes reales).
- **Tú**: terminal abierta, ataque ejecutado en vivo, SIEM respondiendo en tiempo real.

Eso es lo que el público de Evilsec (comunidad técnica/ofensiva) va a recordar. No la diapositiva. **El momento exacto en que el SIEM muestra la alerta de MITRE ATT&CK después del ataque simulado.**

**Instrucción para la charla:** Cuando tengas el dashboard de Wazuh abierto con la alerta mapeada, detente. Deja el silencio por 3 segundos. Luego:
> *"Eso es lo que TID llama 'detección de alta fidelidad'. No un falso positivo. Una alerta exacta, validada, mapeada. Eso es lo que tus controles deberían estar dando hoy."*

---

## Resumen Ejecutivo: Tu Posición en el Evento

**Quién sos:** El único orador que muestra cómo construir la arquitectura defensiva *antes* del incidente, *sin presupuesto millonario*, con una demo técnica en vivo.

**Qué llenás:** El hueco estratégico entre la respuesta reactiva (SOC/IR) y las amenazas del futuro (IA).

**Tu diferencial irreplicable:** La ejecución. El ataque real, el SIEM real, la alerta real. En vivo.

**Tu frase de cierre:**
> *"Menos humo. Más defensa real. Y si no lo viste funcionar en vivo, no es defensa real."*
