#!/bin/bash
set -ex

if [[ "$target_platform" == osx-* ]]; then
    export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
fi

# go-localereader v0.0.1 doesn't compile on Windows; replace with a patched fork.
go mod edit -replace github.com/mattn/go-localereader@v0.0.1=github.com/mattn/go-localereader@v0.0.2-0.20220822084749-2491eb6c1c75
go mod tidy

# The pinned llama.cpp source is a conda `source:` entry (folder: llama.cpp-src),
# not a build-time git clone. Guard against the recipe pin drifting from
# upstream's: the recipe's {{ llama_cpp_version }} must equal LLAMA_CPP_VERSION.
LLAMA_CPP_SRC="${SRC_DIR}/llama.cpp-src"
test -f "${LLAMA_CPP_SRC}/CMakeLists.txt" || { echo "pinned llama.cpp source missing at ${LLAMA_CPP_SRC}"; exit 1; }

# The top-level FETCHCONTENT_SOURCE_DIR_LLAMA_CPP contract expects a PRE-PATCHED
# tree: cmake/local.cmake always forwards -DOLLAMA_LLAMA_CPP_SKIP_COMPAT_PATCH=ON
# to the llama-server sub-build (assuming its own ExternalProject patched the
# clone — which the override path skips). Pre-apply ollama's compat patches here
# with ollama's own idempotent applier (git apply under the hood; this is why
# `git` is a build dep).
pushd "${LLAMA_CPP_SRC}"
cmake -DPATCH_DIR="${SRC_DIR}/llama/compat" -P "${SRC_DIR}/llama/compat/apply-patch.cmake"
popd

# Select the GPU backend from cuda_compiler_version. The CPU variant's sentinel is
# "none" (the gpu_variant zip), but tolerate "None"/empty too to stay robust.
CMAKE_BACKEND_ARGS=()
case "${cuda_compiler_version}" in
  12.*) CMAKE_BACKEND_ARGS=(-DOLLAMA_LLAMA_BACKENDS=cuda_v12) ;;
  13.*) CMAKE_BACKEND_ARGS=(-DOLLAMA_LLAMA_BACKENDS=cuda_v13) ;;
  none|None|"") ;;  # CPU-only build, no GPU backend
  *) echo "unsupported cuda version: '${cuda_compiler_version}'"; exit 1 ;;
esac

# The native runtime (ggml/llama.cpp built from the pinned source entry) and the
# Go binary are both produced by the cmake build. FETCHCONTENT_SOURCE_DIR_LLAMA_CPP
# points FetchContent at the conda-managed (pre-patched above) tree instead of a
# build-time git clone.
cmake ${CMAKE_ARGS} -B build \
    -DOLLAMA_VERSION="${PKG_VERSION}" \
    -DOLLAMA_MLX_BACKENDS= \
    -DHOST_CXX_COMPILER="${CXX}" \
    -DFETCHCONTENT_SOURCE_DIR_LLAMA_CPP="${LLAMA_CPP_SRC}" \
    "${CMAKE_BACKEND_ARGS[@]}" \
    .
cmake --build build --parallel ${CPU_COUNT}
cmake --install build --strip

go-licenses save . --save_path="$SRC_DIR/license-files/"
