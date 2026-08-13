# mpe-cli — agent orientation

*Security boundary for Cursor allowlists. Read before editing.*

## Purpose

**Laptop-side orchestrator** for remote appliances (e.g. MPE Pi). Product behavior lives in the appliance repo (`MPE-Module` on the device). This repo exposes **fixed subcommands** so agents can be allowlisted on `mpe ping`, `mpe status`, etc., instead of raw `ssh`/`scp`.

## Hard rules

1. **No arbitrary remote shell.** Subcommands map to fixed scripts, systemd units, or enum args — never pass user strings through to `ssh`.
2. **No host override flags.** Connection comes only from `~/.config/mpe/mpe.env` (`PI_HOST`, `PI_USER`, `SSH_KEY`).
3. **New commands:** enum-only targets where possible; cap numeric args (e.g. log lines ≤ 200). Test suites live in `lib/test_suites.sh` — add names there, never pass arbitrary module paths from argv.
4. **Document allowlist strings** — exact invocations agents may run (include common `mpe test <suite>` names).
5. **Edits to this repo require Mitch approval** — allowlists trust these entrypoints; changing them is a security event.
6. **Do not edit `~/.config/mpe/mpe.env` without approval** — retargeting the host bypasses allowlist intent.
7. **Registry coverage:** when the product repo gains a test module, add it to a suite and confirm `mpe test coverage` passes. A suite that expands to nothing must error, not report success — a green run that tested nothing is the failure mode this CLI exists to prevent. The same rule covers *partial* runs (exit 3) and shell tests: a `tests/*.sh` that CI never invokes fails `coverage`. When adding a code path that can decline to run something, make it exit non-zero by default and require an explicit flag to accept the gap.
8. **Version bumps:** raise `MPE_CLI_VERSION` in `bin/mpe` whenever a consumer could pin against the change (new subcommand, new suite, changed exit codes). Consumers assert it with `mpe version --check <x.y.z>`.

## Adding a subcommand

1. Add `commands/<name>.sh` with `cmd_<name>()` (use underscores in function names for hyphenated commands).
2. Register in `bin/mpe` dispatcher `case` — no dynamic loading from user input.
3. Document in `README.md` and the product repo’s `COMMANDS.md` / `AGENTS.md`.
4. Propose the **exact allowlist strings** for Cursor (e.g. `mpe logs touch`).

## Suggest new entries

When the same remote operation would be reached twice via improvised SSH, **propose a subcommand here** instead of expanding allowlists to raw SSH.

Pattern doc: [OM-Repo `Docs/appliance-cli-pattern.md`](https://github.com/opsMachine/OM-Repo/blob/main/Docs/appliance-cli-pattern.md)
