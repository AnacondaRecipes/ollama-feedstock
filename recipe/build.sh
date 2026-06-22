#!/bin/bash
set -ex

# Host compiler for the build-time llama-ui-embed tool (forwarded by
# 0001-cmake-forward-cross-compilation-vars.patch). Defaults to the conda C++
# compiler; overridden on macOS below.
HOST_CXX="${CXX}"

if [[ "$target_platform" == osx-* ]]; then
    export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
    # The llama-ui-embed host tool links the system libc++. conda clang's libc++
    # headers are far newer than AR's macOS SDK (12.1) runtime, so the tool
    # references symbols (std::__1::bad_function_call, ne200100 ABI) the old
    # libc++.dylib lacks. Build this host-only tool with Apple clang, whose libc++
    # matches the SDK runtime. The shipped binaries still use the conda toolchain.
    HOST_CXX="/usr/bin/clang++"
fi

# go-localereader v0.0.1 doesn't compile on Windows; replace with a patched fork.
go mod edit -replace github.com/mattn/go-localereader@v0.0.1=github.com/mattn/go-localereader@v0.0.2-0.20220822084749-2491eb6c1c75
go mod tidy

# Select the GPU backend from cuda_compiler_version. The CPU variant's sentinel is
# "none" (the gpu_variant zip), but tolerate "None"/empty too to stay robust.
CMAKE_BACKEND_ARGS=()
case "${cuda_compiler_version}" in
  12.*) CMAKE_BACKEND_ARGS=(-DOLLAMA_LLAMA_BACKENDS=cuda_v12) ;;
  13.*) CMAKE_BACKEND_ARGS=(-DOLLAMA_LLAMA_BACKENDS=cuda_v13) ;;
  none|None|"") ;;  # CPU-only build, no GPU backend
  *) echo "unsupported cuda version: '${cuda_compiler_version}'"; exit 1 ;;
esac

# The native runtime (ggml/llama.cpp built from the pinned LLAMA_CPP_VERSION via
# cmake FetchContent) and the Go binary are both produced by the cmake build.
cmake ${CMAKE_ARGS} -B build \
    -DOLLAMA_VERSION="${PKG_VERSION}" \
    -DOLLAMA_MLX_BACKENDS= \
    -DHOST_CXX_COMPILER="${HOST_CXX}" \
    "${CMAKE_BACKEND_ARGS[@]}" \
    .
cmake --build build --parallel ${CPU_COUNT}
cmake --install build --strip

go-licenses save . --save_path="$SRC_DIR/license-files/"
