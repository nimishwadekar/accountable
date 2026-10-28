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
    if (file !~ /lib\/app\/pages|lib\/app\/theme|lib\/app\/google|lib\/app\/app\.dart|lib\/app\/app_shell\.dart|lib\/data\/sources\/google|lib\/data\/sources\/form_snapshot_store\.dart|lib\/data\/sources\/transaction_outbox_store\.dart|lib\/data\/sources\/accountable_google_account\.dart|lib\/data\/sources\/google_auth_errors\.dart|lib\/data\/sources\/sheets_authorization_stub\.dart|lib\/data\/sources\/google_auth_service_stub\.dart|lib\/data\/repositories\/startup_repository\.dart|lib\/features\/analysis\/analysis_page\.dart|lib\/features\/analysis\/analysis_chart_widgets\.dart|lib\/features\/analysis\/category_analysis_section\.dart|lib\/features\/analysis\/income_allocation_dialog\.dart|lib\/features\/milestones\/milestones_page\.dart|lib\/features\/migration_assistance\/migration_assistance_page\.dart|lib\/main\.dart/) {
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
