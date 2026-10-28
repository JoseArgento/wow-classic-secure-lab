#!/usr/bin/env bash
#
# deploy-vm.sh - Crea una VM del home lab en VirtualBox y la instala sola
#                vía autoinstall (Ubuntu Server 26.04 / subiquity).
#
# Uso (desde Git Bash, parado en infra/):
#   ./deploy-vm.sh observabilidad
#
# Cada VM tiene su carpeta en infra/<nombre>/ con:
#   vm.conf            -> recursos de la VM (RAM, CPU, disco, MAC)   [en git]
#   user-data.example  -> plantilla de autoinstall con placeholders  [en git]
#   meta-data          -> requerido por cloud-init (NoCloud)         [en git]
#   user-data          -> tu copia con hash y clave reales           [NO en git]
#
# Lo que depende de TU PC (ruta de la ISO, nombre de la placa de red) va en
# infra/local.env, que tampoco se commitea. Ver local.env.example.
#
# Requiere: VirtualBox 7.x + una de estas para generar la seed:
#   cloud-localds | xorriso | genisoimage | python3 + pycdlib (pip install pycdlib)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

die() { echo "❌ $*" >&2; exit 1; }

# ===================== ENTRADA =====================
VM_NAME="${1:-}"
[[ -n "$VM_NAME" ]] || die "Uso: ./deploy-vm.sh <nombre-vm>   (ej: ./deploy-vm.sh observabilidad)"

VM_SRC="$SCRIPT_DIR/$VM_NAME"
[[ -d "$VM_SRC" ]] || die "No existe la carpeta $VM_SRC"

# Config de la máquina anfitriona (ruta ISO, adaptador puente)
[[ -f "$SCRIPT_DIR/local.env" ]] || die "Falta infra/local.env. Copialo desde local.env.example y completalo."
# shellcheck source=/dev/null
source "$SCRIPT_DIR/local.env"

# Config de la VM (recursos y MAC)
[[ -f "$VM_SRC/vm.conf" ]] || die "Falta $VM_SRC/vm.conf"
# shellcheck source=/dev/null
source "$VM_SRC/vm.conf"

: "${ISO_PATH:?Definí ISO_PATH en local.env}"
: "${BRIDGE_ADAPTER:?Definí BRIDGE_ADAPTER en local.env}"
: "${RAM_MB:?Definí RAM_MB en vm.conf}"
: "${CPUS:?Definí CPUS en vm.conf}"
: "${DISK_MB:?Definí DISK_MB en vm.conf}"
: "${MAC_ADDRESS:?Definí MAC_ADDRESS en vm.conf}"

VM_DIR="${VM_DIR:-$HOME/VirtualBox VMs}"
VRAM_MB=16
OS_TYPE="Ubuntu_64"

# user-data puede vivir fuera del repo (p. ej. fuera de OneDrive).
# Si en local.env definís USER_DATA_DIR, se busca ahí: <USER_DATA_DIR>/<vm>/user-data
if [[ -n "${USER_DATA_DIR:-}" ]]; then
  USER_DATA="$USER_DATA_DIR/$VM_NAME/user-data"
else
  USER_DATA="$VM_SRC/user-data"
fi
META_DATA="$VM_SRC/meta-data"

# ===================== CHEQUEOS =====================
command -v VBoxManage >/dev/null 2>&1 || die "No encuentro VBoxManage."
[[ -f "$ISO_PATH" ]]  || die "No encuentro la ISO: $ISO_PATH"
[[ -f "$META_DATA" ]] || die "Falta $META_DATA"
[[ -f "$USER_DATA" ]] || die "Falta $USER_DATA (copialo desde user-data.example y completalo)"

# El autoinstall no se lanza con placeholders sin reemplazar: una clave SSH
# falsa con allow-pw: false deja la VM sin forma de entrar por SSH.
if grep -nE '^[^#]*REEMPLAZAR_' "$USER_DATA" >&2; then
  die "Quedan placeholders REEMPLAZAR_* en $USER_DATA (líneas arriba)."
fi

grep -Eq '^[[:space:]]*password:[[:space:]]*"\$6\$' "$USER_DATA" \
  || die "identity.password no parece un hash SHA-512 (\$6\$...). Ver infra/README.md."

grep -Eq '^[[:space:]]*-[[:space:]]*ssh-ed25519[[:space:]]+AAAA' "$USER_DATA" \
  || die "No encuentro una clave ssh-ed25519 válida en authorized-keys."

# El nombre del adaptador puente tiene que coincidir carácter por carácter.
# (tr -d '\r' porque en Windows VBoxManage devuelve finales de línea CRLF)
if ! VBoxManage list bridgedifs | tr -d '\r' | sed -n 's/^Name: *//p' | grep -Fxq "$BRIDGE_ADAPTER"; then
  echo "Adaptadores disponibles:" >&2
  VBoxManage list bridgedifs | tr -d '\r' | sed -n 's/^Name: */   /p' >&2
  die "BRIDGE_ADAPTER='$BRIDGE_ADAPTER' no coincide con ninguno."
fi

if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
  die "Ya existe una VM '$VM_NAME'. Borrala con: VBoxManage unregistervm \"$VM_NAME\" --delete"
fi

VM_PATH="$VM_DIR/$VM_NAME"
DISK_PATH="$VM_PATH/$VM_NAME.vdi"
SEED_PATH="$VM_PATH/seed.iso"
mkdir -p "$VM_PATH"

# Convierte rutas MSYS (/c/...) a Windows (C:\...) solo si estamos en Git Bash.
to_native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

# Intérprete de Python con pycdlib (Windows suele usar "python")
PYTHON=""
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import pycdlib" 2>/dev/null; then
    PYTHON="$cand"; break
  fi
done

# ===================== 1) SEED (label CIDATA) =====================
echo "📦 Generando seed de autoinstall..."
if command -v cloud-localds >/dev/null 2>&1; then
  cloud-localds "$SEED_PATH" "$USER_DATA" "$META_DATA"
elif command -v xorriso >/dev/null 2>&1; then
  # xorriso/genisoimage usan el nombre del archivo: copiamos a nombres exactos
  TMP_SEED="$(mktemp -d)"
  cp "$USER_DATA" "$TMP_SEED/user-data"; cp "$META_DATA" "$TMP_SEED/meta-data"
  xorriso -as mkisofs -o "$SEED_PATH" -V CIDATA -J -r "$TMP_SEED/user-data" "$TMP_SEED/meta-data"
  rm -rf "$TMP_SEED"
elif command -v genisoimage >/dev/null 2>&1; then
  TMP_SEED="$(mktemp -d)"
  cp "$USER_DATA" "$TMP_SEED/user-data"; cp "$META_DATA" "$TMP_SEED/meta-data"
  genisoimage -output "$SEED_PATH" -volid CIDATA -joliet -rock "$TMP_SEED/user-data" "$TMP_SEED/meta-data"
  rm -rf "$TMP_SEED"
elif [[ -n "$PYTHON" ]]; then
  "$PYTHON" - "$(to_native "$SEED_PATH")" "$(to_native "$USER_DATA")" "$(to_native "$META_DATA")" <<'PYEOF'
import os, sys, pycdlib
seed_path, user_data, meta_data = sys.argv[1], sys.argv[2], sys.argv[3]
iso = pycdlib.PyCdlib()
iso.new(joliet=True, rock_ridge='1.09', vol_ident='CIDATA')
with open(user_data, 'rb') as f_ud, open(meta_data, 'rb') as f_md:
    iso.add_fp(f_ud, os.path.getsize(user_data), '/USERDATA;1',
               joliet_path='/user-data', rr_name='user-data')
    iso.add_fp(f_md, os.path.getsize(meta_data), '/METADATA;1',
               joliet_path='/meta-data', rr_name='meta-data')
    iso.write(seed_path)
iso.close()
PYEOF
else
  die "Necesito cloud-localds, xorriso, genisoimage o python + pycdlib (pip install pycdlib)."
fi
echo "   Seed lista: $SEED_PATH"

# ===================== 2) VM =====================
echo "🛠  Creando VM '$VM_NAME'..."
VBoxManage createvm --name "$VM_NAME" --ostype "$OS_TYPE" --basefolder "$VM_DIR" --register

# Red en adaptador puente: la VM queda en la LAN igual que el resto del lab.
# MAC fija para poder reservarle la IP en el router ANTES de crearla.
VBoxManage modifyvm "$VM_NAME" \
  --memory "$RAM_MB" --cpus "$CPUS" --vram "$VRAM_MB" \
  --graphicscontroller vmsvga \
  --nic1 bridged --bridgeadapter1 "$BRIDGE_ADAPTER" \
  --macaddress1 "$MAC_ADDRESS" \
  --boot1 dvd --boot2 disk --boot3 none --boot4 none \
  --audio-enabled off --usbohci on --rtcuseutc on
  # VBox 6.x: "--audio-enabled off" -> "--audio none" ; "--usbohci on" -> "--usb on"

# ===================== 3) DISCO =====================
VBoxManage createmedium disk --filename "$DISK_PATH" --size "$DISK_MB" --format VDI
VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci --portcount 2 --bootable on
VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$DISK_PATH"

# ===================== 4) ISO + SEED =====================
VBoxManage storagectl "$VM_NAME" --name "IDE" --add ide --controller PIIX4
VBoxManage storageattach "$VM_NAME" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "$ISO_PATH"
VBoxManage storageattach "$VM_NAME" --storagectl "IDE" --port 0 --device 1 --type dvddrive --medium "$SEED_PATH"

echo "✅ VM creada y configurada."

# ===================== 5) ARRANQUE =====================
echo "🚀 Arrancando..."
VBoxManage startvm "$VM_NAME" --type gui

VM_USER="$(sed -n 's/^[[:space:]]*username:[[:space:]]*//p' "$USER_DATA" | head -n1)"

cat <<EOF

──────────────────────────────────────────────────────────────
⚠️  Subiquity va a pedir UNA confirmación antes de borrar el disco
   ("Continue with autoinstall?"). Enter y el resto sale solo.

Cuando termine y reinicie, entrás con tu clave:
   ssh -i ~/.ssh/id_ed25519_homelab ${VM_USER:-<usuario>}@<IP reservada para ${MAC_ADDRESS}>

Adentro, verificá (ver infra/README.md):
   cloud-init status   -> "disabled" es lo esperado tras el primer arranque
   groups              -> incluye docker
   sudo ufw status verbose -> deny (incoming), 22/tcp solo desde la LAN

Después, desde esta terminal, sacá las ISOs: el DVD arranca primero y un
reinicio podría relanzar el instalador (un Enter borra el disco). Además
seed.iso contiene el hash de la contraseña. Con la VM APAGADA (encendida,
el sistema bloquea la seed: VERR_PDM_MEDIA_LOCKED):
   VBoxManage controlvm "$VM_NAME" acpipowerbutton     # esperá a que apague
   VBoxManage storageattach "$VM_NAME" --storagectl IDE --port 0 --device 0 --medium emptydrive
   VBoxManage storageattach "$VM_NAME" --storagectl IDE --port 0 --device 1 --medium emptydrive
   VBoxManage closemedium dvd "$(to_native "$SEED_PATH")" --delete
   VBoxManage showvminfo "$VM_NAME" --machinereadable | grep '"IDE-'   # ambas "emptydrive"

Y recién ahí, el snapshot en limpio:
   VBoxManage snapshot "$VM_NAME" take "00-instalacion-limpia"
   VBoxManage startvm "$VM_NAME" --type headless
──────────────────────────────────────────────────────────────
EOF
