#!/usr/bin/env bash
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TEST_BIN="/mayhem/mathopt_solve_test"
MODEL="$SRC/ortools/linear_solver/testdata/maximization.mps"

if [ ! -x "$TEST_BIN" ]; then
  echo "missing test oracle: $TEST_BIN" >&2
  emit_ctrf "mathopt-solve-oracle" 0 1 0
  exit 1
fi

OUT="$("$TEST_BIN" --input_file "$MODEL" --time_limit=10s 2>&1)" || true
if echo "$OUT" | grep -q "best primal bound: 4"; then
  emit_ctrf "mathopt-solve-oracle" 1 0 0
else
  echo "unexpected solver output:" >&2
  echo "$OUT" >&2
  emit_ctrf "mathopt-solve-oracle" 0 1 0
fi
