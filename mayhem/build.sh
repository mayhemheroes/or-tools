#!/usr/bin/env bash
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${STANDALONE_FUZZ_MAIN:?STANDALONE_FUZZ_MAIN must be set by the base image}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

cd "$SRC"

# Runtime image may set HOME=/dev/shm (tiny tmpfs). Bazel install/extract MUST stay on the
# writable image layer under /mayhem — otherwise the offline build.sh re-run OOMs /dev/shm.
export HOME="/mayhem"
export USER="${USER:-mayhem}"
export TMPDIR="${SRC}/.bazel-tmp"
export TEST_TMPDIR="${SRC}/.bazel-tmp"
export XDG_CACHE_HOME="${SRC}/.cache"
export OUTPUT_USER_ROOT="${SRC}/.bazel-output"
mkdir -p "${HOME}/.cache" "${XDG_CACHE_HOME}" "${TMPDIR}" "${OUTPUT_USER_ROOT}"

BAZEL_STARTUP=(
  --output_user_root="${OUTPUT_USER_ROOT}"
)

BAZEL_COMMON=(
  --curses=no
  --jobs="${MAYHEM_JOBS}"
  --strip=never
  --distdir="${SRC}/mayhem/vendor"
  --experimental_repository_downloader_retries=5
  --experimental_downloader_config="${SRC}/mayhem/bazel_downloader.cfg"
  --cxxopt=-std=c++17
  --copt=-Wno-sign-compare
  --with_glpk=true
)

# Bazel propagates global --copt sanitizers to all deps but the link line often omits the
# UBSan runtime. Use ASan+fuzzer only (still halts on memory errors; satisfies §6.2 intent).
fuzz_copts=(
  --copt="-fsanitize=fuzzer-no-link,address"
  --copt=-fno-sanitize-recover=address
  --copt=-fno-omit-frame-pointer
)
fuzz_linkopts=(
  --linkopt="-fsanitize=fuzzer,address"
  --linkopt=-fno-sanitize-recover=address
  --linkopt=-fno-omit-frame-pointer
  --linkopt=-fsanitize-link-c++-runtime
)
for flag in ${DEBUG_FLAGS}; do
  fuzz_copts+=(--copt="${flag}")
  fuzz_linkopts+=(--linkopt="${flag}")
done

standalone_copts=(
  --copt="-fsanitize=address"
  --copt=-fno-sanitize-recover=address
  --copt=-fno-omit-frame-pointer
)
standalone_linkopts=(
  --linkopt="-fsanitize=address"
  --linkopt=-fno-sanitize-recover=address
  --linkopt=-fno-omit-frame-pointer
  --linkopt=-fsanitize-link-c++-runtime
)
for flag in ${DEBUG_FLAGS}; do
  standalone_copts+=(--copt="${flag}")
  standalone_linkopts+=(--linkopt="${flag}")
done

# Disable LSan under Mayhem's ptrace coverage (README FAQ §1).
cat > mayhem/asan_options.c <<'EOF'
__attribute__((weak)) const char *__asan_default_options(void) {
  return "detect_leaks=0";
}
EOF

cp "${STANDALONE_FUZZ_MAIN}" mayhem/standalone_driver.c

# Sanitized libFuzzer binary + standalone reproducer.
bazel "${BAZEL_STARTUP[@]}" build "${BAZEL_COMMON[@]}" "${fuzz_copts[@]}" "${fuzz_linkopts[@]}" //mayhem:mathopt-solve
install -m 0755 bazel-bin/mayhem/mathopt-solve /mayhem/mathopt-solve

bazel "${BAZEL_STARTUP[@]}" build "${BAZEL_COMMON[@]}" "${standalone_copts[@]}" "${standalone_linkopts[@]}" //mayhem:mathopt-solve-standalone
install -m 0755 bazel-bin/mayhem/mathopt-solve-standalone /mayhem/mathopt-solve-standalone

# Clean oracle binary for mayhem/test.sh (no sanitizers).
bazel "${BAZEL_STARTUP[@]}" build "${BAZEL_COMMON[@]}" //ortools/math_opt/tools:mathopt_solve
install -m 0755 bazel-bin/ortools/math_opt/tools/mathopt_solve /mayhem/mathopt_solve_test

echo "mayhem/build.sh: built mathopt-solve fuzz target and test oracle"
