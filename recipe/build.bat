@echo on
setlocal EnableDelayedExpansion

:: bun needs to be on the PATH for the scripts to work
set "PATH=%SRC_DIR%\bun.native;%PATH%"

:: Use clang-cl, lld-link, llvm-lib and llvm-rc from conda-forge's LLVM.
:: The MSVC headers and libraries come from the vs2022 activation (INCLUDE/LIB).
set "BUN_TOOLCHAIN_LLVM=%BUILD_PREFIX%\Library"

:: Use conda-forge's nightly Rust instead of a rustup toolchain.
for /f "delims=" %%i in ('rustc --print sysroot') do set "BUN_TOOLCHAIN_RUST=%%i"
if errorlevel 1 exit 1

:: Use the unpatched upstream dependencies from %LIBRARY_PREFIX% instead of
:: building the vendored copies (patch 0006), as in build.sh (which also
:: says why ls-hpack stays vendored).
set "BUN_SYSTEM_DEPS=brotli,hdrhistogram,highway,libdeflate,libjpeg-turbo,libwebp,sqlite,zlib,zstd"
set "BUN_SYSTEM_DEPS_PREFIX=%LIBRARY_PREFIX%"

:: bun's build switches to its own CI mode (env dumps, artifact downloads) when CI is set
set CI=

bun ./scripts/build.ts ^
    --profile=release ^
    --canary=off ^
    --build-dir=build/release ^
    --cache-dir="%SRC_DIR%\.bun-cache"
if errorlevel 1 exit 1

if not exist "%LIBRARY_BIN%" mkdir "%LIBRARY_BIN%"
copy /Y build\release\bun.exe "%LIBRARY_BIN%\bun.exe"
if errorlevel 1 exit 1
:: bun behaves as bunx when invoked under that name
copy /Y build\release\bun.exe "%LIBRARY_BIN%\bunx.exe"
if errorlevel 1 exit 1

:: licenses
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
if errorlevel 1 exit 1
mkdir vendored-licenses
for /d %%d in (vendor\*) do (
  for %%f in ("%%d\LICENSE*" "%%d\LICENCE*" "%%d\COPYING*" "%%d\NOTICE*") do (
    copy /Y "%%f" "vendored-licenses\%%~nxd-%%~nxf"
    if errorlevel 1 exit 1
  )
)
