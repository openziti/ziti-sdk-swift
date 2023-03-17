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

function edit_interfaces {
   module_dir="$1"

   # Edit the .swiftinterface files to remove import of CZitiPrivate
   find ${module_dir} -name '*.swiftinterface' -print0 |
   while IFS= read -r -d '' i; do
      echo "Editing file: $i"
      sed 's/^import CZitiPrivate$/\/\/ import CZitiPrivate/' $i > $i.bak && mv $i.bak $i
      if [ $? -ne 0 ] ; then
         echo "Unable to edit ${i}"
         exit 1
      fi
   done
}

function create_framework {
   pod_name="$1"
   dist_dir="$2"
   derived_sources_dir="$3"
   lib1="$4"
   lib2="$5"
   module1="$6"
   module2="$7"

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

   # Edit the .swiftinterface files to remove import of CZitiPrivate
   edit_interfaces "${dist_dir}/${PROJECT_NAME}.framework/Modules/${SWIFTMODULE_NAME}"

   cp ${derived_sources_dir}/CZiti-Swift.h ${dist_dir}/${PROJECT_NAME}.framework/Headers
   if [ $? -ne 0 ] ; then
      echo "Unable to copy -Swift.h file"
      exit 1
   fi

   # Create the pod dir (will be tgz'd on publish)
   pod_dir="${dist_dir}/Pods/${pod_name}"
   mkdir -p "${pod_dir}"
   if [ $? -ne 0 ] ; then
      echo "Unable to create pod dir"
      exit 1
   fi

   cp -r "${dist_dir}/${PROJECT_NAME}.framework" "${pod_dir}"
   if [ $? -ne 0 ] ; then
      echo "Unable to copy framework to pod dir"
      exit 1
   fi

   cp LICENSE "${pod_dir}"
   if [ $? -ne 0 ] ; then
      echo "Unable to copy LICENSE to pod dir"
      exit 1
   fi

   cp ${dist_dir}/${PROJECT_NAME}.framework/Headers/CZiti-Swift.h "${pod_dir}"
   if [ $? -ne 0 ] ; then
      echo "Unable to copy CZiti-Swift.h to pod dir"
      exit 1
   fi

   touch "${pod_dir}/SFile.swift"
   touch "${pod_dir}/OFile.m"

   echo "Done creating ${dist_dir}/${PROJECT_NAME}.framework"
}

# accrue these based on $FOR value
xcframework_args=""

#
# iOS
#
if [ "${FOR}" = "All" ] || [ "${FOR}" = "iOS" ] ; then
   create_framework "CZiti-iOS" \
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

   xcframework_args+=" -library ${BUILD_DIR}/${CONFIGURATION}-iphoneos/${LIB_NAME}"
   xcframework_args+=" -headers ${DERIVED_BUILD_DIR}/${CONFIGURATION}-iphoneos/CZiti-iOS.build/DerivedSources"
   xcframework_args+=" -library ${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/${LIB_NAME}" \
   xcframework_args+=" -headers ${DERIVED_BUILD_DIR}/${CONFIGURATION}-iphonesimulator/CZiti-iOS.build/DerivedSources"
fi

#
# macOS
#
if [ "${FOR}" = "All" ] || [ "${FOR}" = "macOS" ] ; then
   create_framework "CZiti-macOS" \
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

   xcframework_args+=" -library ${BUILD_DIR}/${CONFIGURATION}/${LIB_NAME}" \
   xcframework_args+=" -headers ${DERIVED_BUILD_DIR}/${CONFIGURATION}/CZiti-macOS.build/DerivedSources"
fi

#
# xcframework
#
echo "Creating xcframework"
xcodebuild -create-xcframework ${xcframework_args} -output ${DIST_DIR}/CZiti.xcframework

if [ $? -ne 0 ] ; then
   echo "Unable to create xcframework"
   exit 1
fi

edit_interfaces ${DIST_DIR}/CZiti.xcframework

echo "Done creating ${DIST_DIR}/CZiti.xcframework"
