# OpenClaw Auto Heal

<div align="center">

**Self-healing runtime protection for OpenClaw Gateway**

A lightweight recovery layer for OpenClaw Gateway that combines supervision, health checks, official repair commands, and AI fallback into one practical self-healing workflow.

![platform](https://img.shields.io/badge/platform-macOS-black)
![status](https://img.shields.io/badge/status-experimental-orange)
![license](https://img.shields.io/badge/license-MIT-green)

**中文说明 / Chinese README:** [README.zh-CN.md](./README.zh-CN.md)

</div>

## Overview

OpenClaw Auto Heal is built for a simple but painful reality: when OpenClaw Gateway breaks, recovery is often manual, slow, and operationally noisy.

This project turns that into a layered workflow:

> detect → validate → try official recovery → fall back to AI only when needed

The goal is not blind automation. The goal is **practical recovery with guardrails**.

## What it does

- supervises Gateway with `launchd`
- runs periodic health checks
- restores from safe backup when config is fully broken
- tries the official repair path first with `openclaw doctor --fix`
- uses AI repair only as a controlled fallback
- validates AI-generated repair scripts before execution
- supports dry-run rehearsal and config diff output
- supports standalone AI repair credentials or OpenClaw config fallback

## Core Features

- layered recovery flow: `launchd` + health check + doctor-first repair + AI fallback
- safe-backup recovery for broken `openclaw.json`
- official recovery preference via `openclaw doctor --fix`
- standalone AI repair credentials supported
- automatic discovery of required local commands
- dual safety checks for AI-generated repair scripts: pattern guard + AST validation
- repair scripts restricted to the target `openclaw.json`
- `DRY_RUN=1` mode for rehearsal
- optional config diff output before restart
- installer script for quick local setup

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
│   ├── architecture-diagram.md
│   └── security.md
├── launchd/
│   ├── com.openclaw.gateway.plist
│   └── com.openclaw.healthcheck.plist
└── scripts/
    ├── auto-heal-ai.sh
    └── health-check.sh
```

## Recovery Strategy

The recovery order is intentionally conservative:

1. **If JSON is fully corrupted**
   - restore from safe backup immediately

2. **If config is still readable**
   - try the official recovery path first:

   ```bash
   openclaw doctor --fix
   ```

3. **Only if official recovery does not restore service**
   - fall back to AI-assisted repair

This keeps AI as the enhancement layer, not the default repair primitive.

## Architecture

The system works in four layers:

### 1. launchd supervision
- keeps Gateway alive
- restarts the process after crashes

### 2. health check layer
- runs `openclaw status`
- tracks repeated failures
- triggers recovery when a threshold is reached

### 3. official repair layer
- runs `openclaw doctor --fix`
- reuses the official repair path first

### 4. AI repair layer
- collects validation errors
- generates a minimal repair script
- validates safety
- applies the fix
- validates config again
- updates safe backup
- restarts and verifies Gateway

See also:
- [`docs/architecture.md`](./docs/architecture.md)
- [`docs/architecture-diagram.md`](./docs/architecture-diagram.md)

## AI Configuration

The project supports two modes.

### Standalone repair config (preferred)

If these environment variables are present, the repair path uses them first:

```bash
export AUTO_HEAL_API_KEY="your-key"
export AUTO_HEAL_API_ENDPOINT="https://your-api-endpoint.example/v1/messages"
export AUTO_HEAL_MODEL="your-model-name"
export AUTO_HEAL_PROVIDER="external"
```

Optional advanced overrides:

```bash
export AUTO_HEAL_API_HEADER_VALUE="your-key"
export AUTO_HEAL_API_VERSION_VALUE="2023-06-01"
```

### OpenClaw model config fallback

If standalone repair credentials are not set, the script falls back to OpenClaw model settings.

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

### Optional: set standalone AI repair credentials

```bash
export AUTO_HEAL_API_KEY="your-key"
export AUTO_HEAL_API_ENDPOINT="https://your-api-endpoint.example/v1/messages"
export AUTO_HEAL_MODEL="your-model-name"
export AUTO_HEAL_PROVIDER="external"
```

### Manual checks

```bash
bash ~/.openclaw/scripts/health-check.sh
bash ~/.openclaw/scripts/auto-heal-ai.sh
```

## Dry Run and Diff

### Dry run

```bash
DRY_RUN=1 bash ~/.openclaw/scripts/auto-heal-ai.sh
```

Dry run will:

- execute the repair logic
- print config diff into logs
- **not update the safe backup**
- **not restart Gateway**
- **not run `openclaw doctor --fix`**

### Config diff

```bash
SHOW_DIFF=1 bash ~/.openclaw/scripts/auto-heal-ai.sh
```

## Security

This is a guarded self-healing prototype, not a fully trusted autonomous operations system.

Current protections include:

- dangerous-pattern blocking
- AST-level validation for generated repair code
- no network access from repair scripts
- no subprocess execution from repair scripts
- writes restricted to the target `openclaw.json`

For more details, see [`docs/security.md`](./docs/security.md).

## Project Status

This repository is suitable for public GitHub release as an:

- experimental project
- public prototype
- early-stage open-source tool

It already has:

- a coherent recovery strategy
- an installer
- bilingual docs
- CI
- a safer execution model
- doctor-first + AI-fallback design

## Suggested GitHub Metadata

**Description**

> Self-healing runtime protection for OpenClaw Gateway with doctor-first recovery and AI fallback.

**Topics**

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
