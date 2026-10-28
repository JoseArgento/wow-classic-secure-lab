# Modelo de amenazas: lab doméstico (v3)

Alcance: el i3 que sirve los juegos, las VMs del SOC en la PC principal y la
red de casa donde viven. Actualizado: 2026-10-28.

## 1. Qué se protege

| Activo | Por qué importa |
|---|---|
| **La red de casa** y sus equipos personales | El lab comparte LAN plana con la PC de uso diario y otros dispositivos: es el activo más valioso, aunque no sea "del lab" |
| El host i3 | Si se compromete, es un punto de apoyo dentro de la LAN |
| Cuentas y personajes (base `realmd` / `characters`) | Datos de jugadores reales |
| La integridad del SOC | Un SOC que se puede apagar o engañar da falsa seguridad |
| Secretos | Claves de Groq, AbuseIPDB y VirusTotal, token del bot de Telegram, claves SSH, contraseñas de las bases |
| La IP residencial | El DDNS la publica; está asociada a un domicilio |

## 2. Superficie de entrada

| Punto | Expuesto a | Control |
|---|---|---|
| TCP 3724 (realmd), 8085 (mangosd) | Internet | Servicio a pedido; Suricata; reglas Sigma; bans en `prerouting` |
| UDP 2456-2458 (Valheim) | Internet | Servicio a pedido; bans TCP+UDP |
| SSH del i3 y de las VMs | Solo LAN | Solo clave, sin root, ufw |
| n8n (5678) | LAN | Sin publicar a internet; **abierto a toda la LAN** (riesgo aceptado, ver §5) |
| Loki / Grafana | Solo `127.0.0.1` de su VM | Túnel SSH inverso restringido; Grafana por `ssh -L` |
| Bot de Telegram | Internet (API de Telegram) | Escribe solo al chat configurado; los botones de aprobación solo existen ahí |
| Datos que lee el agente LLM (logs, WHOIS, nombres de firmas) | Controlados en parte por el atacante | Ver amenaza A6 |

## 3. Adversarios

| Adversario | Probabilidad | Ejemplo real en el lab |
|---|---|---|
| Escáneres y bots de internet | **Muy alta**, ocurre a diario | 16.5.0.223 (INC-2026-001), 193.163.125.92 (INC-2026-002) |
| Fuerza bruta contra cuentas del juego | Alta | Lockouts del realmd (histórico de la v2 en AWS) |
| Explotación del servidor de juego | Media | VMaNGOS es C++ que parsea tráfico sin autenticar |
| Equipo comprometido dentro de la LAN | Baja-media | Simulado con la Kali |
| Jugador malicioso (con cuenta) | Baja | Abuso dentro del juego |

## 4. Amenazas y controles

| # | Amenaza | Controles | Riesgo residual |
|---|---|---|---|
| A1 | Fuerza bruta / credential stuffing contra realmd | Lockout nativo de VMaNGOS, reglas Sigma (wrong password, lockout), SOAR + ban | Bajo |
| A2 | Escaneo y reconocimiento (T1595) | Exposición mínima verificada, Suricata (firmas de reputación y de patrón), ufw | Bajo. Suricata no detecta escaneos de puertos genéricos |
| A3 | Explotación de VMaNGOS (T1190) | Contenedores sin root (UID 1000), base de datos no publicada, servicio a pedido, imágenes fijadas, detección de crashes de sshd (T1190) | **Medio**: no hay WAF ni sandbox adicional; un exploit llevaría al contenedor |
| A4 | Movimiento lateral desde el i3 hacia la LAN | ufw entrante, SSH solo con clave, Suricata ve tráfico del host | **Medio-alto**: LAN plana, sin segmentación |
| A5 | Desactivar las defensas o el SOC (T1685) | Regla *Security Service Stopped*, dead man's switch, workflow de errores, logs fuera del host | Medio (ver INC-2026-002 y los tres silencios) |
| A6 | Inyección de prompt al agente LLM vía datos del atacante | El LLM no ejecuta nada; ban solo con aprobación humana; validación de IP en tres capas | Medio: el veredicto se puede manipular, pero la acción no |
| A7 | Robo de secretos | `.env` fuera de git, escaneo de exports, credenciales cifradas en n8n, claves SSH restringidas (`from=`, `permitlisten`) | Bajo |
| A8 | Abuso de la automatización de respuesta (banear IPs legítimas) | Aprobación humana, rechazo de IPs privadas/reservadas, bans con vencimiento | Bajo |
| A9 | Denegación de servicio | Ninguno propio (el router del ISP no permite configurarlo) | **Alto, aceptado**: lab sin SLA |

## 5. Riesgos aceptados (y por qué)

| Riesgo | Por qué se acepta | Mitigación futura |
|---|---|---|
| LAN plana | El router del ISP no permite VLANs | Router propio (ONT en bridge + OpenWrt/OPNsense) con VLAN para el lab |
| El SOC depende de la PC principal | Hardware disponible | Monitor de latido externo; buffer en disco de Alloy |
| n8n abierto a toda la LAN | Docker se saltea ufw | Regla en la cadena `DOCKER-USER` |
| `sudo-rs` no registra denegaciones | Cambiarlo rompe otras cosas | `auditd` |
| Grupo `docker` = root | VMs y host de un solo administrador | - |
| Límites del plan gratuito del LLM (8K tokens/min) | Costo | Achicar tokens por triage; plan pago |
| Sin protección DoS | Router gestionado por el ISP | Router propio |

## 6. Supuestos

- El operador es la única persona con acceso administrativo.
- La PC principal no está comprometida (aloja el SOC).
- Los proveedores de enriquecimiento (AbuseIPDB, VirusTotal, RDAP) y Groq
  responden con datos honestos.
