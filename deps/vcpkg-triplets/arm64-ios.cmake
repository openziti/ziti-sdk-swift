include($ENV{VCPKG_ROOT}/triplets/community/arm64-ios.cmake)
# Force --host to differ from --build (aarch64-apple-darwin) so autoconf activates
# cross-compilation mode when building on an arm64 Mac. vcpkg-make otherwise sets
# identical --host and --build triples, causing configure to try to run iOS binaries
# on the host and fail (exit code 77).
set(VCPKG_MAKE_BUILD_TRIPLET "--host=arm-apple-darwin")
