#!/usr/bin/env bash
set -euo pipefail

# Set REPORT_ONLY=1 to reprint existing LCOV files without rerunning the suites.

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
OUTPUT_DIR="${COVERAGE_OUTPUT_DIR:-coverage/financial_flows}"
mkdir -p "$OUTPUT_DIR"

run_coverage() {
  local name="$1"
  shift
  echo "Measuring $name coverage..."
  "$FLUTTER_BIN" test \
    --branch-coverage \
    --concurrency=1 \
    --reporter=silent \
    --coverage-path="$OUTPUT_DIR/$name.info" \
    "$@"
}

# The complete suite supplies executable-line denominators for source modules
# not loaded by an individual flow. Flow percentages below are always calculated
# from that flow's isolated test run, never from the union of all tests.
if [[ "${REPORT_ONLY:-0}" != "1" ]]; then
  SHARED_FINANCIAL_TESTS=(
    test/data/asset_repositories_test.dart
    test/data/financial_model_parsers_test.dart
    test/data/model_parsers_test.dart
    test/data/account_model_test.dart
    test/data/net_worth_achievement_test.dart
  )
  run_coverage full-suite test

run_coverage transactions \
  "${SHARED_FINANCIAL_TESTS[@]}" \
  test/data/money_test.dart \
  test/data/account_model_test.dart \
  test/data/transaction_validation_test.dart \
  test/data/account_balance_calculator_test.dart \
  test/data/app_data_snapshot_index_test.dart \
  test/data/model_parsers_test.dart \
  test/data/local_transaction_repository_test.dart \
  test/data/transaction_template_test.dart \
  test/data/google_sheets_repository_test.dart \
  test/data/repositories_test.dart \
  test/app/transaction_entry_widget_test.dart \
  test/app/transaction_builder_test.dart \
  test/app/transactions_page_test.dart \
  test/app/transactions_page_flow_test.dart \
  test/app/transactions_compact_flow_test.dart \
  test/app/transaction_list_balance_test.dart

run_coverage history-valuation \
  "${SHARED_FINANCIAL_TESTS[@]}" \
  test/data/money_test.dart \
  test/data/account_balance_calculator_test.dart \
  test/data/app_data_snapshot_index_test.dart \
  test/data/daily_maintenance_service_test.dart \
  test/data/manual_valuation_test.dart \
  test/data/google_sheets_repository_test.dart \
  test/data/repositories_test.dart \
  test/app/manual_valuation_date_test.dart \
  test/app/assets_liabilities_page_test.dart \
  test/features/analysis_calculator_test.dart

run_coverage analysis \
  "${SHARED_FINANCIAL_TESTS[@]}" \
  test/features/analysis_calculator_test.dart \
  test/features/category_analysis_test.dart \
  test/features/income_allocation_analysis_test.dart \
  test/features/analysis_page_test.dart \
  test/features/analysis_range_flow_test.dart \
  test/features/category_analysis_section_test.dart \
  test/features/analysis_graph_responsive_test.dart \
  test/features/missing_fx_analysis_page_test.dart \
  test/features/income_allocation_dialog_test.dart \
  test/data/google_sheets_repository_test.dart

run_coverage milestones \
  "${SHARED_FINANCIAL_TESTS[@]}" \
  test/data/net_worth_achievement_test.dart \
  test/features/milestones_page_test.dart \
  test/app/milestones_navigation_test.dart \
  test/data/local_dataset_store_test.dart \
  test/data/google_sheets_repository_test.dart

run_coverage migration \
  "${SHARED_FINANCIAL_TESTS[@]}" \
  test/data/google_sheets_repository_test.dart \
  test/data/migration_transactions_test.dart \
  test/data/transaction_validation_test.dart \
  test/data/model_parsers_test.dart \
  test/features/migration_assistance_test.dart

run_coverage persistence-outbox \
  "${SHARED_FINANCIAL_TESTS[@]}" \
  test/data/startup_persistence_test.dart \
  test/data/transaction_outbox_synchronizer_test.dart \
  test/data/local_dataset_store_test.dart \
  test/data/transaction_write_coordinator_test.dart \
  test/data/google_sheets_repository_test.dart \
  test/data/display_preference_manager_test.dart \
  test/app/transaction_refresh_state_test.dart \
  test/app/transactions_page_flow_test.dart
fi

python3 - "$OUTPUT_DIR" <<'PY'
from pathlib import Path
import sys

output = Path(sys.argv[1])
scopes = {
    "transactions": {
        "Financial logic (95% minimum per file)": [
            "lib/data/models/money.dart",
            "lib/data/models/transaction.dart",
            "lib/data/models/account.dart",
            "lib/data/account_balance_calculator.dart",
            "lib/data/app_data_snapshot.dart",
            "lib/data/csv/model_parsers.dart",
            "lib/data/repositories/transaction_write_validator.dart",
            "lib/app/pages/transaction_builder.dart",
        ],
        "User workflow": [
            "lib/app/pages/transaction_form_selectors.dart",
            "lib/app/pages/transaction_form.dart",
            "lib/app/pages/transaction_builder.dart",
            "lib/app/pages/transactions_page.dart",
            "lib/app/pages/transaction_list_widgets.dart",
        ],
    },
    "history-valuation": {
        "Financial logic (95% minimum per file)": [
            "lib/data/account_balance_calculator.dart",
            "lib/data/csv/model_parsers.dart",
            "lib/data/repositories/daily_maintenance_service.dart",
            "lib/data/repositories/manual_valuation_write_validator.dart",
            "lib/features/analysis/analysis_calculator.dart",
        ],
        "User workflow": ["lib/app/pages/assets_liabilities_page.dart"],
    },
    "analysis": {
        "Financial logic (95% minimum per file)": [
            "lib/features/analysis/analysis_calculator.dart",
            "lib/features/analysis/category_analysis.dart",
            "lib/features/analysis/income_allocation_analysis.dart",
            "lib/features/analysis/income_allocation_dialog.dart",
            "lib/data/csv/model_parsers.dart",
        ],
        "User workflow": [
            "lib/features/analysis/analysis_page.dart",
            "lib/features/analysis/analysis_chart_widgets.dart",
            "lib/features/analysis/category_analysis_section.dart",
            "lib/features/analysis/income_allocation_dialog.dart",
        ],
    },
    "milestones": {
        "Financial logic (95% minimum per file)": [
            "lib/data/net_worth_achievement_calculator.dart",
            "lib/data/csv/model_parsers.dart",
        ],
        "User workflow": ["lib/features/milestones/milestones_page.dart"],
    },
    "migration": {
        "Financial logic (95% minimum per file)": [
            "lib/data/repositories/migration_transactions.dart",
            "lib/data/repositories/transaction_write_validator.dart",
            "lib/data/csv/model_parsers.dart",
        ],
        "User workflow": [
            "lib/features/migration_assistance/migration_assistance_page.dart"
        ],
    },
    "persistence-outbox": {
        "Financial logic (95% minimum per file)": [
            "lib/data/repositories/startup_repository.dart",
            "lib/data/repositories/transaction_outbox_synchronizer.dart",
            "lib/data/sources/transaction_outbox_store.dart",
            "lib/data/sources/form_snapshot_store.dart",
            "lib/data/sources/local_dataset_store.dart",
        ],
        "User workflow": ["lib/app/app_shell.dart"],
    },
}


def read_lcov(path):
    records = {}
    record = None
    for line in path.read_text().splitlines():
        if line.startswith("SF:"):
            if record:
                record["branches_found"] = len(record["branch_hits"])
                records[record["source"]] = record
            record = {
                "source": line[3:],
                "lines_found": 0,
                "lines_hit": 0,
                "line_hits": {},
                "branch_hits": {},
            }
        elif record and line.startswith("LF:"):
            record["lines_found"] = int(line[3:])
        elif record and line.startswith("LH:"):
            record["lines_hit"] = int(line[3:])
        elif record and line.startswith("DA:"):
            line_number, hits = line[3:].split(",", 2)[:2]
            record["line_hits"][int(line_number)] = int(hits)
        elif record and line.startswith("BRDA:"):
            line_number, block, branch, taken = line[5:].split(",", 3)
            if taken != "-":
                key = (int(line_number), block, branch)
                record["branch_hits"][key] = int(taken)
    if record:
        record["branches_found"] = len(record["branch_hits"])
        records[record["source"]] = record
    return records


all_records = read_lcov(output / "full-suite.info")
print("\nScoped financial line/branch coverage (no cross-flow aggregate)")
failed_flows = []
for flow, groups in scopes.items():
    flow_records = read_lcov(output / f"{flow}.info")
    print(f"\n[{flow}]")
    for group, sources in groups.items():
        print(f"  {group}")
        below_minimum = []
        for source in sources:
            flow_record = flow_records.get(source)
            full_record = all_records.get(source)
            full_lines = full_record["line_hits"] if full_record else {}
            flow_lines = flow_record["line_hits"] if flow_record else {}
            denominator = len(full_lines)
            hit = sum(
                flow_lines.get(line_number, 0) > 0 for line_number in full_lines
            )
            percent = 100 * hit / denominator if denominator else 0
            full_branches = full_record["branch_hits"] if full_record else {}
            flow_branches = flow_record["branch_hits"] if flow_record else {}
            branches_found = len(full_branches)
            branches_hit = sum(
                flow_branches.get(branch, 0) > 0 for branch in full_branches
            )
            marker = "" if flow_record else " [not exercised by this flow]"
            branch_percent = (
                f"{100 * branches_hit / branches_found:5.1f}% branches "
                f"({branches_hit}/{branches_found})"
                if branches_found
                else "no branches"
            )
            print(
                f"    {percent:6.2f}% lines ({hit}/{denominator}); "
                f"{branch_percent} {source}{marker}"
            )
            if "95% minimum" in group and percent < 95:
                below_minimum.append(source)
        if below_minimum:
            failed_flows.append(flow)

print("\nShared financial adapters (95% line minimum; each file checked separately)")
shared_failures = []
for source in [
    "lib/data/csv/model_parsers.dart",
    "lib/data/repositories/asset_repositories.dart",
    "lib/data/repositories/google_sheets_repository.dart",
]:
    record = all_records.get(source)
    if not record:
        print(f"  no coverage data: {source}")
        continue
    line_total = len(record["line_hits"])
    line_hit = sum(value > 0 for value in record["line_hits"].values())
    branches = record["branch_hits"]
    branch_total = len(branches)
    branch_hit = sum(value > 0 for value in branches.values())
    line_percent = 100 * line_hit / line_total if line_total else 0
    branch_percent = 100 * branch_hit / branch_total if branch_total else 0
    print(
        f"  {line_percent:6.2f}% lines ({line_hit}/{line_total}); "
        f"{branch_percent:5.1f}% branches ({branch_hit}/{branch_total}) {source}"
    )
    if line_percent < 95:
        shared_failures.append(source)

if failed_flows or shared_failures:
    print("\nFinancial files below the 95% line-coverage minimum:")
    for flow in dict.fromkeys(failed_flows):
        print(f"  {flow}")
    for source in shared_failures:
        print(f"  shared adapter: {source}")
    sys.exit(1)
PY

printf '\nLCOV files written to %s\n' "$OUTPUT_DIR"
