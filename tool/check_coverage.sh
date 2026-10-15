#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
LOGIC_MIN="${LOGIC_MIN:-80}"
FINANCIAL_MIN="${FINANCIAL_MIN:-90}"

"$FLUTTER_BIN" test --coverage

if [[ ! -f coverage/lcov.info ]]; then
  echo "coverage/lcov.info was not generated." >&2
  exit 1
fi

awk -v minimum="$LOGIC_MIN" '
  /^SF:/{file = substr($0, 4)}
  /^LF:/{currentLf = substr($0, 4)}
  /^LH:/{
    currentLh = substr($0, 4)
    # UI composition and external OAuth/HTTP adapters are validated by widget
    # tests or manual smoke tests, not counted in the application-logic gate.
    if (file !~ /lib\/app\/pages|lib\/app\/theme|lib\/app\/google|lib\/data\/sources\/google|lib\/main\.dart/) {
      lf += currentLf
      lh += currentLh
    }
  }
  END {
    percent = lf ? 100 * lh / lf : 0
    printf "Application logic coverage: %.2f%% (%d/%d)\n", percent, lh, lf
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
