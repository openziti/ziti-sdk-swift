This entire directory was copied from https://github.com/microsoft/vcpkg/tree/master/ports/openssl, and `unix/portfile.cmake` was modified to enable building arm64 binaries for the iphonesimulator platform:


```patch
index 98c5dcb54..a2c4daafe 100644
--- a/ports/openssl/unix/portfile.cmake
+++ b/ports/openssl/unix/portfile.cmake
@@ -61,15 +61,19 @@ elseif(VCPKG_TARGET_IS_LINUX)
         set(OPENSSL_ARCH linux-generic32)
     endif()
 elseif(VCPKG_TARGET_IS_IOS)
-    if(VCPKG_TARGET_ARCHITECTURE MATCHES "arm64")
-        set(OPENSSL_ARCH ios64-xcrun)
+    if(VCPKG_OSX_SYSROOT MATCHES "iphonesimulator")
+        set(OPENSSL_ARCH_VARIANT "simulator")
+    elseif(VCPKG_TARGET_ARCHITECTURE MATCHES "arm64")
+        set(OPENSSL_ARCH_VARIANT 64)
     elseif(VCPKG_TARGET_ARCHITECTURE MATCHES "arm")
-        set(OPENSSL_ARCH ios-xcrun)
+        set(OPENSSL_ARCH_VARIANT "")
     elseif(VCPKG_TARGET_ARCHITECTURE MATCHES "x86" OR VCPKG_TARGET_ARCHITECTURE MATCHES "x64")
-        set(OPENSSL_ARCH iossimulator-xcrun)
+        set(OPENSSL_ARCH_VARIANT simulator)
     else()
         message(FATAL_ERROR "Unknown iOS target architecture: ${VCPKG_TARGET_ARCHITECTURE}")
     endif()
+    set(OPENSSL_ARCH "ios${OPENSSL_ARCH_VARIANT}-xcrun")
+    message("using openssl arch ${OPENSSL_ARCH}")
     # disable that makes linkage error (e.g. require stderr usage)
     list(APPEND CONFIGURE_OPTIONS no-ui no-asm)
 elseif(VCPKG_TARGET_IS_OSX)
```

We should submit this change to the vcpkg project, and remove this port-overlay once it's adopted.
Note that the issue has already been reported: https://github.com/microsoft/vcpkg/issues/24468.