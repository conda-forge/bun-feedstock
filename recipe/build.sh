#!/bin/bash

set -exuo pipefail

# bun needs to be on the PATH for the scripts to work
export PATH="$(pwd)/bun.native:${PATH}"

export CMAKE_AR="$(which ${AR})"
if [[ "${target_platform}" == osx-* ]]; then
  export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
  export CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_DSYMUTIL=$(which ${HOST}-dsymutil)"
  export CMAKE_LLD="$(which lld)"
  export CMAKE_STRIP="$BUILD_PREFIX/bin/llvm-strip"
else
  export CMAKE_LLD="$(which ld.lld)"
  export CMAKE_STRIP="$(which ${STRIP})"
fi

export CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_AR=${CMAKE_AR} -DCMAKE_STRIP=${CMAKE_STRIP} -DUSE_STATIC_SQLITE=OFF -DUSE_STATIC_LIBATOMIC=OFF"

# Invalid environment variable: CI="azure", please use CI=<ON|OFF>
unset CI

bun ./scripts/build.mjs -GNinja -DCMAKE_BUILD_TYPE=Release ${CMAKE_ARGS} -B build/release

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
