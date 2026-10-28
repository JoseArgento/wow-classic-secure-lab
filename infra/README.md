# infra/: VMs del home lab como código

Recetas para crear las VMs del lab en VirtualBox de forma desatendida
(Ubuntu Server 26.04 + autoinstall). Una VM nueva sale de un comando y queda
idéntica cada vez: si la VM se rompe, se borra y se vuelve a crear.

```
infra/
├── deploy-vm.sh            # crea e instala cualquier VM de esta carpeta
├── local.env.example       # config de TU PC (ISO, placa de red)   -> local.env (no se commitea)
├── .gitignore
└── observabilidad/         # Loki + Grafana
    ├── vm.conf             # RAM, CPU, disco, MAC fija
    ├── user-data.example   # autoinstall con placeholders          -> user-data (no se commitea)
    └── meta-data
```

## Qué queda fuera de git y por qué

| Archivo | Contiene | Por qué no se sube |
|---|---|---|
| `*/user-data` | hash de la contraseña, clave pública | El hash publicado permite fuerza bruta offline sin límite de intentos |
| `local.env` | rutas de tu PC | No es portable y expone la estructura de tu máquina |

El repo guarda la **receta** (`user-data.example`), no los secretos. Ojo: si el
repo vive en una carpeta de OneDrive, `.gitignore` lo deja fuera de GitHub pero
**no** de OneDrive. Para eso está `USER_DATA_DIR` en `local.env`: los `user-data`
reales pueden vivir en una carpeta local fuera de la sincronización.

---

## Preparación (una sola vez por PC)

Todo desde **Git Bash**.

### 1. Clave SSH del home lab

```bash
ssh-keygen -t ed25519 -C "jose@pc-principal-homelab" -f ~/.ssh/id_ed25519_homelab
```

Ponele passphrase. La misma clave sirve para todas las VMs del lab y el i3.
No es la clave del usuario `soar` (esa es de la VM de n8n para los bans y
sigue separada, con permisos restringidos).

### 2. Contraseña de la VM (para `sudo` y la consola)

Con SSH solo por clave, la contraseña se usa para `sudo` y para entrar por la
consola de VirtualBox si se rompe la red. Generala y sacale el hash en un paso,
sin tipearla nunca:

```bash
PW=$(openssl rand -hex 12)
echo "Contraseña: $PW"
printf '%s' "$PW" | openssl passwd -6 -stdin
unset PW
```

- La primera línea es la contraseña (24 caracteres, 96 bits): **anotala** en
  papel o en un archivo local fuera de OneDrive y de git.
- La segunda es el hash `$6$...`: va en `user-data`.
- Como se genera y se pasa por pipe, no queda en el historial de la terminal.

### 3. Config de la PC

```bash
cd infra
cp local.env.example local.env
VBoxManage list bridgedifs        # copiá el "Name:" exacto a BRIDGE_ADAPTER
```

---

## Crear una VM (ej. observabilidad)

1. **Reserva DHCP en el router** para la MAC de `observabilidad/vm.conf`
   (`08:00:27:AA:0B:01`). Así la VM arranca ya con su IP definitiva y el i3
   siempre encuentra a Loki.
2. **Preparar el autoinstall:**
   ```bash
   cp observabilidad/user-data.example observabilidad/user-data
   ```
   Reemplazá:
   - `REEMPLAZAR_CON_HASH_SHA512` -> el hash del paso 2
   - `REEMPLAZAR_CON_CLAVE_PUBLICA` -> `cat ~/.ssh/id_ed25519_homelab.pub`
   - Verificá la subred del `ufw allow` (`ipconfig` en Windows)
3. **Crear:**
   ```bash
   ./deploy-vm.sh observabilidad
   ```
   Subiquity pide una confirmación ("Continue with autoinstall?"): Enter.
4. **Sacar las ISOs** cuando termine la instalación. El DVD está primero en
   el orden de arranque: un reinicio podría relanzar el instalador, y un Enter
   en "Continue with autoinstall?" borra el disco. Además `seed.iso` contiene
   el hash de la contraseña. Va con la VM **apagada**: encendida, el sistema
   bloquea la seed y VirtualBox responde `VERR_PDM_MEDIA_LOCKED`.
   ```bash
   VBoxManage controlvm observabilidad acpipowerbutton   # esperá a que apague
   VBoxManage storageattach observabilidad --storagectl IDE --port 0 --device 0 --medium emptydrive
   VBoxManage storageattach observabilidad --storagectl IDE --port 0 --device 1 --medium emptydrive
   VBoxManage closemedium dvd "$HOME/VirtualBox VMs/observabilidad/seed.iso" --delete
   VBoxManage showvminfo observabilidad --machinereadable | grep '"IDE-'   # ambas "emptydrive"
   ```
5. **Snapshot en limpio** antes de tocar nada:
   ```bash
   VBoxManage snapshot observabilidad take "00-instalacion-limpia"
   VBoxManage startvm observabilidad --type headless
   ```

> **Snapshots siempre con la VM apagada, nunca `--live`.** Un snapshot en vivo
> guarda también la RAM (6 GB) mientras la VM sigue escribiendo memoria; con
> el disco del host muy lleno no terminó nunca, la VM quedó con las CPUs
> congeladas (`rcu_preempt detected stalls`) y hubo que forzar el apagado.
> Apagada, el snapshot tarda segundos y no guarda RAM, que para restaurar
> no hace falta.

> `cloud-init status` va a decir `disabled` después del primer arranque.
> Es lo esperado: el instalador lo apaga una vez que aplicó el `user-data`.
> Para confirmar que corrió, mirá los efectos (`groups`, `ufw status`), no el estado.

### Chequeos que hace el script antes de crear nada

- No quedan placeholders `REEMPLAZAR_*` (una clave falsa con `allow-pw: false`
  deja la VM sin acceso SSH).
- La contraseña es un hash SHA-512 y hay una clave `ssh-ed25519`.
- El adaptador puente existe con ese nombre exacto (si no, lista los disponibles).
- No existe ya una VM con ese nombre.

## Verificación post-instalación

```bash
ssh -i ~/.ssh/id_ed25519_homelab blue-team-an@<IP>
sudo ufw status verbose      # deny incoming, 22/tcp solo desde la LAN
docker ps                    # sin sudo: el usuario está en el grupo docker
ssh -o PubkeyAuthentication=no blue-team-an@<IP>   # debe RECHAZAR (sin password)
```

## Decisiones de seguridad (para el threat model)

- **Red en adaptador puente.** La VM queda en la LAN plana junto al resto del
  lab. La separación no la da la topología, la dan controles explícitos: ufw,
  servicios publicados en `127.0.0.1` y SSH solo por clave.
- **Docker se saltea ufw** para puertos publicados. Por eso Loki y Grafana se
  publican siempre como `127.0.0.1:puerto`: Loki recibe por el túnel SSH
  inverso desde el i3 y Grafana se abre con `ssh -L 3000:localhost:3000`.
- **Grupo `docker` = root.** Aceptado en una VM de un solo administrador.
- **`updates: security`** aplica parches de seguridad durante la instalación.

## Agregar otra VM

Copiá `observabilidad/` con otro nombre, ajustá `vm.conf` (MAC distinta),
`hostname` y `meta-data` (`instance-id`), y corré `./deploy-vm.sh <nombre>`.

> En Windows, git puede perder el bit de ejecución. Si hace falta:
> `git update-index --chmod=+x infra/deploy-vm.sh`
