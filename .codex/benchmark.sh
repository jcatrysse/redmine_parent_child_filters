#!/usr/bin/env bash
#
# Measures the filters against a dataset large enough to be representative, and
# writes the query plans to tmp/benchmark so two runs can be compared.
#
#   ./.codex/benchmark.sh
#   PCF_BENCH_ISSUES=50000 ./.codex/benchmark.sh
#   PCF_BENCH_NO_VISIBILITY=1 ./.codex/benchmark.sh   # cost of the visibility scoping
#   PCF_BENCH_PRINCIPALS=1 ./.codex/benchmark.sh      # mention filter at 1..1000 principals
#
# It writes to the test database prepared by test_setup.sh and leaves the rows
# behind, so a second run reuses the dataset instead of rebuilding it. Drop the
# database to start over.
#
# Environment (besides the ones test_setup.sh documents):
#   PCF_BENCH_ISSUES         issues to create (default 20000)
#   PCF_BENCH_JOURNALS       journals to create (default 100000)
#   PCF_BENCH_NO_VISIBILITY  1 to measure without the visibility scoping
#   PCF_BENCH_PRINCIPALS     1 to sweep the mention filter over 1..1000 principals
#   PCF_BENCH_REPEATS        measurements per filter, median reported (default 5)
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SCRIPT="plugins/$PLUGIN_NAME/.codex/benchmark.rb"

[ -f "$REDMINE_DIR/$SCRIPT" ] || {
  echo "ERROR: '$REDMINE_DIR/$SCRIPT' not found. Run ./.codex/redmine_clone.sh first." >&2
  exit 1
}

pcf_select_ruby quiet

export RAILS_ENV=test

run bundle exec rails runner "$SCRIPT"
