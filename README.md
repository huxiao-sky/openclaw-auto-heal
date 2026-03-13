# OpenClaw Auto Heal

<div align="center">

**Self-healing runtime protection for OpenClaw Gateway**

A lightweight, open-source recovery layer for OpenClaw Gateway — built to detect failures, prefer official recovery paths, and use AI as a controlled fallback when needed.

![platform](https://img.shields.io/badge/platform-macOS-black)
![status](https://img.shields.io/badge/status-experimental-orange)
![license](https://img.shields.io/badge/license-MIT-green)

**中文说明 / Chinese README:** [README.zh-CN.md](./README.zh-CN.md)

</div>

## Overview

When OpenClaw Gateway breaks because of corrupted config, failed startup, or repeated health-check failures, the traditional recovery path is slow and manual:

- notice the issue
- log into the machine
- inspect logs
- patch config
- restart services

**OpenClaw Auto Heal** is designed to shorten that path into:

> detect → validate → recover with official tooling → fall back to AI only when necessary

It is not just a notification layer. The goal is to help the system recover itself — safely, minimally, and audibly.

## Why this project exists

This project tries to solve a very specific operational problem:

- OpenClaw Gateway can fail because of malformed config or incompatible changes
- manual recovery is slow and fragile
- unattended machines need a lightweight self-healing loop
- operators need something more practical than “watch logs and hope”

The result is a small but structured recovery system that combines process supervision, health checks, official repair commands, safe backups, and AI-assisted remediation.

## Core Features

- layered recovery flow: `launchd` + health check + official repair + AI fallback
- safe-backup recovery for broken `openclaw.json`
- **doctor-first** recovery strategy via `openclaw doctor --fix`
- AI repair only when official repair cannot restore service
- standalone AI repair credentials supported, with OpenClaw model config as fallback
- automatic command discovery for `openclaw`, `curl`, `jq`, `python3`, etc.
- dual security checks for AI-generated repair scripts: pattern guard + AST validation
- repair scripts are restricted to the target `openclaw.json`
- `DRY_RUN=1` mode for rehearsal
- optional config diff output before restart
- one-command installer via `install.sh`

## Repository Layout

```text
openclaw-auto-heal/
├── .gitignore
├── LICENSE
├── README.md
├── README.zh-CN.md
├── bootstrap.sh
├── install.sh
├── docs/
│   ├── architecture.md
│   └── security.md
├── launchd/
│   ├── com.openclaw.gateway.plist
│   └── com.openclaw.healthcheck.plist
└── scripts/
    ├── auto-heal-ai.sh
    └── health-check.sh
```

## Recovery Order

The current recovery flow is intentionally layered:

1. **If JSON is fully corrupted**
   - restore from safe backup immediately

2. **If config is still readable**
   - try the official repair path first:

   ```bash
   openclaw doctor --fix
   ```

3. **Only if official repair cannot restore service**
   - fall back to AI-assisted repair

This makes AI the enhancement layer — not the first or only dependency.

## Architecture

The system currently works in four layers:

### 1. `launchd` supervision
- keeps Gateway running
- restarts the process after crashes
- provides the lowest-level availability baseline

### 2. health check layer
- runs `openclaw status`
- tracks repeated failures
- triggers recovery when the threshold is reached

### 3. official doctor recovery layer
- runs `openclaw doctor --fix`
- reuses official repair logic first
- reduces coupling to undocumented internal config behavior

### 4. AI repair layer
- collects validation errors
- generates a minimal Python repair script
- validates script safety
- executes repair
- validates config
- updates safe backup
- restarts and verifies Gateway

See also: [`docs/architecture.md`](./docs/architecture.md)

## AI Configuration Strategy

The project currently supports two configuration modes.

### Mode A — Standalone AI repair config (preferred)

If the following environment variables exist, the repair script uses them first:

```bash
export AUTO_HEAL_API_KEY="your-key"
export AUTO_HEAL_API_ENDPOINT="https://code.newcli.com/claude/droid/v1/messages"
export AUTO_HEAL_MODEL="claude-sonnet-4-5"
export AUTO_HEAL_PROVIDER="external"
```

Optional advanced overrides:

```bash
export AUTO_HEAL_API_HEADER_VALUE="your-key"
export AUTO_HEAL_API_VERSION_VALUE="2023-06-01"
```

### Mode B — Fallback to OpenClaw model config

If no standalone repair config is provided, the script falls back to OpenClaw model settings, including:

- `models.defaultProvider`
- `models.providers.<provider>.apiKey`
- `models.providers.<provider>.endpoint`
- `models.providers.<provider>.model`

This is convenient, but more tightly coupled.

## Quick Start

### Install

```bash
chmod +x install.sh bootstrap.sh
./install.sh
```

The installer will:

- copy scripts into `~/.openclaw/scripts/`
- initialize log directories
- create a safe backup when possible
- replace `YOUR_USERNAME` in launchd templates
- load the LaunchAgents

### Optional: configure standalone AI repair credentials

```bash
export AUTO_HEAL_API_KEY="your-key"
export AUTO_HEAL_API_ENDPOINT="https://code.newcli.com/claude/droid/v1/messages"
export AUTO_HEAL_MODEL="claude-sonnet-4-5"
export AUTO_HEAL_PROVIDER="external"
```

### Manual health-check test

```bash
bash ~/.openclaw/scripts/health-check.sh
```

### Manual repair test

```bash
bash ~/.openclaw/scripts/auto-heal-ai.sh
```

## Dry Run and Diff

To make this project feel more like a trustworthy open-source tool — not a black box that mutates config behind your back — it supports rehearsal and diff output.

### Dry run

```bash
DRY_RUN=1 bash ~/.openclaw/scripts/auto-heal-ai.sh
```

What it does:

- executes the repair flow
- prints config diff into logs
- **does not update the safe backup**
- **does not restart Gateway**
- **does not run `openclaw doctor --fix` when dry-run is enabled**

### Config diff

Diff output is enabled by default and can also be forced explicitly:

```bash
SHOW_DIFF=1 bash ~/.openclaw/scripts/auto-heal-ai.sh
```

## Security Notes

This is **not** a fully trusted autonomous operations system.
It is a guarded self-healing prototype.

Current protections include:

- dangerous-pattern blocking
- AST-level validation for generated Python repair code
- no network access from repair scripts
- no subprocess execution from repair scripts
- writes restricted to the target `openclaw.json`

For more details, see [`docs/security.md`](./docs/security.md).

## Current Status

### Done

- [x] extracted and reconstructed the core scripts
- [x] removed core path hardcoding
- [x] removed fixed-provider dependency
- [x] added standalone AI config with OpenClaw fallback
- [x] added doctor-first recovery via `openclaw doctor --fix`
- [x] added safety checks for AI-generated repair scripts
- [x] added `.gitignore`, `LICENSE`, and docs
- [x] added installer scripts
- [x] added dry-run and diff support
- [x] added bilingual documentation entry point

### Still worth improving

- [ ] more elegant launchd templating or generated install flow
- [ ] split `auto-heal-ai.sh` into clearer stage functions
- [ ] add shellcheck / CI
- [ ] add fault-injection test cases
- [ ] add a finer-grained allowlist for safe config edits
- [ ] add a diagram or screenshot for the GitHub landing page

## Is it ready for GitHub?

**Yes.**

At this point, the project is strong enough to be published publicly on GitHub as:

- experimental
- public prototype
- early-stage open-source project

It is no longer just an internal note or a rough script dump.
It already has a coherent recovery strategy, a safer execution model, an installer, bilingual docs, and a clear product direction.

What it is **not yet**: a polished, production-grade release.
That would require more testing, CI, installation hardening, and broader protocol support.

## Suggested GitHub Metadata

A simple repo description could be:

> Self-healing runtime protection for OpenClaw Gateway with doctor-first recovery and AI fallback.

Suggested topics:

- `openclaw`
- `self-healing`
- `devops`
- `aiops`
- `automation`
- `launchd`
- `macos`
- `reliability`

## License

MIT
