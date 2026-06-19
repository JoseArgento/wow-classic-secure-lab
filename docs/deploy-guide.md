# 🏰 Deploying VMaNGOS (WoW Classic 1.12.1) on AWS EC2

**English** | [Español](deploy-guide.es.md)

### Deployment & hardening guide — Cybersecurity lab

> Private vanilla 1.12.1 (VMaNGOS) server on Docker, deployed and hardened on AWS
> EC2. Designed for a small population (5-8 players) and documented as an
> infrastructure / blue-team lab.
>
> This guide reflects the real deployment process, including the issues encountered
> and how they were solved (see the **Troubleshooting** section at the end).

---

## 📋 Architecture

| Component | Role | Technology / Port |
|---|---|---|
| `realmd` | Authentication & realm list | C++ (Docker image) · TCP **3724** |
| `mangosd` | World server (game logic) | C++ (Docker image) · TCP **8085** |
| `database` | Accounts, characters & world content | MariaDB (Docker image) · **internal network only** |

This uses the [`mserajnik/vmangos-deploy`](https://github.com/mserajnik/vmangos-deploy)
project, which provides **prebuilt Docker images** — the core is not compiled on the
instance, saving RAM, time and AWS credits.

---

## ✅ Prerequisites

1. **Verified WoW 1.12.1 (build 5875) client.** VMaNGOS extracts game content from an
   original client. Since copies come from unofficial sources, it must be verified
   before use (see [`evidence/binary-verification.md`](../evidence/binary-verification.md)).
2. **Docker Desktop** installed on the machine holding the client (for data extraction).
3. **AWS account** with EC2 access.

---

## 🖥️ Phase 1 — EC2 instance provisioning

Recommended region: **São Paulo (`sa-east-1`)** for latency from the Southern Cone.

| Parameter | Value |
|---|---|
| AMI | Ubuntu Server 24.04 LTS (x86_64) |
| Type | `t3.medium` (2 vCPU, 4 GB RAM) |
| Storage | 30 GB gp3 |
| Access | SSH key pair (`.pem`) |

### Security Group (the heart of hardening)

Principle: **expose only the bare minimum.**

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | **Your IP only** (`X.X.X.X/32`) | SSH administration |
| 3724 | TCP | `0.0.0.0/0` | Login (realmd) |
| 8085 | TCP | `0.0.0.0/0` | World (mangosd) |

> The database port (3306) is **never** included. The DB stays on Docker's internal network.

### Elastic IP

Assign an **Elastic IP** (static public address) to the instance. It's required so the
players' `realmlist` doesn't change every time the instance is stopped and started.

---

## 🔒 Phase 2 — OS hardening

Can be applied manually or with the [`scripts/hardening.sh`](../scripts/hardening.sh)
script (idempotent). Summary of controls:

```bash
sudo apt update && sudo apt upgrade -y
```

**SSH (drop-in config in `/etc/ssh/sshd_config.d/`):**

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

```bash
sudo sshd -t && sudo systemctl restart ssh
# Verify the EFFECTIVE config (don't trust a single file):
sudo sshd -T | grep -iE 'permitrootlogin|passwordauthentication|pubkeyauthentication'
```

**Host firewall (`ufw`) — defense in depth alongside the Security Group:**

```bash
sudo apt install ufw -y
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH admin'
sudo ufw allow 3724/tcp comment 'VMaNGOS realmd (login)'
sudo ufw allow 8085/tcp comment 'VMaNGOS mangosd (world)'
sudo ufw enable
```

**Brute-force mitigation (`fail2ban`):**

```bash
sudo apt install fail2ban -y
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

> **Golden rule:** after hardening SSH, open a **new session** in another terminal and
> confirm key-based access *before* closing the current one.

---

## 🐳 Phase 3 — Install Docker + Compose

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
sudo usermod -aG docker $USER   # log out and back in for this to take effect
```

Verify: `docker run hello-world`

---

## ⚙️ Phase 4 — Configure vmangos-deploy

```bash
cd ~
git clone https://github.com/mserajnik/vmangos-deploy.git
cd vmangos-deploy
cp ./config/mangosd.conf.example ./config/mangosd.conf
cp ./config/realmd.conf.example ./config/realmd.conf
cp ./compose.yaml.example ./compose.yaml
```

### 4.1 — Edit `compose.yaml`

In the **`database`** service:

```yaml
- TZ=America/Argentina/Cordoba
- MARIADB_PASSWORD=<STRONG_PASSWORD>          # application user's password
- MARIADB_ROOT_PASSWORD=<ANOTHER_STRONG_PASSWORD>
- VMANGOS_REALMLIST_NAME=<REALM_NAME>
- VMANGOS_REALMLIST_ADDRESS=<YOUR_ELASTIC_IP> # enables external connections
- VMANGOS_REALMLIST_TIMEZONE=4                # 4 = Latin America
```

In the **`realmd`** and **`mangosd`** services, match the time zone:

```yaml
- TZ=America/Argentina/Cordoba
```

> **What NOT to touch:** the image already ships as `:5875` (1.12.1 client); the
> `database` healthcheck's `start_period: 24h` is intentional (keeps the container in
> `starting` during initial DB creation); and `user: 1000:1000` is correct for
> Ubuntu's default user.

> ⚠️ **DB password constraints** (two critical points):
> 1. **They cannot be changed after first boot** via these variables. Set strong
>    passwords *before* the first `docker compose up`.
> 2. **Avoid special characters** like `#`, `;`, `"`, `'` or spaces. These passwords
>    are also written into the connection strings in the `.conf` files (next step),
>    where `;` is a field separator and `#` can start a comment — they break the parser.

### 4.2 — Sync credentials in the `.conf` files (key step)

The database password lives in **two places** that must match: the `compose.yaml`
**and** the connection strings in the configuration files.

In **`config/mangosd.conf`**, the `*Database.Info` lines use the format
`host;port;user;password;dbname`. Only the **fourth field** (the password) changes:

```
LoginDatabase.Info     = "database;3306;mangos;<PASSWORD>;realmd"
WorldDatabase.Info     = "database;3306;mangos;<PASSWORD>;mangos"
CharacterDatabase.Info = "database;3306;mangos;<PASSWORD>;characters"
LogsDatabase.Info      = "database;3306;mangos;<PASSWORD>;logs"
```

In **`config/realmd.conf`**, sync the same way:

```
LoginDatabase.Info = "database;3306;mangos;<PASSWORD>;realmd"
```

> The user (`mangos`) and the last field (each database's name) stay as they are.
> Only the **password** is unified with the `compose.yaml`'s `MARIADB_PASSWORD`.

---

## 📦 Phase 5 — Extract client data

VMaNGOS needs data derived from the client (`dbc`, `maps`, `vmaps`, `mmaps`).
**Recommended: extract locally** (not on the instance) to avoid burning CPU/credits.

On the machine with the client and Docker Desktop, from PowerShell:

```powershell
mkdir C:\vmangos-extract\client-data, C:\vmangos-extract\extracted-data
# Copy the verified client's contents (without Scan.dll) into client-data\
cd C:\vmangos-extract

docker run -i `
  -v "${PWD}\client-data:/opt/vmangos/storage/client-data" `
  -v "${PWD}\extracted-data:/opt/vmangos/storage/extracted-data" `
  --rm `
  ghcr.io/mserajnik/vmangos-server:5875 `
  extract-client-data
```

> On Windows/PowerShell, use the backtick (`` ` ``) for line continuation and `${PWD}`
> for the path; the `--user 1000:1000` (needed on Linux) is **not** used here.

> ⏳ Extraction takes a while — `mmaps` (pathfinding) are the slowest. Expected result:
> ~3 GB. The `dbc` files end up inside the build folder (`5875/dbc`).

---

## ⬆️ Phase 6 — Upload data to the instance

```bash
# On the EC2 instance:
mkdir -p ~/vmangos-deploy/storage/mangosd/extracted-data
```

```powershell
# On Windows (PowerShell), upload only extracted-data:
scp -r -i C:\path\your-key.pem C:\vmangos-extract\extracted-data\* `
  ubuntu@<YOUR_ELASTIC_IP>:~/vmangos-deploy/storage/mangosd/extracted-data/
```

Verify the real size on the EC2 instance (`mmaps` should be ~2 GB):

```bash
du -sh ~/vmangos-deploy/storage/mangosd/extracted-data/*
```

---

## ▶️ Phase 7 — Launch the server

```bash
cd ~/vmangos-deploy
docker compose up -d
docker compose logs -f mangosd
```

Initial database creation takes several minutes. **Do not interrupt the process.**
The server is ready when you see:

```
World initialized.
```

Check status and DB isolation:

```bash
docker compose ps
# The DB should show "3306/tcp" WITHOUT a 0.0.0.0 mapping (internal only).
```

---

## 👤 Phase 8 — Create accounts

```bash
docker compose attach mangosd
```

```
account create <NAME> <PASSWORD>
account set gmlevel <NAME> 3 -1     # 3 = administrator; -1 = all realms
```

Exit **without** stopping the container: `Ctrl+P` then `Ctrl+Q`.
For regular players, create the account without `account set gmlevel`.

---

## 🎮 Phase 9 — Connect the client

In the client folder, edit `realmlist.wtf`:

```
set realmlist <YOUR_ELASTIC_IP>
```

Distribute to each player: the verified client (without `Scan.dll`), the Elastic IP
for the `realmlist.wtf`, and their account credentials.

---

## 💰 Phase 10 — Operation & cost control

- **Stop when idle:** `docker compose down`, then `Stop` the instance from AWS (you
  stop paying for compute; only the EBS disk and Elastic IP persist).
- **Resume:** `Start` the instance + `docker compose up -d`. The static Elastic IP
  keeps the `realmlist` valid.
- **Backups:** enable the `database-backup` service (commented out in `compose.yaml`).

---

## 🧯 Troubleshooting

Real issues encountered during deployment and their resolution:

| Log symptom | Cause | Fix |
|---|---|---|
| `Access denied for user 'mangos'@... (using password: YES)` | The password in the `.conf` files doesn't match the compose `MARIADB_PASSWORD` | Sync the 4th field of **all** `*Database.Info` lines in `mangosd.conf` **and** `realmd.conf` |
| `Incorrectly formatted database connection string` | A special character in the password (e.g. `#`) breaks the parser, or a missing/extra field | Use a password without `#`, `;`, `"`, spaces; verify exactly 4 `;` (5 fields) inside the quotes |
| `mangosd` restarts or stays `unhealthy` at startup | Limited resources during DB creation | The `database` `start_period: 24h` already covers this; wait for `World initialized.` without interrupting |
| `grep` for `DatabaseInfo` returns nothing | The variable is `WorldDatabase.Info` (with a dot), not `WorldDatabaseInfo` | Search with `grep -i "Database.Info"` |

> 💡 If the DB password must change after first boot (not possible via variables),
> recreate the volume: `docker compose down -v`, adjust passwords in compose **and**
> the `.conf` files, then `docker compose up -d` again.

---

## 🛡️ Applied hardening checklist

- [x] Attack surface minimization (Security Group, 3 ports)
- [x] SSH hardening (key-only, no root, no password) — verified with `sshd -T`
- [x] Defense in depth (cloud + host firewall)
- [x] Brute-force mitigation (`fail2ban`)
- [x] Database isolation (no internet exposure)
- [x] Untrusted-software validation before execution (see binary-verification)

---

## 📚 Sources

- vmangos-deploy: https://github.com/mserajnik/vmangos-deploy
- VMaNGOS core: https://github.com/vmangos/core
- VMaNGOS wiki: https://github.com/vmangos/wiki

---

*Part of the cybersecurity lab — deployment and hardening of game-server infrastructure.*
