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

# accrue these based on $FOR value
xcframework_args=""

#
# iOS
#
if [ "${FOR}" = "All" ] || [ "${FOR}" = "iOS" ] ; then
   xcframework_args+=" -library ${BUILD_DIR}/${CONFIGURATION}-iphoneos/${LIB_NAME}"
   xcframework_args+=" -headers ${DERIVED_BUILD_DIR}/${CONFIGURATION}-iphoneos/CZiti-iOS.build/DerivedSources"
   xcframework_args+=" -library ${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/${LIB_NAME}"
   xcframework_args+=" -headers ${DERIVED_BUILD_DIR}/${CONFIGURATION}-iphonesimulator/CZiti-iOS.build/DerivedSources"
fi

#
# macOS
#
if [ "${FOR}" = "All" ] || [ "${FOR}" = "macOS" ] ; then
   xcframework_args+=" -library ${BUILD_DIR}/${CONFIGURATION}/${LIB_NAME}"
   xcframework_args+=" -headers ${DERIVED_BUILD_DIR}/${CONFIGURATION}/CZiti-macOS.build/DerivedSources"
fi

#
# xcframework
#
echo "Creating xcframework"
echo "xcframework_args: ${xcframework_args}"
xcodebuild -create-xcframework ${xcframework_args} -output ${DIST_DIR}/CZiti.xcframework

if [ $? -ne 0 ] ; then
   echo "Unable to create xcframework"
   exit 1
fi

edit_interfaces ${DIST_DIR}/CZiti.xcframework

echo "Done creating ${DIST_DIR}/CZiti.xcframework"
