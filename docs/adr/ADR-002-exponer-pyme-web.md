# ADR-002: Exponer la web de demo (`pyme-web`) a internet por port forwarding

| Campo | Valor |
|---|---|
| **Estado** | Aceptada (13/11/2026). Implementación en curso: el puerto se abre recién cuando se cumplan las condiciones de abajo |
| **Fecha** | 2026-11-13 |
| **Responsable** | José Argento |
| **Relacionada** | ADR-001 (lab en infraestructura propia), `docs/threat-model.md` (A10) |

## Contexto

- El Mini SOC se extiende a un segundo workload: `pyme-web`, el sitio de una
  PyME ficticia (Flask detrás de nginx) cuyo log de acceso alimenta la familia
  de reglas web.
- Para el trabajo grupal hace falta que los otros integrantes lleguen al sitio
  **desde internet**: para usarlo y para atacarlo desde sus casas, con IPs
  públicas reales.
- La primera versión del sitio decía explícitamente "no forwardear este
  puerto": estaba pensada solo para la LAN.
- El sitio **no es explotable a propósito**: se detectan intentos, no
  explotación. Eso es lo que hace razonable exponerlo desde una red doméstica.

## Decisión

Publicar el sitio con **port forwarding del router (TCP 8080 -> i3:8080)** y el
DDNS que ya usa el lab (DuckDNS), igual que los puertos del juego.

Sigue la política del lab: el workload va **a pedido** (se levanta para las
pruebas y la campaña), la capa de defensa arranca siempre.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Cloudflare Tunnel** | No abre puertos, da HTTPS y no muestra la IP de casa. Pero todos los pedidos llegan desde el túnel: el ban por IP en el host deja de servir, que es justo la respuesta que el SOC tiene que demostrar. Una URL fija exige dominio propio |
| **Tailscale** (solo los integrantes) | Riesgo mínimo, pero no es internet: sin tráfico hostil real, con IPs 100.x, y el ban no aplica |
| **VPS** | Aísla la casa por completo. Es rehacer la arquitectura de la v2 (túnel inverso a Loki, fail2ban en el VPS) para un trabajo con fecha |
| **Dejarlo solo en la LAN** | No cumple el objetivo: sin IPs públicas, el SOAR nunca propone un ban (rechaza rangos privados) |

El port forwarding es la única opción en la que detección, triage y ban
funcionan sin cambiar nada del SOC, y con la IP real del visitante en el log.

## Condiciones para abrir el puerto

Cada una se verifica con una prueba, no se da por hecha:

1. **El contenedor expuesto no puede iniciar conexiones** (`DOCKER-USER`,
   `i3/docker-user/`): probado desde adentro del contenedor contra la LAN,
   internet y el propio i3.
2. **El i3 actualizado y reiniciado**, con ufw, fail2ban, Alloy, Suricata y las
   reglas `DOCKER-USER` arriba después del reinicio.
3. **Rotación del log de acceso** instalada.
4. **El circuito alerta -> triage -> ban probado** con una IP de prueba
   (hecho el 13/11 con 203.0.113.113 y 203.0.113.114).
5. **Exposición verificada desde afuera**: abierto el 8080 y nada más nuevo.

## Consecuencias

**Positivas**
- Tráfico hostil real contra la familia de reglas web, como pasó con el 3724.
- La respuesta se puede demostrar completa: un integrante ataca desde su casa
  y el ban corta su IP de verdad.
- Ningún componente nuevo que mantener.

**Negativas y riesgos asumidos** (detalle en [`threat-model.md`](../threat-model.md))
- **Más superficie en la red de casa**: un servidor HTTP atendiendo a internet
  en la misma LAN plana que los equipos personales.
- **HTTP sin TLS**: la contraseña de demo viaja en claro. No protege nada,
  pero no se reusa.
- **Sin rate limiting** en el sitio, a propósito.
- Los umbrales de las reglas web se fijaron con una corrida en la LAN: el
  ruido de fondo de internet va a obligar a ajustarlos, y cada alerta consume
  del límite de tokens del LLM.

## Medidas agregadas por exponerlo

- Clave de sesión y contraseña de demo fuera del repo; nginx en rama con
  soporte y fijado por digest.
- Contenedores de solo lectura, sin capabilities y con `no-new-privileges`. La
  app no tiene salida de red; nginx no puede iniciar conexiones y cada intento
  queda en el journal (`LAESQUINA-EGRESS`).
- Límites de cuerpo y timeouts en nginx; cabeceras de seguridad.
- Log de acceso en JSON con la línea cruda del pedido, para no perder los
  intentos que nginx rechaza con 400.

## Verificación

La exposición se da por implementada cuando las cinco condiciones tengan su
evidencia y un ataque real desde afuera termine en un ban aprobado por
Telegram.
