#!/usr/bin/env bash
# /usr/local/bin/soar-ban.sh - único comando que el usuario `soar` puede
# correr con sudo. Lo invoca el nodo SSH de n8n tras la aprobación humana
# en Telegram:  sudo /usr/local/bin/soar-ban.sh <ipv4> <short|severe>
#
# Valida TODO del lado del servidor: n8n (y el LLM detrás) no son de fiar
# como fuente de input. root:root, 0755.
set -euo pipefail

IP="${1:-}"
TIER="${2:-}"

if [[ ! "$IP" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
  echo "ERROR: formato de IP invalido" >&2
  exit 1
fi
for octeto in "${BASH_REMATCH[@]:1}"; do
  # 10# fuerza base decimal: sin esto, "08" se lee como octal y rompe.
  if (( 10#$octeto > 255 )); then
    echo "ERROR: octeto fuera de rango" >&2
    exit 1
  fi
done

# Rangos que nunca se banean: privados, loopback, "esta red", link-local,
# CGNAT, multicast y reservados. TEST-NET (192.0.2/24, 198.51.100/24,
# 203.0.113/24) SÍ se permite: es lo que usan las pruebas.
if [[ "$IP" =~ ^10\. ]] || [[ "$IP" =~ ^192\.168\. ]] || \
   [[ "$IP" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || [[ "$IP" =~ ^127\. ]] || \
   [[ "$IP" =~ ^0\. ]] || [[ "$IP" =~ ^169\.254\. ]] || \
   [[ "$IP" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]] || \
   [[ "$IP" =~ ^(22[4-9]|2[3-5][0-9])\. ]]; then
  echo "ERROR: rango privado, reservado o no ruteable, no se banea" >&2
  exit 1
fi

case "$TIER" in
  short)  JAIL="soar" ;;
  severe) JAIL="soar-severe" ;;
  *) echo "ERROR: tier debe ser short o severe" >&2; exit 1 ;;
esac

/usr/bin/fail2ban-client set "$JAIL" banip "$IP"
# Va al journal -> Alloy -> Loki: cada ban queda auditado en Grafana.
logger -t soar-ban "Ban ejecutado: ip=$IP tier=$TIER jail=$JAIL"
