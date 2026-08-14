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
mpe test                   # unittest + shell tests on laptop (allowlist-friendly)
mpe test pi                # same on appliance
mpe test list              # named suite registry
mpe test apc               # example: APC + control-surface tests only
mpe test pi looper         # example: looper tests on Pi
mpe test looper --allow-partial   # accept a suite the branch only partly carries
mpe test coverage          # fail if a module belongs to no suite, or CI skips a shell test
mpe version                # print CLI version
mpe version --check 1.2.0  # exit 1 if the installed CLI is older
mpe midi-list              # USB + MIDI port snapshot (read-only)
mpe restart surge          # or touch | all
mpe record                 # Ctrl+C to stop
mpe pull-videos -o ~/Videos --delete-source
mpe looper sl-clips [local|pi]   # SooperLooper eval: 16 fixture WAVs (default: pi)
mpe looper sl-smoke [local|pi]   # SooperLooper eval: 16-loop load/trigger smoke (default: pi)
```

### Test suites

Named suites are a fixed registry in [`lib/test_suites.sh`](lib/test_suites.sh) — module
paths never come from argv. The design goal is narrow: **a run that did not test
what you asked for must not exit 0.** Four properties enforce it.

- **`mpe test coverage`** fails when the product repo has a test module that no
  suite names, *or* a `tests/*.sh` the CI workflow never invokes. Run it whenever
  tests are added; neither registry can silently fall behind.
- **`all` mirrors CI** — unittest discovery *plus* every `tests/test_*.sh`.
  Running only the Python half made `all` a subset of the gate while being
  described as equal to it.
- A named suite **reports modules absent from the checkout** (feature work lives
  on unmerged branches) and **exits 3** if it ran only part of itself. Pass
  `--allow-partial` to accept that deliberately.
- A suite matching *nothing* is an error, never a vacuous pass.

Exit codes for `mpe test`:

| Code | Meaning |
|------|---------|
| 0 | Everything the suite names ran, and passed |
| 1 | A test failed, or the suite matched no module at all |
| 3 | What ran passed, but part of the suite was absent from this checkout |

### Version pinning

Consuming repos assert a floor so a stale CLI can't produce misleading results:

```bash
mpe version --check 1.2.0 || exit 1   # 0 = ok, 1 = too old, 2 = bad input
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
