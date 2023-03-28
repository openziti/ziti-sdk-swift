# build-macOS-x86_64

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(ZITI_BUILD_TESTS OFF CACHE BOOL "" FORCE)

SET(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -arch x86_64")
SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -arch x86_64")

# for libsodium
set(triple x86_64-apple-macos11)
execute_process(COMMAND /usr/bin/xcrun -sdk macosx --show-sdk-path
                OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
                OUTPUT_STRIP_TRAILING_WHITESPACE)

set(ENV{CFLAGS} "-arch x86_64 -isysroot ${CMAKE_OSX_SYSROOT}")
set(ENV{LDFLAGS} "-arch x86_64 -isysroot ${CMAKE_OSX_SYSROOT}")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
