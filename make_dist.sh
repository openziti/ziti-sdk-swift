#!/bin/sh 

PROJECT_ROOT=$(cd `dirname $0` && pwd)
BUILD_DIR="${PROJECT_ROOT}/DerivedData/CZiti/Build/Products"
DIST_DIR="${PROJECT_ROOT}/dist"

PROJECT_NAME="CZiti"
LIB_NAME="libCZiti.a"
SWIFTMODULE_NAME="CZiti.swiftmodule"
: ${CONFIGURATION:="Release"}


#
# iOS
#
dist_dir_ios="${DIST_DIR}/iOS/${CONFIGURATION}"
echo "creating iOS universal framework in ${dist_dir_ios}"

rm -rf ${dist_dir_ios}
if [ $? -ne 0 ] ; then
   echo "Unable to clean ${dist_dir_ios}"
   exit 1
fi

mkdir -p ${dist_dir_ios}/${PROJECT_NAME}.framework/${SWIFTMODULE_NAME}
if [ $? -ne 0 ] ; then
   echo "Unable to create iOS ditribution dir"
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
   ${dist_dir_ios}/${PROJECT_NAME}.framework/${SWIFTMODULE_NAME}

if [ $? -ne 0 ] ; then
   echo "Unable to copy swiftmodule for iOS"
   exit 1
fi

derived_sources_dir=`xcodebuild -showBuildSettings -configuration ${CONFIGURATION} -scheme CZiti-iOS -sdk iphoneos | grep DERIVED_SOURCES_DIR | cut -d= -f2`
if [ $? -ne 0 ] ; then
   echo "Unable to find DERIVED_SOURCE_DIR for iOS"
   exit 1
fi

cp ${derived_sources_dir}/CZiti-Swift.h ${dist_dir_ios}/${PROJECT_NAME}.framework
if [ $? -ne 0 ] ; then
   echo "Unable to copy -Swift.h file for iOS"
   exit 1
fi

#
# macOS
#
dist_dir_macos="${DIST_DIR}/macOS/${CONFIGURATION}"
echo "creating macOS framework in ${dist_dir_macos}"

rm -rf ${dist_dir_macos}
if [ $? -ne 0 ] ; then
   echo "Unable to clean ${dist_dir_macos}"
   exit 1
fi

mkdir -p ${dist_dir_macos}/${PROJECT_NAME}.framework/${SWIFTMODULE_NAME}
if [ $? -ne 0 ] ; then
   echo "Unable to create macOS ditribution dir"
   exit 1
fi

lipo -create ${BUILD_DIR}/${CONFIGURATION}/${LIB_NAME} -o ${dist_dir_macos}/${PROJECT_NAME}.framework/${PROJECT_NAME}
if [ $? -ne 0 ] ; then
   echo "Unable to lipo create macOS"
   exit 1
fi

cp -r ${BUILD_DIR}/${CONFIGURATION}/${SWIFTMODULE_NAME}/* ${dist_dir_macos}/${PROJECT_NAME}.framework/${SWIFTMODULE_NAME}
if [ $? -ne 0 ] ; then
   echo "Unable to copy swiftmodule for macOS"
   exit 1
fi

derived_sources_dir=`xcodebuild -showBuildSettings -configuration ${CONFIGURATION} -scheme CZiti-macOS -sdk macosx | grep DERIVED_SOURCES_DIR | cut -d= -f2`
if [ $? -ne 0 ] ; then
   echo "Unable to find DERIVED_SOURCE_DIR for macOS"
   exit 1
fi

cp ${derived_sources_dir}/CZiti-Swift.h ${dist_dir_macos}/${PROJECT_NAME}.framework
if [ $? -ne 0 ] ; then
   echo "Unable to copy -Swift.h file for macOS"
   exit 1
fi
