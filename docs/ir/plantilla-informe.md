# INC-AAAA-NNN: <título corto: qué pasó, contra qué>

| Campo | Valor |
|---|---|
| **Estado** | Abierto / Contenido / Cerrado |
| **Severidad** | Baja / Media / Alta / Crítica |
| **Clasificación** | Escaneo, Fuerza bruta, Acceso no autorizado, Pérdida de visibilidad, Otro |
| **Playbook** | IR-01 / IR-02 / IR-03 |
| **Detectado** | AAAA-MM-DD HH:MM (hora de Argentina) |
| **Cerrado** | AAAA-MM-DD HH:MM |
| **Analista** | |

## 1. Resumen

Tres a cinco renglones: qué pasó, cómo se detectó, qué se hizo y cuál fue el
impacto. Tiene que entenderse sin leer el resto.

## 2. Línea de tiempo

| Hora | Fuente | Evento |
|---|---|---|
| | Suricata / Loki / n8n / Telegram / fail2ban | |

## 3. Detección

- **Fuente y regla:**
- **Firma o patrón:**
- **Activo:** host, servicio, puerto, ¿estaba en servicio?

## 4. Indicadores (IOCs)

| Tipo | Valor | Notas |
|---|---|---|
| IP | | |

## 5. Análisis y enriquecimiento

| Fuente | Resultado |
|---|---|
| AbuseIPDB | |
| VirusTotal | |
| WHOIS / RDAP | |
| Veredicto del SOAR | |
| ¿Acceso exitoso? | Sí / No (con qué consulta se verificó) |

Juicio del analista: ¿el veredicto del LLM fue coherente con la evidencia?

## 6. Respuesta

| Acción | Hora | Quién / qué | Verificación |
|---|---|---|---|
| | | | |

## 7. Impacto

Qué se vio afectado y qué no, con la evidencia que lo respalda.

## 8. MITRE ATT&CK (v19)

| Táctica | Técnica | Justificación |
|---|---|---|
| | | |

## 9. Métricas

| Métrica | Tiempo |
|---|---|
| Detección (primer evento -> Telegram) | |
| Decisión (Telegram -> respuesta humana) | |
| Contención (aprobación -> "Ban ejecutado") | |

## 10. Lecciones y acciones

| Lección | Acción | Estado |
|---|---|---|
| | | |

## 11. Evidencia

Lista de capturas y archivos (con la ruta dentro de `evidencia-lab/`).
