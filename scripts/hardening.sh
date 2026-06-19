#!/usr/bin/env bash
# ===================================================================
#  hardening.sh  —  Base host hardening for the VMaNGOS lab (Ubuntu)
# ===================================================================
#  Aplica controles base de seguridad de forma IDEMPOTENTE
#  (podés correrlo varias veces sin romper nada):
#    1. Actualiza el sistema
#    2. Endurece SSH (key-only, sin root, sin password)
#    3. Configura el firewall del host (ufw)
#    4. Instala y activa fail2ban (anti fuerza bruta sobre SSH)
#
#  ⚠️ ADVERTENCIA: este script DESHABILITA el login por password.
#     Asegurate de tener acceso por CLAVE SSH funcionando ANTES de
#     correrlo, o te podés quedar afuera. En EC2 con tu .pem ya estás.
#
#  Uso:  chmod +x hardening.sh && sudo ./hardening.sh
# ===================================================================

set -euo pipefail

# --- Solo abrir estos puertos. Ajustá si cambiaste los defaults. ---
SSH_PORT=22
REALMD_PORT=3724
MANGOSD_PORT=8085

log() { echo -e "\n\033[1;32m[+] $*\033[0m"; }

if [[ $EUID -ne 0 ]]; then
  echo "Corré con sudo: sudo ./hardening.sh" >&2
  exit 1
fi

# ───────────────────────────────────────────────
log "1/4 — Actualizando el sistema"
# ───────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# ───────────────────────────────────────────────
log "2/4 — Endureciendo SSH (drop-in config)"
# ───────────────────────────────────────────────
# Usamos un archivo drop-in en sshd_config.d en vez de editar el
# archivo principal: más limpio y 100% idempotente.
SSH_DROPIN="/etc/ssh/sshd_config.d/99-hardening.conf"
cat > "$SSH_DROPIN" <<EOF
# Generado por hardening.sh
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
EOF

# Validamos la config antes de reiniciar (evita dejar SSH roto)
if sshd -t; then
  systemctl restart ssh
  echo "    SSH endurecido y reiniciado."
else
  echo "    ⚠️ Config SSH inválida — NO se reinició. Revisá $SSH_DROPIN" >&2
  exit 1
fi

# ───────────────────────────────────────────────
log "3/4 — Configurando el firewall del host (ufw)"
# ───────────────────────────────────────────────
apt-get install -y ufw
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"      comment 'SSH admin'
ufw allow "${REALMD_PORT}/tcp"   comment 'VMaNGOS realmd (login)'
ufw allow "${MANGOSD_PORT}/tcp"  comment 'VMaNGOS mangosd (world)'
ufw --force enable
echo "    Firewall activo — solo ${SSH_PORT}, ${REALMD_PORT}, ${MANGOSD_PORT} abiertos."

# ───────────────────────────────────────────────
log "4/4 — Instalando y configurando fail2ban"
# ───────────────────────────────────────────────
apt-get install -y fail2ban
cat > /etc/fail2ban/jail.local <<EOF
# Generado por hardening.sh
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = ${SSH_PORT}
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban
echo "    fail2ban activo sobre SSH."

# ───────────────────────────────────────────────
log "Hardening completo. Verificación del estado efectivo:"
# ───────────────────────────────────────────────
# Verificamos la config EFECTIVA de SSH (no confiamos en un solo archivo;
# la config final surge de combinar el principal + todos los drop-ins).
echo "--- SSH (sshd -T) ---"
sshd -T 2>/dev/null | grep -iE 'permitrootlogin|passwordauthentication|pubkeyauthentication' || true
echo "    Esperado: permitrootlogin no / passwordauthentication no / pubkeyauthentication yes"
echo "--- ufw ---";        ufw status verbose || true
echo "--- fail2ban ---";   fail2ban-client status sshd || true

cat <<'EOF'

✅ Listo. Recordatorios:
   - Verificá que podés abrir una NUEVA sesión SSH por clave ANTES de cerrar
     la actual (por las dudas).
   - 'sudo fail2ban-client status sshd' te muestra IPs baneadas.
EOF
