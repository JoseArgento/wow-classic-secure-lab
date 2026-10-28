# IR-03: El SOC dejó de ver o de responder

**Alcance:**

| Mensaje | Qué significa |
|---|---|
| 🚨 *Dead man's switch - i3 sin latido* | Loki no recibe nada del i3 hace más de 5 min |
| *Linux Security Service Stopped* | Se detuvo fail2ban, ssh o ufw en el i3 |
| 🔥 *SOAR FALLÓ* | Una ejecución de n8n terminó con error: esa alerta no se evaluó |

Un SOC ciego es un incidente en sí mismo: un atacante con privilegios apaga
las defensas antes de actuar (MITRE ATT&CK v19: T1685, *Defense Impairment*).
Hasta demostrar lo contrario, **se asume que no es casual**.

## 1. Análisis: dónde se cortó

**Sin latido**, revisar en orden y parar en el primer eslabón roto:

| # | Eslabón | Chequeo |
|---|---|---|
| 1 | El i3 está prendido y con red | `ssh i3` |
| 2 | Alloy corre | En el i3: `cd ~/alloy && docker compose ps` |
| 3 | El túnel está arriba | En el i3: `ss -tln \| grep 3100`, en observabilidad: `systemctl status loki-tunnel` |
| 4 | Loki responde | En observabilidad: `docker compose ps` en el stack |

**Servicio de seguridad detenido**: ¿fue un reinicio? Si el mensaje coincide
con un reinicio del i3, es un verdadero positivo benigno (en el i3):

```bash
journalctl --list-boots | tail -2
journalctl -u fail2ban -u ssh -u ufw --since "-30min" --no-pager | tail -20
last -x | head -5
```

Si no hubo reinicio: **¿quién lo detuvo?** (`journalctl _COMM=systemctl --since "-30min"`, `last`).

**SOAR falló**: abrir el link de la ejecución que trae el mensaje y leer el
error del nodo. Causas conocidas:

| Error | Causa | Qué hacer |
|---|---|---|
| *too many requests* (Groq) | Límite de 8K tokens/min del plan gratuito | La alerta quedó sin evaluar: triage manual con IR-01 |
| *decommissioned* (Groq) | Modelo dado de baja | Cambiar de modelo en *Groq Chat Model* |
| Error de Postgres / SSH | Servicio caído o credencial | Revisar `ai-lab` y el i3 |

## 2. Contención y recuperación

Restaurar el eslabón roto. Después, **revisar a mano el período ciego**:
el i3 conserva todo localmente aunque el SOC no lo haya visto (en el i3):

```bash
journalctl --since "<inicio del corte>" --until "<fin>" -p warning --no-pager
sudo zgrep -h '"event_type":"alert"' /var/log/suricata/eve.json* | grep '"timestamp":"<AAAA-MM-DDTHH>'
sudo fail2ban-client status sshd
```

Si hubo un servicio detenido sin explicación: tratarlo como posible
compromiso del host (IR-01, §4).

## 3. Post-incidente

Informe siempre, salvo un reinicio planificado. Anotar cuánto duró el período
ciego y qué se habría perdido sin el almacenamiento local del i3.
