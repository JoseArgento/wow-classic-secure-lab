# INC-2026-001: Escaneo desde IP con mala reputación al puerto del mundo (8085)

| Campo | Valor |
|---|---|
| **Estado** | Cerrado |
| **Severidad** | Media |
| **Clasificación** | Escaneo |
| **Playbook** | IR-01 |
| **Detectado** | 2026-10-27 23:07 (hora de Argentina) |
| **Cerrado** | 2026-10-28 00:14 (fin del ban) |
| **Analista** | José Argento |

## 1. Resumen

Media hora después de poner en servicio Suricata, una IP de Brasil
(16.5.0.223) envió tráfico al puerto 8085/TCP del i3, el puerto del servidor
de mundo de VMaNGOS, publicado en el router. Suricata la reconoció por
**reputación** (listas CINS y Dshield), el SOAR la enriqueció (AbuseIPDB 100,
VirusTotal 7/92) y la clasificó como **Maliciosa**, y el operador aprobó el
ban por Telegram. **Sin impacto**: VMaNGOS estaba apagado y el tráfico no
obtuvo respuesta. Es el primer atacante real bloqueado por el flujo completo
del Mini SOC en la infraestructura propia.

## 2. Línea de tiempo

| Hora (27/10) | Fuente | Evento |
|---|---|---|
| 22:28 | i3 | VMaNGOS apagado (`docker compose down`) tras pruebas |
| 22:44 | i3 | Suricata 8.0.3 en servicio (53.275 firmas ET Open) |
| 23:02:06 | Suricata | Primera alerta de 16.5.0.223 (ET CINS / ET DROP Dshield) |
| 23:06:56 | n8n | Ejecución del workflow: triage de 16.5.0.223 |
| 23:07 | Telegram | Veredicto **Malicioso** + PROPUESTA DE BAN (tier *short*) |
| ~23:11:40 | Telegram / i3 | Ban aprobado -> **"Ban ejecutado"**, jail `soar` (fin de la ejecución de 23:06:56) |
| 23:11:56 | n8n / Telegram | Grafana vuelve a notificar la misma IP: veredicto desde el cache + **nueva propuesta, aunque la IP ya estaba baneada** |
| 23:14:18 | Telegram / i3 | Segunda aprobación -> ban re-ejecutado (idempotente: `Total banned: 1`) |
| 00:14 (28/10) | fail2ban | Fin del ban (tier *short*, 1 h) |

## 3. Detección

- **Fuente y regla:** Suricata -> Loki -> regla *Suricata IDS - prioridad media* (Grafana) -> n8n.
- **Firmas:**
  - `ET CINS Active Threat Intelligence Poor Reputation IP group 26`
  - `ET DROP Dshield Block Listed Source group 1`
- **Activo:** i3 (`valheim`), puerto 8085/TCP (mangosd). **No estaba en servicio.**

Son firmas de **reputación**, no de comportamiento: no dicen qué intentaba la
IP, sino que ya figura en listas públicas de atacantes. Detectan desde el
primer paquete, sin esperar a que el atacante haga algo reconocible.

## 4. Indicadores (IOCs)

| Tipo | Valor | Notas |
|---|---|---|
| IP | `16.5.0.223` | Rango `16.5.0.0/24`, EMBNEX LLC, Brasil |

## 5. Análisis y enriquecimiento

| Fuente | Resultado |
|---|---|
| AbuseIPDB | Score **100**, **721** reportes |
| VirusTotal | **7/92** motores la marcan maliciosa, 2 sospechosa |
| WHOIS / RDAP | EMBNEX LLC, `16.5.0.0/24`, Brasil |
| Veredicto del SOAR | **Malicioso**, recomendación: bloquear |
| ¿Acceso exitoso? | **No.** El servicio estaba apagado (ver §7) |

Juicio del analista: veredicto coherente. Las tres fuentes coinciden, y la
detección de Suricata es justamente por reputación. La regla es de severidad
media, así que la propuesta de ban salió **por el veredicto Malicioso**, como
está diseñado (`IF ¿Proponer ban?`: Malicioso **o** severidad high).

## 6. Respuesta

| Acción | Hora | Quién / qué | Verificación |
|---|---|---|---|
| Ban tier *short* (1 h) | ~23:11:40 | Operador aprueba en Telegram -> n8n -> SSH `soar` -> `soar-ban.sh` | `fail2ban-client status soar`: `16.5.0.223` en *Banned IP list* |
| Ban repetido | 23:14:18 | Segunda propuesta aprobada | Sin efecto adicional (`Total banned: 1`) |
| Levantamiento del ban | 00:14 | fail2ban (automático) | - |

## 7. Impacto

**Ninguno.** VMaNGOS estaba apagado desde las 22:28: sin contenedores no hay
regla de DNAT de Docker para el 8085, así que el tráfico llegó a la cadena
`input` del i3, donde ufw descarta todo lo no permitido. Lo confirma un escaneo
desde la Kali esa misma noche: con VMaNGOS apagado, 999 de los 1000 puertos
aparecen *filtered* (solo el 22 abierto a la LAN). Suricata igual vio el
tráfico porque captura una copia de los paquetes en la placa, antes del
firewall.

El 8085 también es un puerto alternativo común de HTTP: no hay evidencia de
que el escaneo buscara específicamente un servidor de WoW.

## 8. MITRE ATT&CK (v19)

| Táctica | Técnica | Justificación |
|---|---|---|
| Reconnaissance (TA0043) | T1595: Active Scanning | Tráfico no solicitado a un puerto publicado desde una IP de escaneo conocida |

## 9. Métricas

| Métrica | Tiempo |
|---|---|
| Detección (primer evento -> Telegram) | **~5 min** (23:02:06 -> 23:07). Ver lección sobre `group_interval` |
| Decisión (Telegram -> respuesta humana) | ~4 min 30 s (23:07 -> ~23:11:40) |
| Contención (aprobación -> "Ban ejecutado") | Segundos |

## 10. Lecciones y acciones

| Lección | Acción | Estado |
|---|---|---|
| Un servidor doméstico recibe tráfico hostil real en minutos, sin publicidad y con el juego apagado | Usar como evidencia del problema en la tesis | Hecho |
| Las firmas de reputación detectan desde el primer paquete | Mantener ET Open al día (cron diario de `suricata-update`) | Hecho |
| Con una regla de severidad media, la propuesta depende del veredicto del LLM | Ese mismo día, un escaneo interno salió *Benigno* por falta de contexto: se agregó la firma al prompt del agente | Hecho |
| La detección tardó ~5 min, cuando la regla evalúa cada minuto. En ese momento la regla ya tenía otra instancia disparada (el falso positivo de DuckDNS): Grafana agrupaba todas las IPs de la regla en un mismo grupo, y una alerta nueva en un grupo ya abierto espera al siguiente `group_interval` (5 min por defecto) | `group_by` por IP y firma: cada IP abre su propio grupo y sale tras el `group_wait` (30 s). Aplicado a las reglas de Suricata (28/10, 00:50); en las Sigma, generador actualizado el 28/10 | Hecho en Suricata; en Sigma falta desplegar |
| La misma IP generó una segunda propuesta **después de estar baneada**, y se aprobó de nuevo | Antes de proponer, consultar si la IP ya está baneada (`fail2ban-client get <jail> banned <IP>` por el usuario `soar`) | Backlog |
| La decisión humana tardó minutos | Aceptable para un lab con un solo operador; en un SOC con turnos sería una métrica a vigilar | - |

## 11. Evidencia

`evidencia-lab/13-suricata-ids/`:

- `08_telegram-atacante-real-16.5.0.223-propuesta.png`
- `09_telegram-ban-ejecutado-16.5.0.223.png`
- `10_i3-fail2ban-soar-16.5.0.223-baneada.png`
- `01_kali-nmap-sS-999-filtrados-solo-22.png` (respaldo de §7)
