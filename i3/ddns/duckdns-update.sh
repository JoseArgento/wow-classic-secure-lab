#!/usr/bin/env bash
# /usr/local/bin/duckdns-update.sh - root:root 0755
# Actualiza el nombre DuckDNS con la IP pública actual (la detecta DuckDNS).
# Lo corre /etc/cron.d/duckdns cada 5 minutos.
#
# El token vive en /etc/duckdns.env (root:root 0600) y se le pasa a curl por
# stdin (-K -), así no aparece en la lista de procesos (`ps`) mientras corre.
# Cada actualización queda en el journal (identifier=duckdns): un cambio de
# IP pública queda auditado en Grafana.
set -euo pipefail

# shellcheck source=/dev/null
source /etc/duckdns.env
: "${DUCKDNS_DOMAIN:?Falta DUCKDNS_DOMAIN en /etc/duckdns.env}"
: "${DUCKDNS_TOKEN:?Falta DUCKDNS_TOKEN en /etc/duckdns.env}"

resp=$(printf 'url = "https://www.duckdns.org/update?domains=%s&token=%s&ip="\n' \
         "$DUCKDNS_DOMAIN" "$DUCKDNS_TOKEN" \
       | curl -fsS --max-time 20 -K -)

logger -t duckdns "update ${DUCKDNS_DOMAIN}: ${resp}"
[[ "$resp" == OK* ]]
