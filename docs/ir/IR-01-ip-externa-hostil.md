# IR-01: IP externa hostil

**Alcance:** alertas cuyo IOC es una IP **pública**.

| Origen | Reglas |
|---|---|
| Sigma (Loki) | VMaNGOS Wrong Password, VMaNGOS IP Lockout, SSH Brute Force, SSH Preauth Disconnect, SSH Penalty Caused Crash |
| Suricata | Suricata IDS - prioridad alta (1), prioridad media (2) |

**Rol:** un solo operador hace de analista y de responsable. Toda acción de
contención la aprueba él (human in the loop).

---

## 1. Preparación (lo que tiene que estar antes)

- Grafana con las reglas cargadas, n8n activo, bot de Telegram respondiendo.
- `soar-ban.sh` en el i3 y el usuario `soar` con su clave restringida.
- Este playbook y la plantilla de informe a mano.

## 2. Detección y análisis

Llega a Telegram un **veredicto** (siempre) y, si corresponde, una
**PROPUESTA DE BAN**. Antes de decidir, responder estas preguntas. La mayoría
se contestan con el propio mensaje; el resto, con las consultas de abajo.

| # | Pregunta | Dónde |
|---|---|---|
| 1 | ¿La IP es pública? (si no -> IR-02) | Mensaje (IOC) |
| 2 | ¿Qué detectó, exactamente? (regla y, si es Suricata, la firma) | Mensaje (Alerta, CONTEXTO) |
| 3 | ¿Cuántos eventos y desde cuándo? | Grafana, consulta A |
| 4 | ¿Contra qué servicio y puerto? ¿Estaba prendido? | Consulta B, `docker ps` en el i3 |
| 5 | **¿Hubo algún acceso exitoso desde esa IP?** | Consulta C |
| 6 | ¿Reputación? (AbuseIPDB, VirusTotal, dueño de la red) | Mensaje (SCORE, VT, CONTEXTO) |
| 7 | ¿El veredicto del LLM es coherente con 2-6? | Juicio del analista |

La pregunta 5 es la que cambia todo: **si hubo acceso exitoso, deja de ser un
escaneo y pasa a ser una cuenta comprometida** (ver §4, Erradicación).

**Consultas (en Grafana, Explore, ventana de 24 h):**

```logql
# A. Todo lo que hizo esa IP, de cualquier fuente
{host="i3"} |= "<IP>"

# B. Alertas de Suricata de esa IP, con firma y puerto
{job="suricata"} | json ip="src_ip", sig="alert.signature", puerto="dest_port" | ip = "<IP>"

# C. ¿Algún login exitoso? (SSH y WoW)
{job="systemd-journal", host="i3"} |~ "Accepted (publickey|password) for .* from <IP>"
{job="vmangos", service="realmd"} |= "<IP>"
# -> leer las líneas: cualquier cosa que no sea contraseña errónea o lockout es un acceso
```

**En el i3, si hace falta el detalle completo de la red:**

```bash
sudo zgrep -h '"src_ip":"<IP>"' /var/log/suricata/eve.json* | grep '"event_type":"alert"'
```

## 3. Contención

| Situación | Acción |
|---|---|
| Malicioso, o regla de severidad **high** | **Banear** desde Telegram (el tier lo propone el SOAR) |
| Sospechoso, sin acceso exitoso | Banear tier *short* si el patrón se repite; si no, monitorear |
| **Benigno pero regla medium/high** | **No confiar ciegamente**: revisar a mano (lección INC del 28/10: un escaneo real salió Benigno porque el agente no tenía la firma) |
| Acceso exitoso confirmado | Banear tier *severe* **y** seguir con Erradicación |

Ban manual, si Telegram o n8n no están disponibles (en el i3):

```bash
sudo /usr/local/bin/soar-ban.sh <IP> short      # o severe
```

Verificar la contención (en el i3):

```bash
sudo fail2ban-client status soar           # o soar-severe
sudo nft list chain inet f2b-table f2b-chain | grep <IP>
journalctl -t soar-ban --since "-15min" --no-pager
```

## 4. Erradicación

- **Escaneo o fuerza bruta sin acceso**: no hay nada que erradicar. El ban
  y el registro alcanzan.
- **Acceso exitoso a una cuenta de WoW**: cambiar la contraseña de la cuenta
  desde la consola de mangosd (`account set password <cuenta> <nueva> <nueva>`),
  revisar sus personajes, y buscar otras IPs que hayan usado esa cuenta.
- **Acceso exitoso por SSH**: tratarlo como compromiso del host. Revisar
  `~/.ssh/authorized_keys` de todos los usuarios, `last`, `journalctl -u ssh`,
  procesos y crontabs; rotar claves. Evaluar reinstalar desde la receta en git.

## 5. Recuperación

- El ban se levanta solo (short: 1 h, severe: 3 días).
- **Falso positivo** (en el i3):
  `sudo fail2ban-client set soar unbanip <IP>` (o `soar-severe`)
- Si hubo erradicación: verificar que el servicio vuelva a funcionar (login
  de prueba) y que las alertas de esa IP se resuelvan en Grafana.

## 6. Post-incidente

- ¿Corresponde informe? Ver `README.md` -> "Cuándo se escribe un informe".
  Si sí: copiar `plantilla-informe.md` a `informes/INC-<año>-<NNN>-<resumen>.md`.
- Medir y anotar: **detección** (evento -> Telegram), **decisión** (Telegram ->
  respuesta humana) y **contención** (aprobación -> "Ban ejecutado").
- Preguntarse qué mejorar: una regla nueva, un tuning, un cambio de prompt.

## Evidencia a guardar

- Captura del veredicto y de la propuesta en Telegram.
- ID de la ejecución de n8n.
- Salida de `fail2ban-client status` y de `journalctl -t soar-ban`.
- Consultas A-C exportadas (Grafana -> Inspector -> Data -> Download CSV).
- Las líneas de `eve.json`, si la fuente fue Suricata.
