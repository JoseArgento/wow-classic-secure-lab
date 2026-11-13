# Almacén La Esquina — web de demostración para el Mini SOC

Sitio web de una PyME ficticia (un almacén de barrio) que hace de **workload**
para la extensión web del lab de Blue Team. Reemplaza al servidor de WoW como
fuente de telemetría: nginx registra cada pedido en JSON, Alloy lo manda a Loki,
y las reglas Sigma de la familia `web/` detectan los patrones hostiles.

## Decisión de diseño: telemetría realista, sin agujero real

La app **no es explotable de verdad**:

- El buscador usa consultas **parametrizadas** (SQLite). Un payload de SQLi no
  inyecta nada, pero el intento queda en el log de nginx.
- La descarga de archivos está acotada a un directorio con `send_from_directory`.
  Un `../../etc/passwd` devuelve 404; el intento queda en el log.
- La única cuenta es de demo y no protege nada sensible.

El objetivo de la tesis es validar **detección**, no explotación. Como el lab
corre en la red doméstica (el i3, LAN plana), un sitio genuinamente vulnerable
sería un riesgo real innecesario. Generar los **patrones de ataque** en el log
sin dejar un agujero explotable es la opción prolija, y es un buen punto de
"gaps documentados, no escondidos" para el informe. Si en algún momento quieren
practicar explotación de verdad, eso va en una VM aislada, no acá.

## Qué dispara cada detección

| Prueba del atacante | Qué ve nginx en el log | Regla |
|---|---|---|
| User-agent de sqlmap/nikto | `user_agent` con la firma | `web_scanner_user_agent` |
| gobuster/ffuf | ráfaga de `status: 404` por IP | `web_content_discovery` |
| Sondas a `/.env`, `/.git/`, backups | `uri` a esos paths, 404 | `web_sensitive_file_probe` |
| Fuerza bruta al login | POST a `/login` con `status: 401` | `web_login_bruteforce` |
| SQLi en el buscador | `UNION SELECT`, `' OR 1=1` en `uri` (codificados, ver abajo) | `web_sqli_attempt` |
| Path traversal | `../`, `/etc/passwd` en `uri` o en `request` | `web_path_traversal` |
| App caída (502/504) | salto de `status: 5xx` | `web_5xx_spike` |

### Cómo llega el payload al log (verificado)

`uri` es el pedido **tal cual lo mandó el cliente**, sin decodificar. Las
herramientas codifican, así que una regla que busque el texto "lindo" no ve
nada. Líneas reales:

| Lo que se tipea | Lo que queda en `uri` |
|---|---|
| `' UNION SELECT name,sql,1 FROM sqlite_master--` | `/productos?q=%27+UNION+SELECT+name%2csql%2c1+FROM+sqlite_master--` |
| `' OR 1=1--` | `/productos?q=%27+OR+1%3d1--` |
| `../../etc/passwd` (codificado) | `/descargas?file=..%2f..%2fetc%2fpasswd` |

Las reglas tienen que contemplar el espacio como `+` y `%20`, la comilla como
`%27`, y `../` como `..%2f` (mayúsculas y minúsculas).

Segundo caso: si el traversal va **en el path** (`/static/../../etc/passwd`,
`/cgi-bin/.%2e/.%2e/bin/sh`, lo típico de los bots), nginx lo rechaza con
`status: 400` y deja `uri` **vacío**. El intento solo se ve en el campo
`request` (la línea cruda del pedido). `web_path_traversal` tiene que mirar
los dos campos.

## Estructura

```
pyme-web/
├─ docker-compose.yml      # nginx (8080) + app (red interna)
├─ .env.example            # copiar a .env (no va a git)
├─ app/                    # Flask + gunicorn
│  ├─ app.py
│  ├─ Dockerfile
│  ├─ requirements.txt
│  ├─ templates/
│  └─ static/
├─ nginx/
│  ├─ nginx.conf           # log de acceso en JSON, límites
│  └─ conf.d/default.conf  # reverse proxy al backend, cabeceras
├─ ops/
│  └─ logrotate-laesquina  # rotación del log (se instala en el i3)
└─ logs/                   # lo crea Docker; acá vive acceso.json
```

## Cómo levantarlo (en el i3)

```bash
# En el i3, donde corre el workload
cd pyme-web
cp .env.example .env
# Completar APP_SECRET (comando en el .env.example) y DEMO_PASSWORD
nano .env
docker compose up -d --build
curl -sI http://localhost:8080        # 200 OK
```

Sin `.env` completo, `docker compose` se niega a arrancar y dice qué falta.

## Dónde está el log para Alloy

`./logs/acceso.json` en el host (bind mount de `/var/log/nginx` del
contenedor). Para que Alloy lo lea, montá esa carpeta de solo lectura en su
contenedor y apuntá un bloque `loki.source.file` a `acceso.json`.

Contrato de labels sugerido (a replicar en Alloy, en línea con el del journal):
`job=nginx`, `service=web`, `host=<nombre del i3>`. La IP, el método, el path y
el status **no** van como labels: se extraen del JSON en la query LogQL.

Campos de cada línea: `time`, `remote_addr`, `http_host`, `method`, `uri`,
`request`, `status`, `body_bytes`, `request_time`, `upstream_status`,
`user_agent`, `referer`.

Rotación: instalar `ops/logrotate-laesquina` en el i3 (instrucciones adentro).

## Prueba rápida de que loguea bien

```bash
# En el i3: generá un 404 y miralo en el log
curl -s http://localhost:8080/.env -o /dev/null
tail -n 1 logs/acceso.json
```

Ojo: un `curl` hecho desde el mismo i3 aparece con la IP del gateway de Docker
(`172.x.x.1`), no con `127.0.0.1`. Las pruebas que cuentan se hacen desde otra
máquina.

## Credencial de demo

Usuario `admin`; la contraseña es `DEMO_PASSWORD` del `.env` y se le pasa al
grupo por privado. Sirve para la prueba negativa: login exitoso, que NO debe
alertar.

## Endurecimiento del despliegue

| Control | Dónde | Para qué |
|---|---|---|
| Clave de sesión y contraseña fuera del repo | `.env` | Con la clave conocida se puede firmar una cookie y entrar a `/admin` sin pasar por `/login` |
| App sin salida de red | red `backend` interna | Si alguien ejecutara código en la app, no llega a la LAN ni a internet |
| Solo lectura, sin capabilities, `no-new-privileges` | compose | Menos margen para persistir o escalar |
| nginx en rama con soporte, fijado por digest | `nginx:1.30-alpine@sha256:…` | La 1.27 ya no recibe parches |
| El contenedor expuesto no inicia conexiones | `DOCKER-USER` en el i3 (`i3/docker-user/`) | Si alguien ejecutara código en nginx, no llega a la LAN ni a internet, y el intento queda en el journal |
| Cabeceras (CSP, nosniff, frame, referrer) y cookie `SameSite=Lax` | nginx / Flask | Higiene básica de un sitio público |
| Cuerpo máximo 16k y timeouts cortos | `nginx.conf` | Conexiones lentas y cuerpos enormes |
| Rotación del log | `ops/logrotate-laesquina` | Que los bots no llenen el disco |

Gaps a propósito, para documentar en el informe:

- **Sin rate limiting.** Frenaría la fuerza bruta y el descubrimiento de
  contenido antes de que dejen el patrón que las reglas tienen que ver. La
  respuesta es del SOC (alerta, triage, ban), no del servidor web.
- **Sin HTTPS** mientras se sirva por HTTP plano: la contraseña de demo viaja
  en claro. No protege nada, pero no hay que reusarla en ningún otro lado.
- **El aislamiento de nginx no está en este compose.** Lo hace el host con la
  cadena `DOCKER-USER`: sin esas reglas instaladas, el contenedor de nginx ve
  la LAN.

## Exposición a internet

Se publica por port forwarding del router (TCP 8080) con el DDNS que ya usa el
lab. La decisión, las alternativas y las condiciones están en
[`docs/adr/ADR-002-exponer-pyme-web.md`](../docs/adr/ADR-002-exponer-pyme-web.md).

Antes de abrir el puerto, en este orden:

1. Reglas `DOCKER-USER` instaladas y probadas (`i3/README.md`).
2. i3 actualizado y reiniciado, con las defensas arriba después del reinicio.
3. Rotación del log instalada (`ops/logrotate-laesquina`).
4. Circuito alerta -> triage -> ban probado con una IP de prueba.

Con port forwarding directo `remote_addr` es la IP real del visitante y no
hace falta tocar nada. Si algún día queda detrás de un túnel o proxy, hay que
configurar la IP real en `nginx/conf.d/default.conf` (está comentado ahí) o
todas las detecciones por IP van a ver una sola dirección.
