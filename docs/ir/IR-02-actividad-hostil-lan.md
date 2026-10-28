# IR-02: Actividad hostil desde la LAN

**Alcance:** alertas cuyo IOC es una IP privada (192.168.x, 10.x,
172.16-31.x) y la regla *Linux Local Account Created*.

Acá **no hay ban automático, a propósito**: la LAN está en el `ignoreip` de
fail2ban, `soar-ban.sh` rechaza IPs privadas y n8n no ofrece el botón
(`IF ¿IP pública?`). Un atacante interno puede cambiar de IP en segundos, y un
ban por IP podría dejar afuera un equipo propio. La respuesta es humana.

## 1. Detección y análisis

1. **¿Qué equipo es?** En el i3, la tabla de vecinos da la MAC; el panel del
   router (DHCP) da el nombre (en el i3):
   ```bash
   ip neigh show <IP>
   ```
2. **¿Es esperado?** La Kali (192.168.1.35) haciendo pruebas, sí. Cualquier
   otro equipo escaneando o forzando logins, no.
3. **¿Qué hizo?** Mismas consultas A-C de IR-01, con la IP privada.
4. **¿Llegó a entrar?** Consulta C de IR-01. Si la alerta fue *Local Account
   Created*: ¿quién creó la cuenta? (en el i3)
   ```bash
   journalctl --since "-1h" -t useradd -t usermod --no-pager
   getent passwd | awk -F: '$3 >= 1000'
   ```

## 2. Contención

- **Equipo propio en prueba** (Kali): cerrar el incidente como prueba.
- **Equipo desconocido o comprometido**: desconectarlo de la red (cable o
  WiFi) o bloquear su MAC en el router. No alcanza con un ban por IP.
- **Cuenta creada sin autorización**: bloquearla ya y después investigar
  (en el i3):
  ```bash
  sudo usermod -L -e 1 <usuario>
  ```

## 3. Erradicación y recuperación

- Equipo comprometido: limpiarlo o reinstalarlo antes de reconectarlo.
- Si llegó al i3: tratarlo como compromiso del host (IR-01, §4).

## 4. Post-incidente

Siempre con informe: un incidente interno real nunca es "un bot más".
