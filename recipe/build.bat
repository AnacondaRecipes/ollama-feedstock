go mod edit -replace github.com/mattn/go-localereader@v0.0.1=github.com/mattn/go-localereader@v0.0.2-0.20220822084749-2491eb6c1c75 || exit 1
go mod tidy || exit 1

set CMAKE_GENERATOR=Ninja

rem Pre-apply ollama's llama.cpp compat patches (top-level source override expects
rem a pre-patched tree; see build.sh for the full explanation).
pushd %SRC_DIR%\llama.cpp-src
cmake -DPATCH_DIR=%SRC_DIR%\llama\compat -P %SRC_DIR%\llama\compat\apply-patch.cmake || exit 1
popd

set "CMAKE_BACKEND_ARGS="
if "%cuda_compiler_version%"=="" set "cuda_compiler_version=none"
if /i "%cuda_compiler_version%"=="none" (
    rem CPU-only build, no GPU backend
) else if "%cuda_compiler_version:~0,2%"=="12" (
    set "CMAKE_BACKEND_ARGS=-DOLLAMA_LLAMA_BACKENDS=cuda_v12"
) else if "%cuda_compiler_version:~0,2%"=="13" (
    set "CMAKE_BACKEND_ARGS=-DOLLAMA_LLAMA_BACKENDS=cuda_v13"
) else (
    echo unsupported CUDA version: "%cuda_compiler_version%"
    exit /b 1
)

cmake %CMAKE_ARGS% -B build -DOLLAMA_VERSION=%PKG_VERSION% -DOLLAMA_MLX_BACKENDS= -DOLLAMA_GO_OUTPUT=%LIBRARY_BIN%\ollama.exe -DFETCHCONTENT_SOURCE_DIR_LLAMA_CPP=%SRC_DIR%\llama.cpp-src %CMAKE_BACKEND_ARGS% . || exit 1
cmake --build build --parallel || exit 1
cmake --install build || exit 1

go-licenses save . --save_path="%SRC_DIR%/license-files/" || exit 1
