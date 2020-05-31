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

function create_framework {
   dist_dir="$1"
   derived_sources_dir="$2"
   lib1="$3"
   lib2="$4"
   module1="$5"
   module2="$6"

   echo "creating framework in ${dist_dir}"

   rm -rf ${dist_dir}
   if [ $? -ne 0 ] ; then
      echo "Unable to clean ${dist_dirs}"
      exit 1
   fi

   mkdir -p ${dist_dir}/${PROJECT_NAME}.framework/Modules/${SWIFTMODULE_NAME}
   if [ $? -ne 0 ] ; then
      echo "Unable to create ditribution dir - Modules"
      exit 1
   fi

   mkdir -p ${dist_dir}/${PROJECT_NAME}.framework/Headers
   if [ $? -ne 0 ] ; then
      echo "Unable to create ditribution dir - Headers"
      exit 1
   fi

   if [ -z "${module2}" ] ; then
      lipo -create "${lib1}" -o ${dist_dir}/${PROJECT_NAME}.framework/${PROJECT_NAME}
   else
      lipo -create "${lib1}" "${lib2}" -o ${dist_dir}/${PROJECT_NAME}.framework/${PROJECT_NAME}
   fi

   if [ $? -ne 0 ] ; then
      echo "Unable to lipo create"
      exit 1
   fi

   if [ -z "${module2}" ] ; then
      cp -r "${module1}"/* ${dist_dir}/${PROJECT_NAME}.framework/Modules/${SWIFTMODULE_NAME}
   else
      cp -r "${module1}"/* "${module2}"/* ${dist_dir}/${PROJECT_NAME}.framework/Modules/${SWIFTMODULE_NAME}
   fi

   if [ $? -ne 0 ] ; then
      echo "Unable to copy swiftmodule"
      exit 1
   fi

   cp ${derived_sources_dir}/CZiti-Swift.h ${dist_dir}/${PROJECT_NAME}.framework/Headers
   if [ $? -ne 0 ] ; then
      echo "Unable to copy -Swift.h file"
      exit 1
   fi

   echo "Done creating ${dist_dir}/${PROJECT_NAME}.framework"
}

#
# iOS
#
if [ "${FOR}" = "All" ] || [ "${FOR}" = "iOS" ] ; then
   create_framework \
      "${DIST_DIR}/iOS/${CONFIGURATION}" \
      "${DERIVED_BUILD_DIR}/${CONFIGURATION}-iphoneos/CZiti-iOS.build/DerivedSources" \
      "${BUILD_DIR}/${CONFIGURATION}-iphoneos/${LIB_NAME}" \
      "${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/${LIB_NAME}" \
      "${BUILD_DIR}/${CONFIGURATION}-iphoneos/${SWIFTMODULE_NAME}" \
      "${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/${SWIFTMODULE_NAME}"

   if [ $? -ne 0 ] ; then
      echo "Unable to create framework for iOS"
      exit 1
   fi
fi

#
# macOS
#
if [ "${FOR}" = "All" ] || [ "${FOR}" = "macOS" ] ; then
   create_framework \
      "${DIST_DIR}/macOS/${CONFIGURATION}" \
      "${DERIVED_BUILD_DIR}/${CONFIGURATION}/CZiti-macOS.build/DerivedSources" \
      "${BUILD_DIR}/${CONFIGURATION}/${LIB_NAME}" \
      "" \
      "${BUILD_DIR}/${CONFIGURATION}/${SWIFTMODULE_NAME}" \
      ""

   if [ $? -ne 0 ] ; then
      echo "Unable to create framework for macOS"
      exit 1
   fi
fi

