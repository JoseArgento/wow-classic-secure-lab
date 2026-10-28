# Secure Game Server Lab: a Mini SOC on my own hardware

**English** | [Español](README.es.md)

This is a small SOC (SIEM, network IDS and SOAR) that I built at home to protect
a game server that is really exposed to the internet: WoW Classic 1.12.1
(VMaNGOS) and Valheim, running on a physical machine in my house. The game is
just the workload. What the project is really about is detection engineering,
automated response with a human approving every action, and testing each
control against real attacks before trusting it.

Versions 1 and 2 ran on AWS EC2. In October 2026 I moved everything to my own
hardware (the reasons are in [ADR-001](docs/adr/ADR-001-aws-to-home-lab.md)).

![Status](https://img.shields.io/badge/status-active-success)
![Self-hosted](https://img.shields.io/badge/infra-self--hosted-informational)
![Docker](https://img.shields.io/badge/Docker-Compose-blue)
![SIEM](https://img.shields.io/badge/SIEM-Alloy%20%2B%20Loki%20%2B%20Grafana-yellow)
![NIDS](https://img.shields.io/badge/NIDS-Suricata%20%2B%20ET%20Open-orange)
![SOAR](https://img.shields.io/badge/SOAR-n8n%20%2B%20LLM-red)
![Detection-as-Code](https://img.shields.io/badge/Detection--as--Code-Sigma-purple)

---

## The short version

![A real attacker, detected by Suricata, triaged by the SOAR and banned after my approval](evidence/v3/telegram-real-attacker-ban.png)

About half an hour after I turned Suricata on, a scanner that appears on
several blocklists hit the world server port. Suricata flagged it by
reputation, the SOAR looked it up (AbuseIPDB 100, VirusTotal 7/92), the LLM
analyst rated it Malicious, and the ban only ran after I approved it on
Telegram. The full write-up is in
[INC-2026-001](docs/ir/informes/INC-2026-001-escaneo-reputacion-8085.md).

| | |
|---|---|
| **Detection** | 8 Sigma rules (CI and `pytest` with real log lines), Suricata with about 53k ET Open signatures |
| **ATT&CK coverage** (v19) | 7 techniques across 5 tactics, measured with [`attack-mapper`](https://pypi.org/project/attack-mapper/) |
| **Response** | LLM triage, Telegram, my approval, a restricted SSH user, then `fail2ban` (all ports, TCP and UDP, Docker included) |
| **SOC health** | A heartbeat with a dead man's switch, plus an error workflow, so the SOC warns me when it stops seeing |
| **Evidence** | Every control was attacked on purpose, see [Validation](#validation-every-control-attacked) |
| **Incident response** | Playbooks based on NIST SP 800-61 Rev. 3 and two reports of real incidents |

---

## Architecture (v3)

![Lab architecture v3](docs/architecture-v3.png)

The diagram source is [`docs/architecture-v3.excalidraw`](docs/architecture-v3.excalidraw) and can be opened at excalidraw.com.

![The physical server: an old mining rig reused as the lab host](evidence/v3/setup-fisico.jpg)

*The i3 server itself: an old mining rig, now running the games and the defense layer.*

| Where | What | Notes |
|---|---|---|
| **i3** (i3-10100F, 16 GB) | VMaNGOS, Valheim, Suricata, Alloy, fail2ban | The games start when I need them; the defenses start with the machine |
| **VM `observabilidad`** | Loki 3.0 and Grafana 13 | Built from a script (unattended Ubuntu install), both listening only on `127.0.0.1` |
| **VM `ai-lab`** | n8n 2.28 and Postgres 16 | The SOAR. LLM: `openai/gpt-oss-120b` on Groq |
| **VM Kali** | Attacker | Every control in this repo was attacked from here |

---

## Repository map

| Folder | Contents |
|---|---|
| [`infra/`](infra/) | VMs as code: `deploy-vm.sh` and an unattended Ubuntu install, with placeholders instead of secrets |
| [`vmangos/`](vmangos/) | Game server compose (images pinned by digest, secrets in `.env`, split horizon realmlist) |
| [`i3/`](i3/) | Host configuration: SSH, `fail2ban`, `sysctl`, Suricata, the SOAR ban wrapper and its `sudoers`, cron jobs (heartbeat, DDNS, signatures) |
| [`alloy/`](alloy/) | Log agent for the journal, the game log and Suricata alerts, with a documented label contract |
| [`grafana/`](grafana/) | Loki and Grafana, fully provisioned: datasource, contact points, alert rules and dashboards |
| [`soar/`](soar/) | n8n and Postgres compose, the exported workflow (no secrets) and the cache schema |
| [`docs/ir/`](docs/ir/) | Incident response playbooks, report template and real incident reports |
| [`docs/adr/`](docs/adr/) | Architecture decision records |
| [`docs/threat-model.md`](docs/threat-model.md) | Threat model for the home setup and the risks I accepted |
| [`docs/legacy-aws/`](docs/legacy-aws/) | Docs and configs from v1 and v2 (AWS EC2), kept for history |

The detection rules have their own repo: [`detection-rules-ci`](https://github.com/JoseArgento/detection-rules-ci).

Playbooks, incident reports, the ADR and the threat model are written in Spanish, like the thesis this lab supports.

---

## How detection and response work

1. **Telemetry.** Grafana Alloy (Promtail reached end of life) ships the
   systemd journal, the game's `Realmd.log` with each event's own timestamp,
   and Suricata's alerts. Logs leave the host through a reverse SSH tunnel,
   and the key used for it can only open `127.0.0.1:3100`. No inbound port is
   opened anywhere.
2. **Detection as code.** Sigma rules are compiled to LogQL in CI, tested
   against real log lines from this host and turned into Grafana alert rules
   with fixed UIDs. The rules repo is the only source of truth.
3. **Network detection.** Suricata runs as a passive IDS with ET Open. Its
   `HOME_NET` is only the server, not my whole LAN, so an attacker inside my
   own network still triggers signatures. Only alerts are sent to Loki.
   Priority 1 and 2 go to the SOAR; priority 3 stays searchable but doesn't
   notify.
4. **SOAR triage.** n8n looks the IP up in AbuseIPDB, RDAP and VirusTotal, and
   an LLM gives a verdict following written rules (for example, a clean
   reputation never lowers the verdict when the behavior I'm seeing is
   hostile). Verdicts are cached in Postgres so the same IP isn't analyzed
   twice.
5. **I approve every ban.** The LLM recommends and I decide. A ban is only
   proposed when the verdict is Malicious or the rule is high severity, and
   never for private IPs. The IP gets checked three times: before proposing,
   after I approve, and again on the server by `soar-ban.sh`.
6. **Checking that the SOC itself works.** A heartbeat every minute feeds a
   dead man's switch, and any failed SOAR run sends me a Telegram message. If
   everything is quiet, I don't take it for granted.

![n8n SOAR workflow](evidence/v3/n8n-soar-workflow.png)

More detail in [`docs/soar-pipeline.md`](docs/soar-pipeline.md).

---

## Hardening at home

| Control | How | How I checked it |
|---|---|---|
| **Small exposure** | The router only forwards the game ports. SSH is never exposed and UPnP is off | Port check from outside: 3724 and 8085 open; 22, 80, 443 and 8080 closed |
| **SSH** | Keys only, no root, reachable only from the LAN through `ufw` | `sshd -T`, and a password login gets refused |
| **Bans that also cover Docker** | `fail2ban` blocks in the nftables `prerouting` chain (priority -150, before Docker's DNAT), for TCP and UDP | From Kali: open, then timeout while banned, then open again after the unban |
| **Least privilege for automation** | The `soar` user's key only works from the SOAR VM, has no shell, and `sudo` only allows a wrapper that validates its input | 21 test cases for the wrapper, plus an escalation attempt |
| **Kernel** | `sysctl`: no redirects or source routing, martian packets logged, kernel pointers hidden, ptrace and eBPF limited to root. One documented exception: `ip_forward=1`, which Docker needs | Diff before and after, and it survives a reboot |
| **Supply chain** | Every image is pinned by digest once I've verified it | It caught a breaking upstream change during the migration |
| **Secrets** | Only in `.env` files that git ignores, with `.env.example` templates. Workflows are exported and scanned before committing | The scan found an API key typed straight into a node |
| **Games on demand** | VMaNGOS and Valheim don't start at boot; `restart: on-failure` only recovers crashes | Reboot test |

---

## Validation: every control attacked

| Control | Test | Result |
|---|---|---|
| Bans reach ports published by Docker | `nc` from Kali to 3724 and 22, ban, retry, unban | open, timeout, open |
| SOAR end to end | A lockout injected from a TEST-NET IP, then approval | Loki, alert, n8n, Telegram, ban, audit log |
| No bans for internal IPs | A lockout injected from a LAN IP | The verdict arrives without a ban button |
| Dead man's switch | Log agent stopped for about 5 minutes | Alert on Telegram, then the recovery message |
| Reboot | `sudo reboot` | Games stay off, defenses come up, the tunnel reconnects, 1 minute gap in the heartbeat |
| Suricata against an insider | A burst of SSH connections from Kali | *ET SCAN Potential SSH Scan*, then a verdict that names the signature |
| Detection after a rule reload | Reload and scan again | Alert after the reload (this is where I found and fixed a bug, see the lessons) |
| **Real attacker** | A blocklisted scanner from the internet | Detected, analyzed and banned with my approval ([INC-2026-001](docs/ir/informes/INC-2026-001-escaneo-reputacion-8085.md)) |

![Suricata alerts in Loki, only alerts and no flow noise](evidence/v3/grafana-suricata-alerts.png)

---

## Incident response

The playbooks follow **NIST SP 800-61 Rev. 3** (April 2025, CSF 2.0 profile):

- [IR-01: Hostile external IP](docs/ir/IR-01-ip-externa-hostil.md)
- [IR-02: Hostile activity from the LAN](docs/ir/IR-02-actividad-hostil-lan.md)
- [IR-03: The SOC can't see](docs/ir/IR-03-soc-ciego.md)

Real incidents, written with the [report template](docs/ir/plantilla-informe.md):

- [INC-2026-001](docs/ir/informes/INC-2026-001-escaneo-reputacion-8085.md): a blocklisted scanner hit the world port. It was detected, analyzed and banned.
- [INC-2026-002](docs/ir/informes/INC-2026-002-periodo-ciego-soc.md): seven hours with the SOC turned off. What got lost, what the host kept, and why a bad reputation doesn't always mean an attack.

---

## Lessons learned

- **I found three ways for the SOC to go quiet in a single night.** A Suricata
  rule reload reset `HOME_NET` without any error and it stopped seeing the
  insider. The LLM rated a real scan as benign because it never got the
  signature name. And a rate-limited LLM call killed a run without telling
  anyone. All three are fixed and tested now, and the takeaway is that the
  monitoring itself needs monitoring.
- **The LLM recommends, the workflow decides.** The same event with less
  context got a different verdict. That's why a ban depends on the verdict,
  the rule's severity and a hard check on the IP, and no single one of them
  can ban (or hide an alert) on its own.
- **A bad reputation doesn't always mean an attack.** An internet measurement
  scanner scores 100 % on AbuseIPDB just because so many people report it, and
  its WHOIS record says it is not attacking anyone. When I trimmed the tool
  output to save tokens, I had removed exactly that line.
- **Bans and Docker take different paths.** `fail2ban` blocks in `input`, but
  traffic to published containers goes through DNAT and `forward`. Moving the
  bans to `prerouting`, and testing it with a real attack, closed that gap.
- **A "safer" component can break detection.** After switching to `sudo-rs`,
  denied escalation attempts stopped showing up in the logs. I only noticed by
  generating the real event.
- **If it isn't in Git it doesn't exist, and if it isn't in a volume it
  doesn't either.** The only history of real hostile traffic was living in a
  container's writable layer until the migration exposed it.
- **Pin what you verified.** An image with a breaking change arrived through
  `latest`. Now images get pinned by digest after I verify them.
- **It's QA applied to security.** If a control is listed in this README,
  there is a test that tried to break it.

---

## Untrusted client analysis (v1)

The game client came from an unofficial source, so I hashed and analyzed every
binary (VirusTotal plus dynamic analysis) before running it or sharing it. One
UPX-packed DLL had 2 heuristic detections out of 70 and turned out to be a
false positive. Full report: [`evidence/binary-verification.md`](evidence/binary-verification.md).

---

## History

| Version | Where | Main changes |
|---|---|---|
| v1 | AWS EC2 | Hardened multi-tier deployment, malware triage of the client |
| v2 | AWS EC2 and VMs | SIEM (Promtail, Loki, Grafana), Sigma in CI, n8n SOAR with an LLM and approvals on Telegram |
| **v3** | **My own hardware** | Migration ([ADR-001](docs/adr/ADR-001-aws-to-home-lab.md)), Alloy, Suricata, bans that cover Docker, SOC health checks, IR playbooks |

The v1 and v2 docs are in [`docs/legacy-aws/`](docs/legacy-aws/).

---

## About me

I'm **José**, a QA Automation Engineer moving into blue team and detection
engineering. This lab is the base of my final project for the Diploma in
Cybersecurity (UTN).

I try to bring a tester's habits to security: understand what is exposed
before exposing it, attack every control before trusting it, and keep the
evidence.

[LinkedIn](https://www.linkedin.com/in/jos%C3%A9-angel-argento-victoria/) | [detection-rules-ci](https://github.com/JoseArgento/detection-rules-ci) | [pentest-lab](https://github.com/JoseArgento/pentest-lab)

---

## Disclaimer

Personal, non-commercial lab running on my own infrastructure, for learning
detection engineering, incident response and Linux security. All the
validation attacks target my own systems.

## License

MIT, see [`LICENSE`](LICENSE).
