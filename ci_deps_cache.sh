#!/bin/sh

#
# deps/ziti-sdh-c is the longest part of the build in CI.
#
# This scripts caches the build to S3 and only rebuilds if the submodule hash changs
#
# We then go ahead and build the related Xcode project and stach the DerivedData
# for future assembly into .framework
#

C_SDK_ROOT="./deps/ziti-sdk-c"

BUCKET="ziti-sdk-swift"
SCHEME=$1
SDK=$2
ARCH=$3
CFGSDK=$4
TOOLCHAIN=$5

xcode_arch_arg=""
IFS=', ' read -r -a array <<< "$ARCH"
for a in "${array[@]}" ; do

   C_SDK_BUILD_DIR="${C_SDK_ROOT}/build-${a}-${ARCH}"

   C_SDK_REV=`git submodule status ${C_SDK_ROOT} | cut -d' ' -f2`
   C_SDK_REV_SHORT=`git rev-parse --short ${C_SDK_REV}`

   echo "C_SDK_BUILD: (${C_SDK_REV_SHORT}) ${C_SDK_BUILD_DIR}"

   #
   # Grab from S3
   #
   TGZ_FILE="build-${SDK}-${a}-${C_SDK_REV_SHORT}.tgz"
   aws s3 cp s3://${BUCKET}/${TGZ_FILE} .

   if [ -f "${TGZ_FILE}" ] ; then
      echo "${TGZ_FILE} from cache"

      tar -xf ${TGZ_FILE}
   else
      echo "Cached build ${TGZ_FILE} not found"
   fi

   LIBZITI_FILE="${C_SDK_BUILD_DIR}/library/libziti.a"
   if [ ! -f "${LIBZITI_FILE}" ] ; then

      echo "${LIBZITI_FILE} not found.  Starting build"

      toolchain=""
      if [[ "${TOOLCHAIN}" =~ "${a}" ]] ; then
         toolchain="${TOOLCHAIN}"
      fi

      cmake -GNinja ${toolchain} -S ${C_SDK_ROOT} -B ${C_SDK_BUILD_DIR}
      if [ $? -ne 0 ] ; then
         echo "Error on cmake -GNinja"
         exit 1
      fi

      cmake --build ${C_SDK_BUILD_DIR} --target ziti -- -j 10
      if [ $? -ne 0 ] ; then
         echo "Error on cmake --build"
         exit 1
      fi

      tar -czf ${TGZ_FILE} ${C_SDK_BUILD_DIR}
      if [ $? -ne 0 ] ; then
         echo "Error creating ${TGZ_FILE}"
         exit 1
      fi

      echo "Uploading build cache to S3"
      aws s3 cp ${TGZ_FILE} s3://${BUCKET}/${TGZ_FILE}
   fi

   xcode_arch_arg="${xcode_arch_arg} -arch ${a}"
done

n_arch="${#array[@]}"
if [ $n_arch -gt 1 ] ; then
   xcode_arch_arg="${xcode_arch_arg} ONLY_ACTIVE_ARCH=NO"
fi

xcodebuild build -configuration Release -scheme ${SCHEME} -derivedDataPath ./DerivedData/CZiti ${xcode_arch_arg} -sdk ${SDK}
if [ $? -ne 0 ] ; then
   echo "xcodebuild failed"
   exit 1
fi

MYLIBDIR="DerivedData/CZiti/Build/Products/${CFGSDK}"
aws s3 sync "${TRAVIS_BUILD_DIR}/${MYLIBDIR}" s3://ziti-sdk-swift/DerivedData-${TRAVIS_BUILD_NUMBER}/${MYLIBDIR}
if [ $? -ne 0 ] ; then
   echo "aws sync of ${MYLIBDIR} failed"
   exit 1
fi

MYDSDIR="DerivedData/CZiti/Build/Intermediates.noindex/CZiti.build/${CFGSDK}/${SCHEME}.build/DerivedSources"
aws s3 sync "${TRAVIS_BUILD_DIR}/${MYDSDIR}" s3://ziti-sdk-swift/DerivedData-${TRAVIS_BUILD_NUMBER}/${MYDSDIR}
if [ $? -ne 0 ] ; then
   echo "aws sync of ${MYDSDIR} failed"
   exit 1
fi

exit 0
