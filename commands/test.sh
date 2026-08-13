# shellcheck source=../lib/repo.sh
source "$MPE_CLI_ROOT/lib/repo.sh"
# shellcheck source=../lib/target.sh
source "$MPE_CLI_ROOT/lib/target.sh"
# shellcheck source=../lib/test_suites.sh
source "$MPE_CLI_ROOT/lib/test_suites.sh"
# shellcheck source=../lib/test_coverage.sh
source "$MPE_CLI_ROOT/lib/test_coverage.sh"

# Run product-repo unit tests (laptop or Pi). Agent-safe — fixed unittest invocations only.

cmd_test() {
    local arg1="${1:-}"
    local arg2="${2:-}"
    local target suite

    case "$arg1" in
        -h | --help | help)
            mpe_cli_test_usage
            return 0
            ;;
        list)
            echo "=== test suites ==="
            mpe_cli_test_suite_list
            echo ""
            echo "Usage: $MPE_CLI_NAME test [local|pi] [suite]"
            return 0
            ;;
        coverage)
            cmd_test_coverage "${2:-local}"
            return $?
            ;;
    esac

    if mpe_cli_target_is_known "$arg1"; then
        target="$(mpe_cli_normalize_target "$arg1")" || exit 1
        suite="${arg2:-all}"
    else
        target=local
        suite="${arg1:-all}"
    fi

    if ! mpe_cli_test_suite_is_valid "$suite"; then
        echo "$MPE_CLI_NAME test: unknown suite: $suite" >&2
        echo "Run '$MPE_CLI_NAME test list' for suite names." >&2
        exit 1
    fi

    local unittest_cmd
    unittest_cmd="$(mpe_cli_test_unittest_cmd "$suite")" || exit 1

    case "$target" in
        local)
            local repo
            repo="$(mpe_cli_require_local_repo)"
            mpe_cli_require_tests_dir "$repo"
            echo "=== unittest ($suite, local) ==="
            echo "Repo: $repo"
            (
                cd "$repo" || exit 1
                # shellcheck disable=SC2090
                eval "$unittest_cmd"
            )
            ;;
        pi)
            mpe_cli_require_config
            local repo
            repo="$(mpe_cli_remote_repo)"
            echo "=== unittest ($suite, Pi) ==="
            echo "Host: $PI_USER@$PI_HOST"
            echo "Repo: $repo"
            mpe_cli_remote_bash "
set -euo pipefail
$(mpe_cli_remote_repo_cd)
if [ ! -d tests ]; then
  echo 'no tests/ in '\$repo >&2
  exit 1
fi
$unittest_cmd
"
            ;;
    esac
}

# Registry drift guard: fail if the product repo has a test module that no
# suite names. Read-only; runs the same comparison locally or on the appliance.
cmd_test_coverage() {
    local target
    target="$(mpe_cli_normalize_target "${1:-local}")" || exit 1

    local check_cmd
    check_cmd="$(mpe_cli_test_coverage_cmd)"

    case "$target" in
        local)
            local repo
            repo="$(mpe_cli_require_local_repo)"
            mpe_cli_require_tests_dir "$repo"
            echo "=== suite coverage (local) ==="
            echo "Repo: $repo"
            (
                cd "$repo" || exit 1
                eval "$check_cmd"
            )
            ;;
        pi)
            mpe_cli_require_config
            echo "=== suite coverage (Pi) ==="
            echo "Host: $PI_USER@$PI_HOST"
            mpe_cli_remote_bash "
set -uo pipefail
$(mpe_cli_remote_repo_cd)
if [ ! -d tests ]; then
  echo 'no tests/ in '\$repo >&2
  exit 1
fi
$check_cmd
"
            ;;
    esac
}

mpe_cli_test_usage() {
    cat <<EOF
Usage: $MPE_CLI_NAME test [local|pi] [suite]

  test              Full suite on laptop (default)
  test local        Same
  test pi           Full suite on appliance
  test apc          Named suite on laptop
  test pi looper    Named suite on Pi
  test list         Show suite names
  test coverage     Fail if any test module belongs to no suite
  test coverage pi  Same check against the appliance checkout

Suites: $(mpe_cli_test_suite_list | tr '\n' ' ' | sed 's/ $//')

A named suite skips modules absent from the checkout (feature work lives on
unmerged branches) and reports what it skipped. A suite that matches nothing
is an error, not a pass.

Allowlist examples:
  $MPE_CLI_NAME test · $MPE_CLI_NAME test local · $MPE_CLI_NAME test pi
  $MPE_CLI_NAME test list · $MPE_CLI_NAME test coverage
  $MPE_CLI_NAME test apc · $MPE_CLI_NAME test looper · $MPE_CLI_NAME test pi apc
EOF
}
