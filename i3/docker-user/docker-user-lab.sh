#!/usr/bin/env bash
# /usr/local/sbin/docker-user-lab.sh - root:root 0755
# Reglas del lab en la cadena DOCKER-USER (iptables, tabla filter).
#
# POR QUÉ ACÁ: los contenedores salen por la cadena `forward`, donde ufw no
# opina (ufw protege `input`). DOCKER-USER es la cadena que Docker reserva para
# reglas propias: se evalúa antes que las suyas y Docker no la pisa.
#
# QUÉ HACE: el contenedor de nginx de pyme-web es lo único del lab que atiende
# pedidos HTTP de internet. Su trabajo es contestar; no tiene motivo para
# INICIAR una conexión hacia ningún lado (ni la LAN ni internet). Si alguien
# lograra ejecutar código ahí adentro, lo primero que haría es conectarse a
# algo: bajar herramientas, abrir un canal de control, escanear la LAN.
#   - LOG: deja el intento en el journal (prefijo LAESQUINA-EGRESS). Un solo
#     evento ya es señal fuerte de compromiso: nada legítimo lo genera.
#   - DROP: lo corta.
# Solo se frenan las conexiones NUEVAS que nacen del lado del contenedor. Las
# respuestas a los visitantes pertenecen a conexiones que abrieron ellos
# (ESTABLISHED) y pasan. nginx -> app va por otra red (backend), no por acá.
#
# La interfaz br-laesquina la fija pyme-web/docker-compose.yml. Si la web
# está apagada la interfaz no existe y las reglas no matchean nada.
#
# NO cubre: contenedor -> el propio i3. Ese tráfico entra por `input`, y ahí
# manda ufw (verificar con las pruebas del README).
set -euo pipefail

# Idempotente: agrega la regla solo si no está. -I la pone primera.
aplicar() {
  iptables -C DOCKER-USER "$@" 2>/dev/null || iptables -I DOCKER-USER "$@"
}

# Docker crea la cadena al arrancar; si todavía no existe, se crea vacía y
# Docker la adopta.
iptables -N DOCKER-USER 2>/dev/null || true

# Orden final: LOG y después DROP (cada -I entra arriba de la anterior).
aplicar -i br-laesquina -m conntrack --ctstate NEW -j DROP
aplicar -i br-laesquina -m conntrack --ctstate NEW \
        -m limit --limit 6/min -j LOG --log-prefix "LAESQUINA-EGRESS "

# --- Pendiente (backlog): ningún contenedor inicia conexiones hacia la LAN ---
# Cubre VMaNGOS y Valheim. Apagada hasta probarla con los dos juegos andando.
# aplicar ! -i eno1 -d 192.168.1.0/24 -m conntrack --ctstate NEW -j DROP

logger -t docker-user-lab "reglas DOCKER-USER aplicadas"
