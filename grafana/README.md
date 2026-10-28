# Observability stack: Loki + Grafana (provisioned as code)

The stack that receives the lab's telemetry: Loki (log store) and Grafana
(dashboards + alerting), running on the **`observabilidad` VM** (created with
[`infra/`](../infra/)). Both are bound to `127.0.0.1`: Loki receives logs only
through the reverse SSH tunnel opened by `loki-tunnel.service`, and Grafana is
reached with `ssh -L 3000:localhost:3000`.

Everything Grafana knows is provisioned from this folder, nothing is
configured through the UI:

| Path | Contents |
|---|---|
| `docker-compose.yml` | Loki 3.0 + Grafana 13 (pinned), persistent volumes, `stop_grace_period` so Loki flushes on shutdown |
| `loki/config.yaml` | Loki config (tsdb v13, 365-day retention) |
| `loki-tunnel.service` | systemd unit for the reverse tunnel (the key on the i3 can only open `127.0.0.1:3100`) |
| `provisioning/datasources/` | Loki datasource (stable UID referenced by dashboards and alerts) |
| `provisioning/alerting/contact-points.yaml` | n8n SOAR webhook, Telegram (health), Telegram (host alerts) |
| `provisioning/alerting/alert-rules.yaml` | ⚠️ **Generated, do not edit.** Compiled from Sigma in [`detection-rules-ci`](https://github.com/JoseArgento/detection-rules-ci) by `generate_alerts.py` |
| `provisioning/alerting/alert-rules-health.yaml` | Dead man's switch (heartbeat), hand-written |
| `provisioning/alerting/alert-rules-suricata.yaml` | Suricata priority 1-2 -> SOAR, one notification per IP and signature |
| `provisioning/dashboards/` | Dashboard provider + dashboard JSON |

> **Why provisioning-as-code is non-negotiable here:** a routine container
> recreation once wiped every UI-configured setting, datasources, alerts,
> dashboards. This folder is the fix: the whole stack rebuilds from Git.

## Usage

```bash
cp .env.example .env    # admin password + Telegram bot token (never committed)
docker compose up -d
```

> Never run `docker compose down -v`: it deletes the Loki volume (the log
> history). To shut down, power off the VM; Docker stops the containers and
> brings them back on boot.
