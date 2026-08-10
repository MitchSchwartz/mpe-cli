# mpe-cli

Laptop-side CLI for remote **appliance** operations (SSH orchestration with fixed subcommands).

First consumer: [MPE-Module](https://github.com/MitchSchwartz/MPE-Module) Raspberry Pi sound module.

## Install

```bash
git clone git@github.com:MitchSchwartz/mpe-cli.git   # or your fork
cd mpe-cli
./install.sh
```

Edit `~/.config/mpe/mpe.env` (created from `config/mpe.env.example`):

```bash
PI_HOST=raspberrypi.local
PI_USER=your-pi-username
SSH_KEY=$HOME/.ssh/your_pi_key
```

Ensure `~/.local/bin` is on your `PATH`.

## Commands

```bash
mpe ping
mpe status
mpe logs touch -n 80
mpe osc-check
mpe diagnose
mpe restart surge          # or touch | all
mpe record                 # Ctrl+C to stop
mpe pull-videos -o ~/Videos --delete-source
```

## Architecture

| Layer | Repo | Role |
|-------|------|------|
| **CLI (this repo)** | `mpe-cli` | SSH allowlist boundary on the laptop |
| **Appliance** | e.g. `MPE-Module` on device | Services, scripts, diagnostics |

Config: `~/.config/mpe/mpe.env` — not inside the product workspace.

See [AGENTS.md](AGENTS.md) for agent/security rules and [OM-Repo appliance-cli-pattern](https://github.com/opsMachine/OM-Repo/blob/main/Docs/appliance-cli-pattern.md) for the reusable pattern.
