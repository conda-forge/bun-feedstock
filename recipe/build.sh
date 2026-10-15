#!/bin/bash

set -exuo pipefail

# bun needs to be on the PATH for the scripts to work
export PATH="$(pwd)/bun.native:${PATH}"

# The build scripts look up unprefixed LLVM tools (clang, clang++, llvm-ar, ...)
# in $BUN_TOOLCHAIN_LLVM/bin. Point them at conda's compiler wrappers, which
# already carry the target triple, sysroot and flags of the build environment.
toolchain="${SRC_DIR}/conda-toolchain"
mkdir -p "${toolchain}/bin"
# bun's build ignores LDFLAGS, so add them to link invocations (e.g. to link
# against libcxx/libstdcxx from $PREFIX instead of the system's).
# rust's compiler activation pulls in gcc, which overrides CC, so use CLANG/CLANGXX.
for wrapper in clang:"${CLANG:-${CC}}" clang++:"${CLANGXX:-${CXX}}"; do
  cat > "${toolchain}/bin/${wrapper%%:*}" <<EOF
#!/bin/bash
for arg in "\$@"; do
  case "\$arg" in
    -c|-E|-S|-M|-MM|-print-*|--version) exec ${wrapper#*:} "\$@" ;;
  esac
done
exec ${wrapper#*:} "\$@" ${LDFLAGS}
EOF
  chmod +x "${toolchain}/bin/${wrapper%%:*}"
done
if [[ "${target_platform}" == linux-* ]]; then
  # GNU strip is looked up on PATH
  ln -sf "$(command -v "${STRIP}")" "${toolchain}/bin/strip"
fi
for tool in llvm-ar llvm-ranlib llvm-nm llvm-strip dsymutil ld.lld; do
  if [[ -x "${BUILD_PREFIX}/bin/${tool}" ]]; then
    ln -sf "${BUILD_PREFIX}/bin/${tool}" "${toolchain}/bin/${tool}"
  fi
done
export BUN_TOOLCHAIN_LLVM="${toolchain}"
if [[ "${target_platform}" == linux-* ]]; then
  # Compilers for build-time host tools and the Rust host linker (gcc's
  # activation overrides CC_FOR_BUILD as well)
  export CC_FOR_BUILD="${CONDA_TOOLCHAIN_BUILD}-clang"
  export CXX_FOR_BUILD="${CONDA_TOOLCHAIN_BUILD}-clang++"
fi
export PATH="${toolchain}/bin:${PATH}"

# Use conda-forge's stable Rust; bun's build relies on nightly-only flags.
export BUN_TOOLCHAIN_RUST="${BUILD_PREFIX}"
export RUSTC_BOOTSTRAP=1

# Use the unpatched upstream dependencies from $PREFIX instead of building
# the vendored copies (patch 0007). sqlite is only built on Linux; macOS
# loads the system's libsqlite3 at runtime.
export BUN_SYSTEM_DEPS="brotli,hdrhistogram,highway,libdeflate,libjpeg-turbo,libwebp,lshpack,sqlite,zlib,zstd"
export BUN_SYSTEM_DEPS_PREFIX="${PREFIX}"

# GIT_SHA (set in recipe.yaml) is the build revision; these would take precedence
unset CI BUILDKITE_COMMIT GITHUB_SHA

build_args=(
  --profile=release
  --canary=off
  --build-dir=build/release
  --cache-dir="${SRC_DIR}/.bun-cache"
  --static-libatomic=off
)
if [[ "${target_platform}" == osx-* ]]; then
  build_args+=(--osx-deployment-target="${MACOSX_DEPLOYMENT_TARGET}")
fi
if [[ "${target_platform}" == "linux-aarch64" ]]; then
  build_args+=(--os=linux --arch=aarch64 --abi=gnu)
fi

bun ./scripts/build.ts "${build_args[@]}"

mkdir -p $PREFIX/bin
cp build/release/bun $PREFIX/bin/bun

ln -sf bun $PREFIX/bin/bunx

# The shell completion text is architecture-independent. On cross-builds,
# use the native Bun bootstrap binary instead of trying to execute the target binary.
completion_bun="$PREFIX/bin/bun"
if [[ "${build_platform}" != "${target_platform}" ]]; then
  completion_bun="$(pwd)/bun.native/bun"
fi

# completions
mkdir -p $PREFIX/share/zsh/site-functions
SHELL=zsh "$completion_bun" completions > $PREFIX/share/zsh/site-functions/_bun
grep -q '_bun_add_completion' $PREFIX/share/zsh/site-functions/_bun
mkdir -p $PREFIX/share/bash-completion/completions
SHELL=bash "$completion_bun" completions > $PREFIX/share/bash-completion/completions/bun
grep -q '_file_arguments()' $PREFIX/share/bash-completion/completions/bun
mkdir -p $PREFIX/share/fish/vendor_completions.d
SHELL=fish "$completion_bun" completions > $PREFIX/share/fish/vendor_completions.d/bun.fish
grep -q '__fish__get_bun_bins' $PREFIX/share/fish/vendor_completions.d/bun.fish

# licenses
cargo-bundle-licenses --format yaml --output THIRDPARTY.yml
mkdir -p vendored-licenses
for dep in vendor/*/; do
  dep_name="$(basename "${dep}")"
  for license in "${dep}"{LICENSE,LICENCE,COPYING,NOTICE}*; do
    if [[ -f "${license}" ]]; then
      cp "${license}" "vendored-licenses/${dep_name}-$(basename "${license}")"
    fi
  done
done
