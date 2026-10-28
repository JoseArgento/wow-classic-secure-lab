# Respuesta a incidentes (docs/ir)

Playbooks, plantilla e informes del Mini SOC. Marco: **NIST SP 800-61 Rev. 3**
(abril 2025, perfil de comunidad de CSF 2.0), que reemplaza a la Rev. 2 de 2012.
La Rev. 3 ya no plantea un ciclo propio: ubica la respuesta a incidentes dentro
de las funciones de CSF 2.0. En este lab:

| Función CSF 2.0 | Qué es acá |
|---|---|
| **Govern / Identify / Protect** (preparación) | Hardening del i3, ufw, SSH solo clave, sysctl, reglas Sigma, firmas, este directorio |
| **Detect** (DE.CM, DE.AE) | Alloy -> Loki -> Grafana; Suricata; dead man's switch |
| **Respond** (RS.MA, RS.AN, RS.MI, RS.CO) | n8n (triage con LLM) -> Telegram -> humano -> `soar-ban.sh` |
| **Recover** (RC.RP) | Unban automático por tier, restauración de servicios, verificación |
| **Identify -> Improvement** (ID.IM) | Informe del incidente y acciones (reglas, tuning, prompt) |

Para quien venga de la Rev. 2, las fases clásicas siguen sirviendo de guía
dentro de cada playbook: preparación, detección y análisis, contención,
erradicación y recuperación, actividad post-incidente.

## Contenido

| Archivo | Para qué |
|---|---|
| [`IR-01-ip-externa-hostil.md`](IR-01-ip-externa-hostil.md) | Alertas con IP pública: fuerza bruta, lockout, escaneo, reputación |
| [`IR-02-actividad-hostil-lan.md`](IR-02-actividad-hostil-lan.md) | Alertas con IP de la LAN (sin ban automático) |
| [`IR-03-soc-ciego.md`](IR-03-soc-ciego.md) | El SOC dejó de ver o de responder |
| [`plantilla-informe.md`](plantilla-informe.md) | Plantilla de informe de incidente |
| [`informes/`](informes/) | Informes reales (`INC-AAAA-NNN-*.md`) |

## Qué playbook según el mensaje de Telegram

| Mensaje | Playbook |
|---|---|
| Veredicto con IP pública (con o sin PROPUESTA DE BAN) | IR-01 |
| Veredicto con IP 192.168.x / 10.x / 172.16-31.x (sin botón) | IR-02 |
| 🚨 Dead man's switch, Security Service Stopped, 🔥 SOAR FALLÓ | IR-03 |
| Linux Local Account Created | IR-02 (actividad en el host) |

## Cuándo se escribe un informe

Siempre que haya una **acción de respuesta** (ban aprobado, servicio
restaurado, cuenta bloqueada), un **patrón nuevo** o una **falla del SOC**.
Un bot más con el mismo patrón y ban automático no necesita informe: queda en
Loki, en la auditoría de `soar-ban` y en el historial de n8n.

Numeración: `INC-<año>-<NNN>`, correlativa por año.
