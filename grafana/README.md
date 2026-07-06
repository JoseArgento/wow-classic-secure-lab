# Observability stack — Loki + Grafana (provisioned as code)

The complete observability stack that receives the lab's telemetry: Loki (log
store) and Grafana (dashboards + alerting), both bound to `127.0.0.1` on the
analysis VM. The folder is named `grafana/` but the Compose file runs **both**
services — Grafana is simply the face of it.

Everything Grafana knows is provisioned from this folder — nothing is
configured through the UI:

| Path | Contents |
|---|---|
| `provisioning/datasources/` | Loki datasource (stable UID referenced by dashboards and alerts) |
| `provisioning/alerting/contact-points.yaml` | Webhook to the n8n SOAR pipeline |
| `provisioning/alerting/alert-rules.yaml` | ⚠️ **Generated artifact — do not edit by hand.** Compiled from Sigma sources in [`detection-rules-ci`](https://github.com/JoseArgento/detection-rules-ci) by `generate_alerts.py`. Versioned here as a snapshot of deployed state; regenerate via `deploy.sh` |
| `provisioning/dashboards/` | Dashboard provider + dashboard JSON |

> **Why provisioning-as-code is non-negotiable here:** a routine container
> recreation once wiped every UI-configured setting — datasources, alerts,
> dashboards. This folder is the fix: the whole stack rebuilds from Git.

## Usage

```bash
cp .env.example .env    # set a real admin password (never committed)
docker compose up -d
```

Grafana: `http://127.0.0.1:3000` · Loki: `http://127.0.0.1:3100` (both
localhost-only by design — see the
[logging architecture doc](../docs/blue-team-logging.md) for the reverse-tunnel
ingestion design).
