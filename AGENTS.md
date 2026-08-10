# mpe-cli — agent orientation

*Security boundary for Cursor allowlists. Read before editing.*

## Purpose

**Laptop-side orchestrator** for remote appliances (e.g. MPE Pi). Product behavior lives in the appliance repo (`MPE-Module` on the device). This repo exposes **fixed subcommands** so agents can be allowlisted on `mpe ping`, `mpe status`, etc., instead of raw `ssh`/`scp`.

## Hard rules

1. **No arbitrary remote shell.** Subcommands map to fixed scripts, systemd units, or enum args — never pass user strings through to `ssh`.
2. **No host override flags.** Connection comes only from `~/.config/mpe/mpe.env` (`PI_HOST`, `PI_USER`, `SSH_KEY`).
3. **New commands:** enum-only targets where possible; cap numeric args (e.g. log lines ≤ 200).
4. **Edits to this repo require Mitch approval** — allowlists trust these entrypoints; changing them is a security event.
5. **Do not edit `~/.config/mpe/mpe.env` without approval** — retargeting the host bypasses allowlist intent.

## Adding a subcommand

1. Add `commands/<name>.sh` with `cmd_<name>()` (use underscores in function names for hyphenated commands).
2. Register in `bin/mpe` dispatcher `case` — no dynamic loading from user input.
3. Document in `README.md` and the product repo’s `COMMANDS.md` / `AGENTS.md`.
4. Propose the **exact allowlist strings** for Cursor (e.g. `mpe logs touch`).

## Suggest new entries

When the same remote operation would be reached twice via improvised SSH, **propose a subcommand here** instead of expanding allowlists to raw SSH.

Pattern doc: [OM-Repo `Docs/appliance-cli-pattern.md`](https://github.com/opsMachine/OM-Repo/blob/main/Docs/appliance-cli-pattern.md)
