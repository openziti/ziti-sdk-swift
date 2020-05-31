#!/bin/sh 

PROJECT_ROOT=$(cd `dirname $0` && pwd)
BUILD_DIR="${PROJECT_ROOT}/DerivedData/CZiti/Build/Products"
DERIVED_BUILD_DIR="${PROJECT_ROOT}/DerivedData/CZiti/Build/Intermediates.noindex/CZiti.build"
DIST_DIR="${PROJECT_ROOT}/dist"

PROJECT_NAME="CZiti"
LIB_NAME="libCZiti.a"
SWIFTMODULE_NAME="CZiti.swiftmodule"
: ${CONFIGURATION:="Release"}

# make for iOS, macOS, or All
: ${FOR:="All"}


#
# iOS
#
if [ "${FOR}" = "All" ] || [ "${FOR}" = "iOS" ] ; then
   dist_dir_ios="${DIST_DIR}/iOS/${CONFIGURATION}"
   echo "creating iOS universal framework in ${dist_dir_ios}"

   rm -rf ${dist_dir_ios}
   if [ $? -ne 0 ] ; then
      echo "Unable to clean ${dist_dir_ios}"
      exit 1
   fi

   mkdir -p ${dist_dir_ios}/${PROJECT_NAME}.framework/Modules/${SWIFTMODULE_NAME}
   if [ $? -ne 0 ] ; then
      echo "Unable to create iOS ditribution dir = Modules"
      exit 1
   fi

   mkdir -p ${dist_dir_ios}/${PROJECT_NAME}.framework/Headers
   if [ $? -ne 0 ] ; then
      echo "Unable to create iOS ditribution dir - Headers"
      exit 1
   fi

   lipo -create ${BUILD_DIR}/${CONFIGURATION}-iphoneos/${LIB_NAME} \
      ${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/${LIB_NAME} \
      -o ${dist_dir_ios}/${PROJECT_NAME}.framework/${PROJECT_NAME}

   if [ $? -ne 0 ] ; then
      echo "Unable to lipo create iOS"
      exit 1
   fi

   cp -r ${BUILD_DIR}/${CONFIGURATION}-iphoneos/${SWIFTMODULE_NAME}/* \
      ${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/${SWIFTMODULE_NAME}/* \
      ${dist_dir_ios}/${PROJECT_NAME}.framework/Modules/${SWIFTMODULE_NAME}

   if [ $? -ne 0 ] ; then
      echo "Unable to copy swiftmodule for iOS"
      exit 1
   fi

   derived_sources_dir=${DERIVED_BUILD_DIR}/${CONFIGURATION}-iphoneos/CZiti-iOS.build/DerivedSources
   cp ${derived_sources_dir}/CZiti-Swift.h ${dist_dir_ios}/${PROJECT_NAME}.framework/Headers
   if [ $? -ne 0 ] ; then
      echo "Unable to copy -Swift.h file for iOS"
      exit 1
   fi
fi

#
# macOS
#
if [ "${FOR}" = "All" ] || [ "${FOR}" = "macOS" ] ; then
   dist_dir_macos="${DIST_DIR}/macOS/${CONFIGURATION}"
   echo "creating macOS framework in ${dist_dir_macos}"

   rm -rf ${dist_dir_macos}
   if [ $? -ne 0 ] ; then
      echo "Unable to clean ${dist_dir_macos}"
      exit 1
   fi

   mkdir -p ${dist_dir_macos}/${PROJECT_NAME}.framework/Modules/${SWIFTMODULE_NAME}
   if [ $? -ne 0 ] ; then
      echo "Unable to create macOS ditribution dir - Modules"
      exit 1
   fi

   mkdir -p ${dist_dir_macos}/${PROJECT_NAME}.framework/Headers
   if [ $? -ne 0 ] ; then
      echo "Unable to create macOS ditribution dir"
      exit 1
   fi

   lipo -create ${BUILD_DIR}/${CONFIGURATION}/${LIB_NAME} -o ${dist_dir_macos}/${PROJECT_NAME}.framework/${PROJECT_NAME}
   if [ $? -ne 0 ] ; then
      echo "Unable to lipo create macOS"
      exit 1
   fi

   cp -r ${BUILD_DIR}/${CONFIGURATION}/${SWIFTMODULE_NAME}/* ${dist_dir_macos}/${PROJECT_NAME}.framework/Modules/${SWIFTMODULE_NAME}
   if [ $? -ne 0 ] ; then
      echo "Unable to copy swiftmodule for macOS"
      exit 1
   fi

   derived_sources_dir=${DERIVED_BUILD_DIR}/${CONFIGURATION}/CZiti-macOS.build/DerivedSources
   cp ${derived_sources_dir}/CZiti-Swift.h ${dist_dir_macos}/${PROJECT_NAME}.framework/Headers
   if [ $? -ne 0 ] ; then
      echo "Unable to copy -Swift.h file for macOS"
      exit 1
   fi
fi
