# Drift guard for the hand-maintained suite registry in lib/test_suites.sh.
#
# The registry is typed by hand, so it goes stale every time the product repo
# adds a test module: the named suite still passes while the new module is
# never run. This check fails when a module exists in the product repo's tests/
# but is named by no suite.
#
# It makes the same check for shell tests against CI. Those have no registry
# here — `mpe test all` globs them — so the drift that matters is a tests/*.sh
# the workflow never invokes: a test that exists, passes locally, and gates
# nothing on a PR.
#
# Shell only — no python, no jq, no network. The comparison is emitted as a
# script so it runs identically against a laptop clone and the appliance.

# Emit the coverage check for the repo cwd. The registered-module list is
# interpolated from the registry, never from argv.
mpe_cli_test_coverage_cmd() {
    local registered
    registered="$(mpe_cli_test_all_registered_modules | tr '\n' ' ')"

    cat <<EOF
_mpe_registered=" $registered"
_mpe_unhomed=""
_mpe_absent=""
_mpe_found=0

for _mpe_f in tests/test_*.py; do
    [ -e "\$_mpe_f" ] || continue
    _mpe_found=\$((_mpe_found + 1))
    _mpe_base="\${_mpe_f##*/}"
    _mpe_base="\${_mpe_base%.py}"
    case "\$_mpe_registered" in
        *" \$_mpe_base "*) ;;
        *) _mpe_unhomed="\$_mpe_unhomed \$_mpe_base" ;;
    esac
done

if [ "\$_mpe_found" -eq 0 ]; then
    echo "error: no tests/test_*.py found — wrong repo?" >&2
    exit 1
fi

for _mpe_m in \$_mpe_registered; do
    [ -f "tests/\$_mpe_m.py" ] || _mpe_absent="\$_mpe_absent \$_mpe_m"
done

echo "test modules in checkout: \$_mpe_found"

if [ -n "\$_mpe_absent" ]; then
    _mpe_n=0
    for _mpe_m in \$_mpe_absent; do _mpe_n=\$((_mpe_n + 1)); done
    echo "registered but absent here (\$_mpe_n, on unmerged branches — not a failure):\$_mpe_absent"
fi

# Shell tests have no registry — 'mpe test all' globs them. The gap a glob
# cannot see is CI: a tests/*.sh that the workflow never invokes is a test
# nobody runs on a PR, which is the same false green in a different file type.
_mpe_wf=".github/workflows/test.yml"
_mpe_sh_unrun=""
_mpe_sh_count=0
for _mpe_f in tests/test_*.sh; do
    [ -e "\$_mpe_f" ] || continue
    _mpe_sh_count=\$((_mpe_sh_count + 1))
    if [ -f "\$_mpe_wf" ] && ! grep -qF "\$_mpe_f" "\$_mpe_wf"; then
        _mpe_sh_unrun="\$_mpe_sh_unrun \$_mpe_f"
    fi
done

_mpe_sh_checked=1
if [ "\$_mpe_sh_count" -gt 0 ]; then
    echo "shell tests in checkout: \$_mpe_sh_count"
    if [ ! -f "\$_mpe_wf" ]; then
        _mpe_sh_checked=0
        echo "note: \$_mpe_wf absent — CI drift check skipped, not passed" >&2
    fi
fi

_mpe_fail=0

if [ -n "\$_mpe_unhomed" ]; then
    echo ""
    echo "FAIL: test modules reachable from no suite:" >&2
    for _mpe_m in \$_mpe_unhomed; do echo "  - \$_mpe_m" >&2; done
    echo "" >&2
    echo "Add each to a suite in lib/test_suites.sh (mpe-cli repo)." >&2
    _mpe_fail=1
fi

if [ -n "\$_mpe_sh_unrun" ]; then
    echo ""
    echo "FAIL: shell tests not invoked by CI:" >&2
    for _mpe_f in \$_mpe_sh_unrun; do echo "  - \$_mpe_f" >&2; done
    echo "" >&2
    echo "Add each to the shell-tests job in \$_mpe_wf (product repo)." >&2
    _mpe_fail=1
fi

if [ "\$_mpe_fail" -ne 0 ]; then
    exit 1
fi

echo ""
if [ "\$_mpe_sh_checked" -eq 1 ]; then
    echo "OK: every test module is reachable from a suite, and CI runs every shell test."
else
    echo "OK: every test module is reachable from a suite. Shell-test CI coverage unverified."
fi
EOF
}
