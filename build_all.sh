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
# make for iOS, macOS, or All
: ${FOR:="All"}

function build_tsdk {
   name=$1
   toolchain=$2

   echo "Building TSDK for ${name}; toolchain:${toolchain}"
   rm -rf ./deps/ziti-tunnel-sdk-c/${name}

   cmake_build_type=RelWithDebInfo
   if [ "${CONFIGURATION}" == "Debug" ]; then cmake_build_type="Debug"; fi

   if [ -n "${ASAN_ENABLED}" -a "${FOR}" = "macOS" ]; then
       clang_asan_flags="-DCMAKE_C_FLAGS=-fsanitize=address -DCMAKE_CXX_FLAGS=-fsanitize=address"
   fi

   cmake -DCMAKE_BUILD_TYPE=${cmake_build_type} \
      ${clang_asan_flags} \
      -DTLSUV_TLSLIB=openssl \
      -DVCPKG_INSTALL_OPTIONS="--debug;--overlay-ports=./deps/vcpkg-overlays/json-c" \
      -DEXCLUDE_PROGRAMS=ON \
      -DZITI_TUNNEL_BUILD_TESTS=OFF \
      -DCMAKE_TOOLCHAIN_FILE="${toolchain}" \
      -S ./deps/ziti-tunnel-sdk-c -B ./deps/ziti-tunnel-sdk-c/${name}

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

   if [ -n "${ASAN_ENABLED}" -a "${FOR}" = "macOS" ]; then
       asan_flags="-enableAddressSanitizer YES"
   fi

   echo "Building ${scheme} ${sdk}"
   set -o pipefail && xcodebuild build \
      -derivedDataPath ./DerivedData/CZiti \
      -configuration ${CONFIGURATION} \
      -scheme ${scheme} \
      ${arch_flags} \
      ${asan_flags} \
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
if [ "${FOR}" = "All" ] || [ "${FOR}" = "iOS" ] ; then
   build_tsdk 'build-iphoneos-arm64' "${toolchain_dir}/iOS-arm64.cmake"
   build_tsdk 'build-iphonesimulator-x86_64' "${toolchain_dir}/iOS-Simulator-x86_64.cmake"
   build_tsdk 'build-iphonesimulator-arm64' "${toolchain_dir}/iOS-Simulator-arm64.cmake"
fi

if [ "${FOR}" = "All" ] || [ "${FOR}" = "macOS" ] ; then
   build_tsdk 'build-macosx-arm64' "${toolchain_dir}/macOS-arm64.cmake"
   build_tsdk 'build-macosx-x86_64' "${toolchain_dir}/macOS-x86_64.cmake"
fi


if [ "${FOR}" = "All" ] || [ "${FOR}" = "iOS" ] ; then
   build_cziti 'CZiti-iOS' 'iphoneos' '-arch arm64'
   build_cziti 'CZiti-iOS' 'iphonesimulator' '-arch x86_64 -arch arm64 ONLY_ACTIVE_ARCH=NO'
fi

if [ "${FOR}" = "All" ] || [ "${FOR}" = "macOS" ] ; then
   build_cziti 'CZiti-macOS' 'macosx' '-arch x86_64 -arch arm64 ONLY_ACTIVE_ARCH=NO'
fi

/bin/sh ${PROJECT_ROOT}/make_dist.sh
if [ $? -ne 0 ] ; then
   echo "Unable to create distribution"
   exit 1
fi
