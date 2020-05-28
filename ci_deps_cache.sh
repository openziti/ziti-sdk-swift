#!/bin/sh

#
# deps/ziti-sdh-c is the longest part of the build in CI.
#
# This scripts caches the build to S3 and only rebuilds if the submodule hash changs
#

C_SDK_ROOT="./deps/ziti-sdk-c"

BUCKET="ziti-sdk-swift"
SDK=$1
ARCH=$2
TOOLCHAIN=$3

C_SDK_BUILD_DIR="${C_SDK_ROOT}/build-${SDK}-${ARCH}"

C_SDK_REV=`git submodule status ${C_SDK_ROOT} | cut -d' ' -f2`
C_SDK_REV_SHORT=`git rev-parse --short ${C_SDK_REV}`

echo "C_SDK_BUILD: (${C_SDK_REV_SHORT}) ${C_SDK_BUILD_DIR}"

#
# Grab from S3
#
TGZ_FILE="build-${SDK}-${ARCH}-${C_SDK_REV_SHORT}.tgz"
aws s3 cp s3://${BUCKET}/${TGZ_FILE} .

if [ -f "${TGZ_FILE}" ] ; then
   echo "${TGZ_FILE} from cache"

   tar -xvf ${TGZ_FILE}
else
   echo "Cached build ${TGZ_FILE} not found"
fi

LIBZITI_FILE="${C_SDK_BUILD_DIR}/library/libziti.a"
if [ ! -f "${LIBZITI_FILE}" ] ; then

   echo "${LIBZITI_FILE} not found.  Starting build"

   cmake -GNinja ${TOOLCHAIN} -S ${C_SDK_ROOT} -B ${C_SDK_BUILD_DIR}
   if [ $? -ne 0 ] ; then
      echo "Error on cmake -GNinja"
      exit 1
   fi

   cmake --build ${C_SDK_BUILD_DIR} --target ziti -- -j 10
   if [ $? -ne 0 ] ; then
      echo "Error on cmake --build"
      exit 1
   fi

   tar -czvf ${TGZ_FILE} ${C_SDK_BUILD_DIR}
   if [ $? -ne 0 ] ; then
      echo "Error creating ${TGZ_FILE}"
      exit 1
   fi

   echo "Uploading build cache to S3"
   aws s3 cp ${TGZ_FILE} s3://${BUCKET}/${TGZ_FILE}
fi

exit 0
