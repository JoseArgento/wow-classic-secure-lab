# legacy-aws/: v1 and v2 (AWS EC2)

**English**, *Español abajo*

Docs and configs from the versions of this lab that ran on **AWS EC2**
(`sa-east-1`), kept for history. They describe a deployment that **no longer
exists**: the stack moved to my own hardware in October 2026
([ADR-001](../adr/ADR-001-aws-to-home-lab.md)).

| File | What it was |
|---|---|
| `deploy-guide*.md` | Step-by-step EC2 deployment (v1) |
| `blue-team-logging*.md` | Telemetry design with Promtail and the reverse tunnel to the Kali VM (v2) |
| `blue-team-lab-v2.png` / `wow-blueteam-lab-v2.excalidraw` | v2 architecture diagram |
| `config/compose.yaml.example` | v1 VMaNGOS compose (pre vmangos-deploy v1) |
| `scripts/hardening.sh` | EC2 hardening script |

Current equivalents: [`vmangos/`](../../vmangos/), [`i3/`](../../i3/),
[`alloy/`](../../alloy/), [`grafana/`](../../grafana/), [`infra/`](../../infra/).

---

**Español:** documentos y configuraciones de las versiones del lab que corrían
en AWS EC2, conservados como historia. Describen un despliegue que **ya no
existe**: el stack se mudó a hardware propio en octubre de 2026 (ver ADR-001).
