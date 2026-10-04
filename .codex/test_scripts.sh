#!/usr/bin/env bash
#
# Tests the .codex helpers themselves.
#
#   ./.codex/test_scripts.sh
#
# This exists because of one bug that cost a silent local failure: pcf_select_ruby
# ended on `[ "$mode" = install ] && echo ...`, so in quiet mode it returned 1 and
# `set -e` in the caller killed test_plugin.sh before it ran a single spec, with no
# output at all. It only reproduced where mise is installed, so CI never saw it, and
# ShellCheck does not check what status a function returns.
#
# No Bats, no ShellSpec: a helper that has to survive `set -e` is tested by running
# it under `set -e` in a real process and looking at the exit status. Adding a test
# framework to assert that would be more machinery than the thing being asserted.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
checks=0

# A probe has to be its own process: `set -e` is suspended inside a compound
# command on the left of `||`, so testing this in-shell reports success no matter
# what the function returns. That mistake is easy to make twice.
cat > "$TMP/probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
. "$1/common.sh"
pcf_select_ruby "$2"
echo "USE_MISE=$USE_MISE RUBY_TARGET=$RUBY_TARGET"
PROBE
chmod +x "$TMP/probe.sh"

# Stands in for mise: present on PATH, does nothing, succeeds.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/mise"
chmod +x "$TMP/bin/mise"

check() {
  local label="$1" expect_mise="$2"; shift 2
  local output status
  checks=$((checks + 1))
  output="$("$@" 2>&1)"
  status=$?

  if [ "$status" -ne 0 ]; then
    echo "FAIL $label: exited $status"
    printf '%s\n' "$output" | sed 's/^/      /'
    failures=$((failures + 1))
    return
  fi

  case "$output" in
    *"USE_MISE=$expect_mise"*) echo "ok   $label" ;;
    *)
      echo "FAIL $label: expected USE_MISE=$expect_mise"
      printf '%s\n' "$output" | sed 's/^/      /'
      failures=$((failures + 1))
      ;;
  esac
}

# Absence is asserted through MISE_BIN, not by choosing a PATH that looks safe.
# The first version of this test simulated "no mise" with PATH=/usr/bin:/bin, which
# assumes mise is never installed in /usr/bin — on a machine where it is, the three
# negative checks failed, so the test measured the PATH layout of one CI runner
# rather than the behaviour it claims to. MISE_BIN is already common.sh's documented
# way to point at a mise, and an absolute path that does not exist is absence no
# host can contradict.
ABSENT_MISE="$TMP/absent/mise"

echo "pcf_select_ruby survives every mode, with and without mise"
for mode in install quiet other; do
  check "mise present, mode=$mode" 1 \
    env "MISE_BIN=$TMP/bin/mise" PCF_RUBY=3.4 "$TMP/probe.sh" "$HERE" "$mode"
  check "no mise, mode=$mode" 0 \
    env "MISE_BIN=$ABSENT_MISE" PCF_RUBY=3.4 "$TMP/probe.sh" "$HERE" "$mode"
done

# ...and that a bare name is still resolved on PATH, which is the default and the
# only case a developer actually hits. Safe on a host that has its own mise: the
# expectation is the same either way.
for mode in install quiet; do
  check "mise on PATH, mode=$mode" 1 \
    env "PATH=$TMP/bin:$PATH" PCF_RUBY=3.4 "$TMP/probe.sh" "$HERE" "$mode"
done

# The Ruby version is derived from the checkout's Gemfile, and a version that was
# never released is worse than a wrong guess: bundler fails with an error about a
# Ruby nobody can install. Redmine 7 allows "< 4.1.0", which is the case that bit.
echo
echo "pcf_detect_ruby_version stays inside what exists"
detect() {
  local constraint="$1"
  local dir="$TMP/redmine-$checks"
  mkdir -p "$dir"
  printf "source 'https://rubygems.org'\nruby %s\n" "$constraint" > "$dir/Gemfile"
  ( set -euo pipefail
    # shellcheck source-path=SCRIPTDIR
    # shellcheck source=common.sh
    . "$HERE/common.sh"
    # Read by pcf_detect_ruby_version, which is defined in the file sourced above.
    # shellcheck disable=SC2034
    REDMINE_DIR="$dir"
    unset PCF_RUBY
    pcf_detect_ruby_version )
}

expect_version() {
  local label="$1" constraint="$2" want="$3" max="${4:-3.4}" got
  checks=$((checks + 1))
  got="$(PCF_RUBY_MAX="$max" detect "$constraint")"
  if [ "$got" = "$want" ]; then
    echo "ok   $label -> $got"
  else
    echo "FAIL $label: expected $want, got '$got'"
    failures=$((failures + 1))
  fi
}

expect_version 'Redmine 5.x range'  "'>= 2.7.0', '< 3.3.0'" 3.2
expect_version 'Redmine 6.x range'  "'>= 3.1.0', '< 3.5.0'" 3.4
expect_version 'unreleased upper'   "'>= 3.2.0', '< 4.1.0'" 3.4
expect_version 'lower bound wins'   "'>= 3.4.0', '< 3.5.0'" 3.4
# The floor only shows when the cap falls below the lower bound. It used to read
# no lower bound at all from a real Gemfile line, so the cap won.
expect_version 'floor over the cap' "'>= 3.2.0', '< 4.1.0'" 3.2 3.0

expect_output() {
  local label="$1" want="$2" got; shift 2
  checks=$((checks + 1))
  got="$("$@" 2>&1)"
  if [ "$got" = "$want" ]; then
    echo "ok   $label -> '$got'"
  else
    echo "FAIL $label: expected '$want', got '$got'"
    failures=$((failures + 1))
  fi
}

# Runs a common.sh helper under the callers' `set -euo pipefail`. $1 is the
# command line, the rest are its arguments.
helper() {
  local script="$1"; shift
  bash -c 'set -euo pipefail; . "$1/common.sh"; shift; '"$script" _ "$HERE" "$@"
}

# rspec given only options looks for ./spec in the Redmine checkout, finds none
# and passes with 0 examples, so options alone must still get the spec folder.
echo
echo "pcf_rspec_targets always runs the plugin's specs"
targets() {
  # Expanded by the inner bash, not here.
  # shellcheck disable=SC2016
  helper 'pcf_rspec_targets "$@"; printf "%s|" "${PCF_RSPEC_TARGETS[@]}"' "$@"
}
spec="plugins/$(basename "$(dirname "$HERE")")/spec"
expect_output 'no arguments'      "$spec|" targets
expect_output 'options only'      "--seed|3|$spec|" targets --seed 3
expect_output 'filter only'       "-e|a b|$spec|" targets -e 'a b'
expect_output 'file and filter'   "$spec/x_spec.rb|-e|a b|" targets spec/x_spec.rb -e 'a b'
expect_output 'file with a line'  "$spec/x_spec.rb:12|" targets spec/x_spec.rb:12

# rsync matches an exclude relative to the source, so an absolute REDMINE_DIR
# inside the plugin used to be copied into itself on every run.
echo
echo "pcf_checkout_exclude matches the checkout the way rsync sees it"
plugin_root="$(cd "$HERE/.." && pwd)"
inside="$plugin_root/pcf-test-scripts-$$"
mkdir -p "$inside" "$TMP/outside"
trap 'rm -rf "$TMP" "$inside"' EXIT
# $1 is REDMINE_DIR, $2 the directory to run from.
exclude_for() {
  # Expanded by the inner bash, not here.
  # shellcheck disable=SC2016
  ( cd "${2:-$PWD}" && helper 'REDMINE_DIR="$1"; pcf_checkout_exclude' "$1" )
}
expect_output 'absolute, inside'   "/pcf-test-scripts-$$/" exclude_for "$inside"
expect_output 'relative, inside'   "/pcf-test-scripts-$$/" exclude_for "pcf-test-scripts-$$" "$plugin_root"
expect_output 'outside the plugin' '' exclude_for "$TMP/outside"
expect_output 'not cloned yet'     '' exclude_for "$TMP/missing"

echo
if [ "$failures" -eq 0 ]; then
  echo "$checks checks, 0 failures"
else
  echo "$checks checks, $failures failures"
  exit 1
fi
