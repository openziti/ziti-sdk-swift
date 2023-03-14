#!/bin/sh

#
# Requires on path:
#   - xcodebuild
#   - cmake
#   - ninja
#
# `CONFIGURATION=Debug /bin/sh $0` to build Debug configuration
#

PROJECT_ROOT=$(cd `dirname $0` && pwd)
DERIVED_DATA_PATH="${PROJECT_ROOT}/DerivedData/CZiti"
C_SDK_ROOT="${PROJECT_ROOT}/deps/ziti-tunnel-sdk-c"
: ${CONFIGURATION:="Release"}

function do_build {
   scheme=$1
   arch=$2
   sdk=$3
   toolchain=$4

   xcode_arch_arg=""
   IFS=', ' read -r -a array <<< "$arch"
   for a in "${array[@]}" ; do
      c_sdk_build_dir=${C_SDK_ROOT}/build-${sdk}-${a}

      # nuke C SDK build dir and re-create it
      rm -rf ${c_sdk_build_dir}
      if [ $? -ne 0 ] ;  then
         echo "Unable to delete directory ${c_sdk_build_dir}"
         exit 1
      fi

      mkdir -p ${c_sdk_build_dir}
      if [ $? -ne 0 ] ;  then
         echo "Unable to create directory ${c_sdk_build_dir}"
         exit 1
      fi

      cd ${c_sdk_build_dir}
      if [[ "${toolchain}" =~ "${a}" ]] ; then
         cmake -GNinja -DCMAKE_BUILD_TYPE=${CONFIGURATION} -DMBEDTLS_FATAL_WARNINGS:BOOL=OFF -DEXCLUDE_PROGRAMS=ON -DCMAKE_TOOLCHAIN_FILE=../../toolchains/${toolchain} .. && ninja
      else
         cmake -GNinja -DCMAKE_BUILD_TYPE=${CONFIGURATION} -DMBEDTLS_FATAL_WARNINGS:BOOL=OFF -DEXCLUDE_PROGRAMS=ON .. && ninja
      fi

      if [ $? -ne 0 ] ;  then
         echo "FAILED building C SDK ${c_sdk_build_dir}"
         exit 1
      fi

      xcode_arch_arg="${xcode_arch_arg} -arch ${a}"
   done

   n_arch="${#array[@]}"
   if [ $n_arch -gt 1 ] ; then
      xcode_arch_arg="${xcode_arch_arg} ONLY_ACTIVE_ARCH=NO"
   fi


   cd ${PROJECT_ROOT}
   xcodebuild build -configuration ${CONFIGURATION} -scheme ${scheme} -derivedDataPath ${DERIVED_DATA_PATH} ${xcode_arch_arg} -sdk ${sdk}
   if [ $? -ne 0 ] ;  then
      echo "FAILED building ${scheme} ${CONFIGURATION} ${sdk} ${xcode_arch_arg}"
      exit 1
   fi
}


rm -rf ${DERIVED_DATA_PATH}
if [ $? -ne 0 ] ; then
   echo "Unable to remove ${DERIVED_DATA_PATH}"
   exit 1
fi

do_build CZiti-macOS "x86_64,arm64" macosx macOS-arm64.cmake
do_build CZiti-iOS arm64 iphoneos iOS-arm64.cmake
do_build CZiti-iOS x86_64 iphonesimulator iOS-x86_64.cmake

/bin/sh ${PROJECT_ROOT}/make_dist.sh
if [ $? -ne 0 ] ; then
   echo "Unable to create distribution"
   exit 1
fi
