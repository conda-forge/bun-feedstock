#!/bin/bash

set -exuo pipefail

# bun needs to be on the PATH for the scripts to work
export PATH="$(pwd)/bun.native:${PATH}"

# The build scripts look up unprefixed LLVM tools (clang, clang++, llvm-ar, ...)
# in $BUN_TOOLCHAIN_LLVM/bin. Point them at conda's compiler wrappers, which
# already carry the target triple, sysroot and flags of the build environment.
toolchain="${SRC_DIR}/conda-toolchain"
mkdir -p "${toolchain}/bin"
# conda's clang finds its target and config from the name it is invoked by, so
# these have to be wrappers instead of symlinks.
# rust's compiler activation pulls in gcc, which overrides CC, so use CLANG/CLANGXX.
for wrapper in clang:"${CLANG:-${CC}}" clang++:"${CLANGXX:-${CXX}}"; do
  printf '#!/bin/bash\nexec %s "$@"\n' "${wrapper#*:}" > "${toolchain}/bin/${wrapper%%:*}"
  chmod +x "${toolchain}/bin/${wrapper%%:*}"
done
# bun's build ignores LDFLAGS, so have clang append them to every invocation
# (e.g. to link against libcxx/libstdcxx from $PREFIX instead of the system's).
# The leading '#' keeps clang from printing the edits; -Qunused-arguments
# silences the warnings about them in compile-only invocations.
CCC_OVERRIDE_OPTIONS="# +-Qunused-arguments"
for flag in ${LDFLAGS}; do
  CCC_OVERRIDE_OPTIONS+=" +${flag}"
done
export CCC_OVERRIDE_OPTIONS
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

# Use conda-forge's nightly Rust instead of a rustup toolchain.
export BUN_TOOLCHAIN_RUST="${BUILD_PREFIX}"

# Use the unpatched upstream dependencies from $PREFIX instead of building
# the vendored copies (patch 0006). sqlite is only built on Linux; macOS
# loads the system's libsqlite3 at runtime. ls-hpack stays vendored: since
# 1.4.4 bun, lsquic and lsqpack build against lsxpack_header.h with
# LSXPACK_MAX_STRLEN=UINT32_MAX, which widens the length fields of
# struct lsxpack_header, so conda-forge's libls-hpack (built with the
# default UINT16_MAX) is not ABI-compatible.
export BUN_SYSTEM_DEPS="brotli,hdrhistogram,highway,libdeflate,libjpeg-turbo,libwebp,sqlite,zlib,zstd"
export BUN_SYSTEM_DEPS_PREFIX="${PREFIX}"

# bun's build switches to its own CI mode (env dumps, artifact downloads) when CI is set
unset CI

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
