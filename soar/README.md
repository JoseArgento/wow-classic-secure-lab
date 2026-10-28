# soar/: n8n + Postgres (respuesta con aprobación humana)

Corre en la VM `ai-lab` (192.168.1.54), en la PC principal.

```
soar/
├── docker-compose.yml   # n8n 2.28.3 + postgres 16, fijados por digest
├── .env.example         # -> .env (no se commitea)
├── sql/                 # esquema de la tabla verdicts (primer arranque)
└── workflows/           # export de los workflows (sin credenciales)
```

## Flujo

```
Grafana ──webhook──▶ Filter ──▶ Buscar Veredicto (Postgres)
                                   │
                    ┌── cache hit ─┴─ cache miss ──┐
                    ▼                              ▼
              Set/Edit Fields            AI Agent (Groq, gpt-oss-120b)
                    │                     tools: AbuseIPDB, WHOIS/RDAP, VirusTotal
                    │                              │
                    │                     Guardar veredicto (Postgres)
                    └──────────────┬───────────────┘
                                   ▼
                     Telegram: veredicto (siempre)
                                   │
                  IF ¿Proponer ban?  (VEREDICTO Malicioso  OR  severidad high)
                                   │
                  IF ¿IP pública?    (no RFC1918 / loopback / link-local / CGNAT)
                                   │
                  Telegram: PROPUESTA DE BAN  [Ignorar] [Banear]   ◀── humano
                                   │
                  IF ¿Aprobado? ─▶ IF ¿IP válida? ─▶ SSH soar@i3: soar-ban.sh <ip> <tier>
                                                         │
                                                  Telegram: resultado
```

## Decisiones de diseño

- **Human in the loop.** El LLM recomienda; nunca ejecuta. El ban corre solo
  después de que una persona aprieta "Banear" en Telegram.
- **La propuesta no depende solo del modelo.** Se ofrece si el veredicto es
  Malicioso **o** si la regla Sigma es de severidad high: un modelo que
  subestima un ataque confirmado (lockout, crash de sshd) no lo silencia.
- **IPs internas: sin botón.** Una alerta desde la LAN llega con su
  veredicto, pero el ban automático por IP no sirve contra un atacante
  interno (cambia de IP, o es un equipo propio). Esa respuesta es manual.
- **Defensa en profundidad para el ban.** La IP se valida tres veces: antes
  de proponer (`IF ¿IP pública?`), después de aprobar (`IF ¿IP válida?`) y
  en el i3 (`soar-ban.sh` rechaza privadas, reservadas y multicast; sudo
  solo permite ese script; la clave SSH solo funciona desde esta VM).
- **Cache de veredictos.** Una IP ya evaluada no vuelve a consultar APIs ni
  al LLM. Se vacía al cambiar de modelo o de prompt: el veredicto viejo lo
  hizo otro "analista" con otras instrucciones (oct 2026: de
  llama-3.3-70b, dado de baja por Groq, a gpt-oss-120b).
- **Ninguna falla queda en silencio.** El workflow `SOAR - errores` (Error
  Trigger + Telegram) está configurado como *Error Workflow* del SOAR: si una
  ejecución falla (límite de tokens del LLM, Postgres caído, SSH rechazado),
  llega un aviso con el nodo, el error y el link a la ejecución.

## Credenciales (en n8n, no en git)

| Uso | Tipo en n8n |
|---|---|
| Groq | Groq API |
| AbuseIPDB, VirusTotal | Header Auth |
| Cache de veredictos | Postgres (host `postgres`, usuario/base `soar`) |
| Telegram | Telegram API |
| `Soar@i3` | SSH con clave privada (usuario `soar` en 192.168.1.66) |

n8n las guarda cifradas en `n8n_data`, con una clave que está en
`/home/node/.n8n/config`. **Quien tenga ese archivo y la base de n8n tiene
todas las credenciales**: los respaldos de `n8n_data` se tratan como un
secreto (fuera de git y de OneDrive).

## Despliegue

```bash
cp .env.example .env            # completar POSTGRES_PASSWORD
docker compose config -q        # valida el compose y el .env
docker compose up -d
docker compose exec n8n n8n import:workflow --separate --input=/home/node/.n8n/workflows
```
(antes de importar: `docker compose cp workflows n8n:/home/node/.n8n/workflows`)

Después: crear las credenciales de la tabla, asignarlas en los nodos y
activar el workflow.

## Respaldo

```bash
docker compose cp n8n:/home/node/.n8n ./n8n-backup                    # workflows, credenciales, clave
docker compose exec -T postgres pg_dump -U soar -d soar > verdicts-$(date +%F).sql
```

## Deuda conocida

- El workflow procesa solo `alerts[0]`: si Grafana agrupa dos alertas en un
  mismo webhook, la segunda no se evalúa.
- El agente no recibe la línea del log, solo nombre de alerta, severidad y
  conteo: no puede citar cuántos intentos hubo.
- El 5678 queda abierto a toda la LAN (Docker se saltea ufw). Limitarlo a la
  VM de observabilidad requiere una regla en la cadena `DOCKER-USER`.
