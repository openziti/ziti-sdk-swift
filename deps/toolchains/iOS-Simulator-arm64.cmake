# build-iphonesimulator-arm64

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "The list of target architectures to build")

execute_process(COMMAND /usr/bin/xcrun -sdk iphonesimulator --show-sdk-path
                OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
                OUTPUT_STRIP_TRAILING_WHITESPACE)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# work around vcpkg's openssl port assuming simulator platform should only be used when building x86_64
set(ENV{VCPKG_OVERLAY_PORTS} ${PROJECT_SOURCE_DIR}/../vcpkg-overlays)

set(VCPKG_OVERLAY_TRIPLETS ${PROJECT_SOURCE_DIR}/../vcpkg-triplets)
set(VCPKG_TARGET_TRIPLET arm64-iphonesimulator)
include($ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake)