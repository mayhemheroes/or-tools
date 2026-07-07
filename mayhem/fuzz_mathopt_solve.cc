// Mayhem libFuzzer harness for MathOpt MPS solving (in-process replacement for
// the archived black-box mathopt_solve CLI + filepath: target).
#include <fcntl.h>
#include <stdint.h>
#include <unistd.h>

#include <string>

#include "absl/time/time.h"
#include "ortools/base/init_google.h"
#include "ortools/math_opt/cpp/math_opt.h"
#include "ortools/math_opt/io/mps_converter.h"

namespace {

void EnsureStdinClosed() {
  const int null_fd = open("/dev/null", O_RDONLY);
  if (null_fd >= 0) {
    dup2(null_fd, STDIN_FILENO);
    close(null_fd);
  }
}

void InitOnce() {
  static bool initialized = false;
  if (initialized) {
    return;
  }
  initialized = true;
  EnsureStdinClosed();
  int argc = 1;
  char arg0[] = "mathopt-solve";
  char* argv[] = {arg0, nullptr};
  char** argv_ptr = argv;
  InitGoogle(arg0, &argc, &argv_ptr, /*remove_flags=*/true);
}

}  // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 16 || size > (1 << 20)) {
    return 0;
  }
  InitOnce();

  using operations_research::math_opt::Model;
  using operations_research::math_opt::MpsToModelProto;
  using operations_research::math_opt::Solve;
  using operations_research::math_opt::SolveParameters;
  using operations_research::math_opt::SolverType;

  const std::string mps(reinterpret_cast<const char*>(data), size);
  const auto model_proto = MpsToModelProto(mps);
  if (!model_proto.ok()) {
    return 0;
  }
  const auto model = Model::FromModelProto(*model_proto);
  if (!model.ok()) {
    return 0;
  }

  SolveParameters params;
  params.time_limit = absl::Seconds(1);
  (void)Solve(**model, SolverType::kGscip, {.parameters = params});
  return 0;
}
