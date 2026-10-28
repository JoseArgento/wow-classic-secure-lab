# i3/: configuración del host físico como código

El i3 (`valheim`, 192.168.1.66) corre VMaNGOS y Valheim **a pedido**, y la
capa de defensa **siempre**: ufw, fail2ban, Alloy (y Suricata).

```
i3/
├── ssh/01-hardening.conf          -> /etc/ssh/sshd_config.d/
├── fail2ban/jail.d/lab.local      -> /etc/fail2ban/jail.d/
├── fail2ban/filter.d/soar.conf    -> /etc/fail2ban/filter.d/
├── cron/lab-heartbeat               -> /etc/cron.d/            (latido del dead man's switch)
├── cron/duckdns                     -> /etc/cron.d/
├── cron/suricata-update            -> /etc/cron.d/            (firmas ET Open, diario)
├── ddns/duckdns-update.sh           -> /usr/local/bin/         (root:root 0755)
├── ddns/duckdns.env.example         -> /etc/duckdns.env        (root:root 0600, el real no se commitea)
├── sysctl/99-lab-hardening.conf     -> /etc/sysctl.d/          (endurecimiento del kernel)
├── suricata/lab.conf                -> /etc/systemd/system/suricata.service.d/   (interfaz de captura)
├── suricata/disable.conf            -> /etc/suricata/          (falsos positivos conocidos, con motivo)
└── soar/
    ├── soar-ban.sh                -> /usr/local/bin/        (root:root 0755)
    ├── sudoers-soar               -> /etc/sudoers.d/soar    (root:root 0440)
    └── authorized_keys.example    -> ~soar/.ssh/authorized_keys
```

## Decisiones de seguridad

- **SSH**: solo clave, sin root, y ufw lo limita a la LAN (`192.168.1.0/24`).
  El router no forwardea el 22.
- **Bans en `prerouting`**: VMaNGOS publica puertos con Docker; ese tráfico
  entra por DNAT y nunca pasa por `input`, que es donde fail2ban banea por
  defecto. En la EC2 los bans estaban en `input`. Acá van en `prerouting`
  con prioridad -150 (antes del DNAT de Docker, -100) y `drop`.
- **Usuario `soar`**: su clave solo funciona desde la VM de n8n
  (`from=`), sin pty ni forwarding (`restrict`), y con sudo solo puede
  correr `soar-ban.sh`, que valida IP y tier del lado del servidor.
- **Kernel (`sysctl`)**: sin redirects ni source routing, martians al log,
  punteros del kernel ocultos, ptrace y eBPF solo para root. Excepción
  documentada: `ip_forward = 1`, porque Docker lo necesita para publicar
  los puertos del juego (las guías CIS piden 0 en hosts que no rutean).
- **Suricata (IDS pasivo)**: copia de los paquetes de `eno1` contra ET Open.
  No bloquea (un falso positivo cortaría a un jugador); la respuesta sigue
  siendo fail2ban con aprobación humana. `HOME_NET` es solo el i3, no la LAN:
  así un atacante interno también dispara firmas. `eve.json` queda completo
  en el i3; a Loki van solo las alertas.
  `HOME_NET` se edita en `suricata.yaml` (no por `--set`): un reload de reglas
  relee el YAML y descarta los `--set`. Es la única línea cambiada del YAML:
  ```bash
  sudo cp -n /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.orig
  sudo sed -i 's|^    HOME_NET: "\[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12\]"|    HOME_NET: "[192.168.1.66/32]"|' /etc/suricata/suricata.yaml
  ```
  Si un upgrade del paquete pregunta por `suricata.yaml`, conservar la versión
  local o repetir el `sed`.
- **Túnel de logs**: el usuario `lokitunnel` no tiene shell y su clave solo
  puede abrir `127.0.0.1:3100` (`permitlisten`).

## Verificación

```bash
sudo sshd -T | grep -E "passwordauthentication|permitrootlogin"   # no / no
sudo ufw status numbered                                          # 22 solo LAN
sudo fail2ban-client status                                       # sshd, soar, soar-severe
sudo nft list chain inet f2b-table f2b-chain | head -3            # hook prerouting priority -150 (la tabla se crea con el primer ban)
sudo -l -U soar                                                   # solo soar-ban.sh
sudo sysctl --system 2>&1 | grep -E "^sysctl:"                       # sin salida
sysctl net.ipv4.ip_forward kernel.kptr_restrict net.ipv4.conf.all.accept_redirects   # 1, 2, 0
systemctl is-active suricata && sudo grep -E "eno1|rules successfully loaded" /var/log/suricata/suricata.log | tail -3
```
