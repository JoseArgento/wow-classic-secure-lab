# ADR-001: Migrar el lab de AWS EC2 a infraestructura propia

| Campo | Valor |
|---|---|
| **Estado** | Aceptada e implementada (26-27/10/2026) |
| **Fecha** | 2026-10-27 |
| **Responsable** | José Argento |
| **Reemplaza** | Arquitectura v2 (EC2 + VMs), ver `docs/legacy-aws/` |

## Contexto

- El servidor de juego (VMaNGOS) corría en una instancia **EC2 de AWS** cubierta
  por créditos del Free Tier, que **vencían en noviembre de 2026**. Seguir en
  AWS implicaba pagar todos los meses por un lab personal.
- El stack de observabilidad (Loki + Grafana) vivía en la **Kali**, la misma VM
  que se usa para atacar el lab: mezclaba el rol de atacante con el de defensor,
  y Loki ni siquiera tenía un volumen persistente.
- Había disponible una **máquina física** (i3-10100F, 16 GB, 900 GB, ex equipo
  de minería) que ya alojaba un servidor de Valheim.
- El trabajo final de la Diplomatura pedía un proyecto propio; presentarlo
  sobre infraestructura propia (con foto del setup físico) le suma realismo.

## Decisión

| Componente | Antes (v2) | Después (v3) |
|---|---|---|
| VMaNGOS | EC2 (`sa-east-1`) | **i3** (Docker), a pedido |
| Valheim | i3 | i3, a pedido |
| Loki + Grafana | Kali | **VM `observabilidad`** en la PC principal, creada desde un script |
| n8n + Postgres | VM `ai-lab` | Sin cambios (repuntado al i3) |
| Kali | Atacante + observabilidad | **Solo atacante** |
| Agente de logs | Promtail (EOL) | **Grafana Alloy** |

Los juegos arrancan a pedido; la capa de defensa (ufw, fail2ban, Alloy,
Suricata, latido) arranca siempre.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| Quedarse en AWS pagando | Costo recurrente sin valor nuevo; el aprendizaje de la v2 ya estaba capitalizado |
| Todo en el i3, SOC incluido | Si el i3 cae o se compromete, el SOC cae con él: los logs deben salir del host que vigilan |
| Todo en VMs de la PC principal | El servidor de juego dependería de que la PC esté prendida y compitiría por recursos con el uso diario |
| SIEM en la nube (plan gratuito de un SaaS) | Límites de ingesta y retención, y una dependencia externa más. Además, la idea era aprender a operar el stack completo |

## Consecuencias

**Positivas**
- Costo de infraestructura cero (salvo electricidad).
- Control total del hardware, la red y los tiempos: se pueden probar escenarios
  que en la nube no aplican (atacante en la LAN, reinicios, cortes).
- Observabilidad separada del atacante, con volumen persistente y retención
  versionada.
- Todo el stack quedó **como código** (`infra/`, `i3/`, `vmangos/`, `alloy/`,
  `grafana/`, `soar/`): la migración obligó a versionar lo que en AWS estaba a
  mano.

**Negativas y riesgos asumidos** (detalle en [`threat-model.md`](../threat-model.md))
- **La red de casa queda expuesta**: los puertos del juego apuntan a una IP
  residencial, en una LAN plana compartida con equipos personales.
- **El SOC depende de que la PC principal esté prendida.** Con la PC apagada no
  hay alertas ni respuesta, y Loki no recibe ese período (ver INC-2026-002).
- **Router del ISP gestionado** (TR-069): sin VLANs, sin control de DoS, con
  administración limitada.
- **IP dinámica**: se resuelve con DDNS (DuckDNS), que a su vez generó un falso
  positivo en Suricata.
- Cortes de luz o de internet afectan al servidor; la nube los absorbía.

## Medidas agregadas por estar en casa

- SSH **nunca** expuesto a internet y limitado a la LAN; solo clave.
- `fail2ban` en `prerouting` de nftables para que los bans alcancen a los
  puertos publicados por Docker, TCP y UDP.
- Servicios del SOC publicados solo en `127.0.0.1`; ingesta por túnel SSH
  inverso con una clave que solo puede abrir `127.0.0.1:3100`.
- `sysctl` endurecido, Suricata pasivo con `HOME_NET` = solo el i3.
- Exposición verificada desde afuera (solo 3724/8085 abiertos).

## Verificación

La migración se dio por terminada recién cuando cada control pasó una prueba
con ataque o evento real: ver la tabla de validación del README y
`docs/ir/informes/`.
