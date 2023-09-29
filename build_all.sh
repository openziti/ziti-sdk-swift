#!/bin/sh

#
# Requires on path:
#   - xcodebuild
#   - cmake
#   - xcpretty
#
# `CONFIGURATION=Debug /bin/sh $0` to build Debug configuration
#

PROJECT_ROOT=$(cd `dirname $0` && pwd)
DERIVED_DATA_PATH="${PROJECT_ROOT}/DerivedData/CZiti"
C_SDK_ROOT="${PROJECT_ROOT}/deps/ziti-tunnel-sdk-c"
: ${CONFIGURATION:="Release"}

function build_tsdk {
   name=$1
   toolchain=$2

   echo "Building TSDK for ${name}; toolchain:${toolchain}"
   rm -rf ./deps/ziti-tunnel-sdk-c/${name}

   cmake -DCMAKE_BUILD_TYPE=${CONFIGURATION} \
      -DTLSUV_TLSLIB=mbedtls \
      -DMBEDTLS_FATAL_WARNINGS:BOOL=OFF -DEXCLUDE_PROGRAMS=ON \
      -DZITI_TUNNEL_BUILD_TESTS=OFF \
      -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
      -DDISABLE_SEMVER_VERIFICATION=ON \
      -S ./deps/ziti-tunnel-sdk-c -B ./deps/ziti-tunnel-sdk-c/${name}
 # todo remove DISABLE_SEMVER_VERIFICATION when we go back to using a released tsdk/csdk. also in CI.yml
   if [ $? -ne 0 ] ; then
      echo "Unable to cmake ${name}"
      exit 1
   fi

   cmake --build ./deps/ziti-tunnel-sdk-c/${name}
   if [ $? -ne 0 ] ; then
      echo "Unable to cmake build ${name}"
      exit 1
   fi
}

if ! command -v xcpretty > /dev/null; then
  xcpretty() { echo "install xcpretty for more legible xcodebuild output"; cat; }
fi

function build_cziti {
   scheme=$1
   sdk=$2
   arch_flags=$3

   echo "Building ${scheme} ${sdk}"
   set -o pipefail && xcodebuild build \
      -derivedDataPath ./DerivedData/CZiti \
      -configuration ${CONFIGURATION} \
      -scheme ${scheme} \
      ${arch_flags} \
      -sdk ${sdk} \
      | xcpretty

   if [ $? -ne 0 ] ; then
      echo "Unable to xcodebuild ${scheme} ${sdk}"
      exit 1
   fi
}

rm -rf ${DERIVED_DATA_PATH}
if [ $? -ne 0 ] ; then
   echo "Unable to remove ${DERIVED_DATA_PATH}"
   exit 1
fi

toolchain_dir="../../toolchains"
build_tsdk 'build-iphoneos-arm64' "${toolchain_dir}/iOS-arm64.cmake"
build_tsdk 'build-iphonesimulator-x86_64' "${toolchain_dir}/iOS-Simulator-x86_64.cmake"
build_tsdk 'build-iphonesimulator-arm64' "${toolchain_dir}/iOS-Simulator-arm64.cmake"
build_tsdk 'build-macosx-arm64' "${toolchain_dir}/macOS-arm64.cmake"
build_tsdk 'build-macosx-x86_64' "${toolchain_dir}/macOS-x86_64.cmake"

build_cziti 'CZiti-iOS' 'iphoneos' '-arch arm64'
build_cziti 'CZiti-iOS' 'iphonesimulator' '-arch x86_64 -arch arm64 ONLY_ACTIVE_ARCH=NO'
build_cziti 'CZiti-macOS' 'macosx' '-arch x86_64 -arch arm64 ONLY_ACTIVE_ARCH=NO'

/bin/sh ${PROJECT_ROOT}/make_dist.sh
if [ $? -ne 0 ] ; then
   echo "Unable to create distribution"
   exit 1
fi
