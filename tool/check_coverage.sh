#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
OVERALL_MIN="${OVERALL_MIN:-60}"
FINANCIAL_MIN="${FINANCIAL_MIN:-75}"

"$FLUTTER_BIN" test --coverage

if [[ ! -f coverage/lcov.info ]]; then
  echo "coverage/lcov.info was not generated." >&2
  exit 1
fi

awk -v minimum="$OVERALL_MIN" '
  /^LF:/{lf += substr($0, 4)}
  /^LH:/{lh += substr($0, 4)}
  END {
    percent = lf ? 100 * lh / lf : 0
    printf "Overall line coverage: %.2f%% (%d/%d)\n", percent, lh, lf
    if (percent < minimum) exit 1
  }
' coverage/lcov.info

awk -v minimum="$FINANCIAL_MIN" '
  /^SF:/{file = substr($0, 4)}
  /^LF:/{lf = substr($0, 4)}
  /^LH:/{
    lh = substr($0, 4)
    if (file ~ /money\.dart|transaction\.dart|daily_maintenance_service\.dart|analysis_calculator\.dart/) {
      percent = lf ? 100 * lh / lf : 0
      printf "Financial logic coverage: %.2f%% (%d/%d) %s\n", percent, lh, lf, file
      if (percent < minimum) failed = 1
    }
  }
  END { exit failed ? 1 : 0 }
' coverage/lcov.info
