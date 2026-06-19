# 🏰 Despliegue de VMaNGOS (WoW Classic 1.12.1) en AWS EC2

[English](deploy-guide.md) | **Español**

### Guía de despliegue y hardening — Laboratorio de ciberseguridad

> Servidor privado vanilla 1.12.1 (VMaNGOS) sobre Docker, desplegado y endurecido en
> AWS EC2. Pensado para una población chica (5-8 jugadores) y documentado como
> laboratorio de infraestructura y blue team.
>
> Esta guía refleja el proceso real de despliegue, incluyendo los problemas
> encontrados y su resolución (ver la sección **Troubleshooting** al final).

---

## 📋 Arquitectura

| Componente | Rol | Tecnología / Puerto |
|---|---|---|
| `realmd` | Autenticación y lista de realms | C++ (imagen Docker) · TCP **3724** |
| `mangosd` | Servidor de mundo (lógica del juego) | C++ (imagen Docker) · TCP **8085** |
| `database` | Cuentas, personajes y contenido del mundo | MariaDB (imagen Docker) · **solo red interna** |

Se utiliza el proyecto [`mserajnik/vmangos-deploy`](https://github.com/mserajnik/vmangos-deploy),
que provee **imágenes Docker precompiladas** — no se compila el core en la instancia,
lo que ahorra RAM, tiempo y créditos de AWS.

---

## ✅ Prerrequisitos

1. **Cliente WoW 1.12.1 (build 5875) verificado.** VMaNGOS extrae el contenido del
   juego de un cliente original. Como las copias provienen de fuentes no oficiales,
   debe verificarse antes de usar (ver [`evidence/binary-verification.es.md`](../evidence/binary-verification.es.md)).
2. **Docker Desktop** instalado en el equipo donde está el cliente (para la extracción de datos).
3. **Cuenta de AWS** con acceso a EC2.

---

## 🖥️ Fase 1 — Provisión de la instancia EC2

Región recomendada: **São Paulo (`sa-east-1`)** por latencia desde el Cono Sur.

| Parámetro | Valor |
|---|---|
| AMI | Ubuntu Server 24.04 LTS (x86_64) |
| Tipo | `t3.medium` (2 vCPU, 4 GB RAM) |
| Almacenamiento | 30 GB gp3 |
| Acceso | Par de claves SSH (`.pem`) |

### Security Group (corazón del hardening)

Principio: **exponer solo lo mínimo indispensable.**

| Puerto | Protocolo | Origen | Propósito |
|---|---|---|---|
| 22 | TCP | **Solo tu IP** (`X.X.X.X/32`) | Administración SSH |
| 3724 | TCP | `0.0.0.0/0` | Login (realmd) |
| 8085 | TCP | `0.0.0.0/0` | Mundo (mangosd) |

> El puerto de la base de datos (3306) **nunca** se incluye. La DB permanece en la red interna de Docker.

### Elastic IP

Asignar una **Elastic IP** (dirección pública fija) a la instancia. Es necesaria para
que el `realmlist` de los jugadores no cambie cada vez que la instancia se detiene e inicia.

---

## 🔒 Fase 2 — Hardening del sistema operativo

Puede aplicarse manualmente o con el script [`scripts/hardening.sh`](../scripts/hardening.sh)
(idempotente). Resumen de controles:

```bash
sudo apt update && sudo apt upgrade -y
```

**SSH (config drop-in en `/etc/ssh/sshd_config.d/`):**

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

```bash
sudo sshd -t && sudo systemctl restart ssh
# Verificar la config EFECTIVA (no confiar en un solo archivo):
sudo sshd -T | grep -iE 'permitrootlogin|passwordauthentication|pubkeyauthentication'
```

**Firewall de host (`ufw`) — defensa en profundidad junto al Security Group:**

```bash
sudo apt install ufw -y
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH admin'
sudo ufw allow 3724/tcp comment 'VMaNGOS realmd (login)'
sudo ufw allow 8085/tcp comment 'VMaNGOS mangosd (world)'
sudo ufw enable
```

**Mitigación de fuerza bruta (`fail2ban`):**

```bash
sudo apt install fail2ban -y
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

> **Regla de oro:** tras endurecer SSH, abrir una **sesión nueva** en otra terminal
> y confirmar el acceso por clave *antes* de cerrar la sesión actual.

---

## 🐳 Fase 3 — Instalar Docker + Compose

```bash
sudo apt install -y ca-certificates curl gnupg git
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER   # cerrar y reabrir la sesión SSH para que tome efecto
```

Verificar: `docker run hello-world`

---

## ⚙️ Fase 4 — Configurar vmangos-deploy

```bash
cd ~
git clone https://github.com/mserajnik/vmangos-deploy.git
cd vmangos-deploy
cp ./config/mangosd.conf.example ./config/mangosd.conf
cp ./config/realmd.conf.example ./config/realmd.conf
cp ./compose.yaml.example ./compose.yaml
```

### 4.1 — Editar `compose.yaml`

En el servicio **`database`**:

```yaml
- TZ=America/Argentina/Cordoba
- MARIADB_PASSWORD=<PASSWORD_FUERTE>          # password del usuario de la aplicación
- MARIADB_ROOT_PASSWORD=<OTRO_PASSWORD_FUERTE>
- VMANGOS_REALMLIST_NAME=<NOMBRE_DEL_REALM>
- VMANGOS_REALMLIST_ADDRESS=<TU_ELASTIC_IP>   # permite conexiones externas
- VMANGOS_REALMLIST_TIMEZONE=4                # 4 = Latin America
```

En los servicios **`realmd`** y **`mangosd`**, igualar la zona horaria:

```yaml
- TZ=America/Argentina/Cordoba
```

> **Lo que NO hay que tocar:** la imagen ya viene en `:5875` (cliente 1.12.1); el
> `start_period: 24h` del healthcheck del `database` es intencional (mantiene el
> contenedor en `starting` durante la creación inicial); y `user: 1000:1000` es
> correcto para el usuario por defecto de Ubuntu.

> ⚠️ **Restricciones del password de la DB** (dos puntos críticos):
> 1. **No se puede cambiar después del primer arranque** vía estas variables. Definir
>    passwords fuertes *antes* del primer `docker compose up`.
> 2. **Evitar caracteres especiales** como `#`, `;`, `"`, `'` o espacios. Estos passwords
>    también se escriben en las cadenas de conexión de los `.conf` (siguiente paso),
>    donde `;` es separador de campos y `#` puede iniciar un comentario — rompen el parser.

### 4.2 — Sincronizar credenciales en los `.conf` (paso clave)

El password de la base vive en **dos lugares** que deben coincidir: el `compose.yaml`
**y** las cadenas de conexión de los archivos de configuración.

En **`config/mangosd.conf`**, las líneas `*Database.Info` usan el formato
`host;puerto;usuario;password;basededatos`. Solo cambia el **cuarto campo** (el password):

```
LoginDatabase.Info     = "database;3306;mangos;<PASSWORD>;realmd"
WorldDatabase.Info     = "database;3306;mangos;<PASSWORD>;mangos"
CharacterDatabase.Info = "database;3306;mangos;<PASSWORD>;characters"
LogsDatabase.Info      = "database;3306;mangos;<PASSWORD>;logs"
```

En **`config/realmd.conf`**, sincronizar igual:

```
LoginDatabase.Info = "database;3306;mangos;<PASSWORD>;realmd"
```

> El usuario (`mangos`) y el último campo (nombre de cada base) se mantienen.
> Solo se unifica el **password** con el `MARIADB_PASSWORD` del `compose.yaml`.

---

## 📦 Fase 5 — Extraer los datos del cliente

VMaNGOS necesita datos derivados del cliente (`dbc`, `maps`, `vmaps`, `mmaps`).
**Recomendado: extraer en local** (no en la instancia) para no consumir CPU/créditos.

En el equipo con el cliente y Docker Desktop, desde PowerShell:

```powershell
mkdir C:\vmangos-extract\client-data, C:\vmangos-extract\extracted-data
# Copiar el contenido del cliente verificado (sin Scan.dll) a client-data\
cd C:\vmangos-extract

docker run -i `
  -v "${PWD}\client-data:/opt/vmangos/storage/client-data" `
  -v "${PWD}\extracted-data:/opt/vmangos/storage/extracted-data" `
  --rm `
  ghcr.io/mserajnik/vmangos-server:5875 `
  extract-client-data
```

> En Windows/PowerShell se usa el backtick (`` ` ``) como continuación de línea y
> `${PWD}` para la ruta; el `--user 1000:1000` (necesario en Linux) **no** se usa aquí.

> ⏳ La extracción tarda — las `mmaps` (pathfinding) son las más lentas. Resultado
> esperado: ~3 GB. Los `dbc` quedan dentro de la carpeta de build (`5875/dbc`).

---

## ⬆️ Fase 6 — Subir los datos a la instancia

```bash
# En la EC2:
mkdir -p ~/vmangos-deploy/storage/mangosd/extracted-data
```

```powershell
# En Windows (PowerShell), subir solo extracted-data:
scp -r -i C:\ruta\tu-clave.pem C:\vmangos-extract\extracted-data\* `
  ubuntu@<TU_ELASTIC_IP>:~/vmangos-deploy/storage/mangosd/extracted-data/
```

Verificar el tamaño real en la EC2 (las `mmaps` deben pesar ~2 GB):

```bash
du -sh ~/vmangos-deploy/storage/mangosd/extracted-data/*
```

---

## ▶️ Fase 7 — Levantar el servidor

```bash
cd ~/vmangos-deploy
docker compose up -d
docker compose logs -f mangosd
```

La creación inicial de la base tarda varios minutos. **No interrumpir el proceso.**
El servidor está listo cuando aparece:

```
World initialized.
```

Verificar el estado y el aislamiento de la DB:

```bash
docker compose ps
# La DB debe mostrar "3306/tcp" SIN un mapeo 0.0.0.0 (solo interna).
```

---

## 👤 Fase 8 — Crear cuentas

```bash
docker compose attach mangosd
```

```
account create <NOMBRE> <PASSWORD>
account set gmlevel <NOMBRE> 3 -1     # 3 = administrador; -1 = todos los realms
```

Salir **sin** detener el contenedor: `Ctrl+P` y luego `Ctrl+Q`.
Para jugadores normales, crear la cuenta sin el `account set gmlevel`.

---

## 🎮 Fase 9 — Conectar el cliente

En la carpeta del cliente, editar `realmlist.wtf`:

```
set realmlist <TU_ELASTIC_IP>
```

Distribuir a cada jugador: el cliente verificado (sin `Scan.dll`), la Elastic IP para
el `realmlist.wtf`, y sus credenciales de cuenta.

---

## 💰 Fase 10 — Operación y control de costos

- **Detener cuando no se usa:** `docker compose down`, luego `Stop` de la instancia
  desde AWS (se deja de pagar compute; solo persisten el disco EBS y la Elastic IP).
- **Reanudar:** `Start` de la instancia + `docker compose up -d`. La Elastic IP fija
  mantiene el `realmlist` válido.
- **Backups:** activar el servicio `database-backup` (comentado en `compose.yaml`).

---

## 🧯 Troubleshooting

Problemas reales encontrados durante el despliegue y su resolución:

| Síntoma en los logs | Causa | Solución |
|---|---|---|
| `Access denied for user 'mangos'@... (using password: YES)` | El password en los `.conf` no coincide con el `MARIADB_PASSWORD` del compose | Sincronizar el 4.º campo de **todas** las líneas `*Database.Info` en `mangosd.conf` **y** `realmd.conf` |
| `Incorrectly formatted database connection string` | Caracter especial en el password (ej. `#`) que rompe el parser, o un campo faltante/sobrante | Usar un password sin `#`, `;`, `"`, espacios; verificar que haya exactamente 4 `;` (5 campos) entre comillas |
| `mangosd` reinicia o queda `unhealthy` al inicio | Recursos limitados durante la creación de la DB | El `start_period: 24h` del `database` ya lo cubre; esperar a `World initialized.` sin interrumpir |
| El `grep` de `DatabaseInfo` no devuelve nada | La variable es `WorldDatabase.Info` (con punto), no `WorldDatabaseInfo` | Buscar con `grep -i "Database.Info"` |

> 💡 Si hay que cambiar el password de la DB después del primer arranque (no se puede
> vía variables), recrear el volumen: `docker compose down -v`, ajustar passwords en
> compose **y** en los `.conf`, y `docker compose up -d` de nuevo.

---

## 🛡️ Checklist de hardening aplicado

- [x] Minimización de superficie de ataque (Security Group, 3 puertos)
- [x] SSH endurecido (solo clave, sin root, sin password) — verificado con `sshd -T`
- [x] Defensa en profundidad (firewall cloud + host)
- [x] Mitigación de fuerza bruta (`fail2ban`)
- [x] Aislamiento de la base de datos (sin exposición a internet)
- [x] Validación de software no confiable previo a su ejecución (ver binary-verification)

---

## 📚 Fuentes

- vmangos-deploy: https://github.com/mserajnik/vmangos-deploy
- VMaNGOS core: https://github.com/vmangos/core
- Wiki de VMaNGOS: https://github.com/vmangos/wiki

---

*Parte del lab de ciberseguridad — despliegue y hardening de infraestructura de servidor de juego.*
