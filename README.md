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

**Before first public push:** `./scripts/secret-scan.sh` (requires [gitleaks](https://github.com/gitleaks/gitleaks)). Optional pre-commit: `./scripts/install-git-hooks.sh`.

## Commands

```bash
mpe ping
mpe status
mpe logs touch -n 80
mpe osc-check
mpe diagnose
mpe sysinfo                # board, kernel/preempt, EEPROM, RT limits, buffer latency
mpe test                   # full unit test suite on laptop (allowlist-friendly)
mpe test pi                # full suite on appliance
mpe test list              # named suite registry
mpe test apc               # example: APC + control-surface tests only
mpe test pi looper         # example: looper tests on Pi
mpe test coverage          # fail if a test module belongs to no suite
mpe version                # print CLI version
mpe version --check 1.1.0  # exit 1 if the installed CLI is older
mpe midi-list              # USB + MIDI port snapshot (read-only)
mpe restart surge          # or touch | all
mpe record                 # Ctrl+C to stop
mpe pull-videos -o ~/Videos --delete-source
```

### Test suites

Named suites are a fixed registry in [`lib/test_suites.sh`](lib/test_suites.sh) — module
paths never come from argv. Two properties keep the registry honest:

- **`mpe test coverage`** fails when the product repo has a test module that no
  suite names. Run it whenever tests are added; the registry cannot silently
  fall behind.
- A named suite **skips modules absent from the checkout** (feature work lives on
  unmerged branches) and says which it skipped. A suite matching *nothing* is an
  error, never a vacuous pass.

### Version pinning

Consuming repos assert a floor so a stale CLI can't produce misleading results:

```bash
mpe version --check 1.1.0 || exit 1   # 0 = ok, 1 = too old, 2 = bad input
```

Bump `MPE_CLI_VERSION` in [`bin/mpe`](bin/mpe) on any change a consumer may pin
against: a new subcommand, a new suite, or a changed exit-code contract.

## Architecture

| Layer | Repo | Role |
|-------|------|------|
| **CLI (this repo)** | `mpe-cli` | SSH allowlist boundary on the laptop |
| **Appliance** | e.g. `MPE-Module` on device | Services, scripts, diagnostics |

Config: `~/.config/mpe/mpe.env` — not inside the product workspace.

See [AGENTS.md](AGENTS.md) for agent/security rules and [OM-Repo appliance-cli-pattern](https://github.com/opsMachine/OM-Repo/blob/main/Docs/appliance-cli-pattern.md) for the reusable pattern.
