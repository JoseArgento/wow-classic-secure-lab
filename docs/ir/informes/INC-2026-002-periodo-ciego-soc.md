# INC-2026-002: Siete horas de período ciego en el SOC

| Campo | Valor |
|---|---|
| **Estado** | Cerrado |
| **Severidad** | Baja |
| **Clasificación** | Pérdida de visibilidad (planificada), Escaneo |
| **Playbook** | IR-03, con triage manual según IR-01 |
| **Detectado** | 2026-10-28 ~09:20 (revisión matinal) |
| **Cerrado** | 2026-10-28 09:45 |
| **Analista** | José Argento |

## 1. Resumen

Durante la noche se apagó la PC principal, donde viven las VMs de
observabilidad (Loki + Grafana) y del SOAR (n8n). El i3 siguió en línea,
protegido por sus controles locales, pero durante ~7 horas **nadie evaluó
alertas ni respondió**. En ese período Suricata registró una IP de lista negra
(193.163.125.92) contra el 8085. A la mañana se revisó el período ciego a mano
desde el almacenamiento local del i3: la IP resultó ser un **escáner de
medición de internet** que se declara no hostil, y no hubo impacto. El
incidente deja a la vista tres límites del diseño y una pérdida de datos en
Loki.

## 2. Línea de tiempo (28/10)

| Hora | Fuente | Evento |
|---|---|---|
| ~01:55 | Operador | Apagado de la PC principal (VMs observabilidad, ai-lab y Kali) |
| ~02:00 | Loki | Último latido recibido del i3. **Empieza el período ciego** |
| 05:54:05 | Suricata (i3) | 193.163.125.92 -> 8085/TCP, firma *ET DROP Dshield Block Listed Source*, prioridad 2. Sin triage |
| ~09:15 | Operador | PC y VMs encendidas. Los contenedores **no arrancan solos** (ver §10); se levantan a mano |
| ~09:15 | Loki | Vuelven los latidos. **Fin del período ciego (~7 h 15 min)** |
| 09:20 | Operador | Revisión del período ciego (IR-03 §2) |
| 09:36 | n8n | Intento de triage por el chat del workflow: falla (ver §10) |
| 09:43 | Operador | Triage manual (AbuseIPDB, VirusTotal, RDAP/WHOIS) |

## 3. Detección

- **Fuente:** revisión manual, no una alerta. El SOC no puede avisar de su
  propia ausencia: el dead man's switch vive en la misma VM que se apagó.
- **Al volver**, tampoco se disparó nada: Grafana arrancó cuando los latidos
  ya llegaban de nuevo, así que la regla nunca vio el hueco.
- **Activo afectado (la cobertura, no un servicio):** i3, 8085/TCP sin
  servicio (VMaNGOS apagado).

## 4. Indicadores (IOCs)

| Tipo | Valor | Notas |
|---|---|---|
| IP | `193.163.125.92` | Driftnet Ltd, AS211298, `193.163.125.0/24`, Reino Unido, hostname `r1-92-5c.census.internet-measurement.com` |

## 5. Análisis

**Qué se perdió y qué no:**

| Dato | ¿En Loki? | ¿En el i3? |
|---|---|---|
| Latidos (02:00-09:00) | **No** | Sí: 420 (7 h × 60, completos) |
| Alertas de Suricata | **No** | Sí: 39 en `eve.json` |

Alloy siguió leyendo, pero con Loki inaccesible agotó los reintentos y
**descartó** los lotes. El original quedó intacto en el i3.

**Las 39 alertas de Suricata:**

| Cant. | Firma | Prioridad | Lectura |
|---|---|---|---|
| 22 | SURICATA Ethertype unknown | 3 | Ruido del decodificador (tramas de la LAN) |
| 16 | ET INFO GNU/Linux APT User-Agent Outbound | 3 | El propio i3 actualizando paquetes |
| 1 | ET DROP Dshield Block Listed Source group 1 | 2 | **La única relevante** |

Las 38 de prioridad 3 no habrían notificado aunque el SOC estuviera encendido:
el corte en prioridad 2 funcionó como se diseñó.

**Triage manual de 193.163.125.92:**

| Fuente | Resultado |
|---|---|
| AbuseIPDB | Confianza de abuso **100 %**, **45.524** reportes de 405 fuentes, desde mayo de 2021 |
| VirusTotal | **11/92** (categorías mezcladas: malicious, phishing, malware) |
| RDAP / WHOIS | Red `UK-DRIFTNET-20210505`. Comentario del registro: *"This IP range is not attacking your network. Visit https://internet-measurement.com for more details."* |

**Juicio del analista:** es un **escáner de medición de internet** que
recorre todo el espacio IPv4 y se identifica como tal. Su puntaje de abuso es
máximo por volumen: decenas de miles de administradores reportan que los
escaneó, no que los atacó. **Reputación no es intención.** El riesgo real no
es este escáner: es que los datos que recolecta hacen pública la exposición
del 8085, y otros los consultan.

Un agente con solo AbuseIPDB y VirusTotal lo habría clasificado como
Malicioso. La pista que lo distingue está en los comentarios del WHOIS, que
**el SOAR hoy no ve**: el recorte de tokens del 28/10 (*Optimize Response*)
dejó solo nombre, rango, país y tipo.

## 6. Respuesta

| Acción | Hora | Quién / qué | Verificación |
|---|---|---|---|
| Levantar Loki, Grafana y n8n | ~09:15 | Operador (`docker compose up -d`) | Latidos en Grafana |
| Revisar el período ciego | 09:20 | Operador, desde el i3 | §5 |
| Triage manual | 09:43 | Operador | §5 |
| Ban | - | **No se aplicó**: el escaneo fue horas antes, no hubo acceso y la IP es un escáner declarado | - |

## 7. Impacto

**Ninguno sobre los servicios.** VMaNGOS estaba apagado, el 8085 sin
servicio y ufw descarta el tráfico no permitido. Las defensas locales del i3
(ufw, fail2ban, Suricata registrando) siguieron activas toda la noche.

**Sobre el SOC:** 7 h 15 min sin evaluación de alertas ni respuesta, y el
mismo período **ausente en Loki**. Solo es investigable desde el i3.

## 8. MITRE ATT&CK (v19)

| Táctica | Técnica | Justificación |
|---|---|---|
| Reconnaissance (TA0043) | T1595: Active Scanning | Escaneo masivo no dirigido de servicios expuestos |

## 9. Métricas

| Métrica | Tiempo |
|---|---|
| Período ciego | ~7 h 15 min (02:00 -> 09:15) |
| Evento -> triage | ~3 h 50 min (05:54 -> 09:43), solo por revisión manual |
| Contención | No aplica |

## 10. Lecciones y acciones

| Lección | Acción | Estado |
|---|---|---|
| Con la PC apagada no hay alertas ni respuesta, y Loki pierde el período | Documentar como limitación. A futuro: buffer en disco de Alloy, u observabilidad en hardware siempre encendido | Backlog |
| El dead man's switch no puede avisar de su propia ausencia (vive en la VM que se apaga) | Monitor de latido **externo** (un servicio que espere un ping periódico del i3 y avise si falta) | Backlog |
| `docker compose stop` + `restart: unless-stopped` = los contenedores no vuelven solos al encender | Procedimiento: apagar las VMs solo con `sudo poweroff`. Loki con `stop_grace_period: 1m` para que igual guarde a disco | Hecho |
| El chat del workflow del SOAR no sirve para triage manual: el agente y los nodos posteriores leen datos del Webhook | Workflow separado "SOAR - triage manual" (chat -> agente -> respuesta, sin cache ni ban) | Backlog |
| Reputación ≠ intención: un escáner de investigación tiene score 100 | Sumar `remarks` a los campos del WHOIS en *Optimize Response*, y una línea en el prompt sobre escáneres declarados | Hoy |
| El almacenamiento local del i3 (journal, `eve.json`) permitió revisar todo el período | Mantenerlo; es la fuente de verdad cuando el SOC no ve | Hecho |

## 11. Evidencia

`evidencia-lab/14-periodo-ciego/`:

- `01_grafana-latidos-hueco-02-a-09.png`
- `02_n8n-chat-error-webhook-no-ejecutado.png`
- `03_abuseipdb-193.163.125.92.png`
- `04_virustotal-193.163.125.92.png`
- `05_rdap-whois-193.163.125.92-remarks.png`
