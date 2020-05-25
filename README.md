# Ziti SDK for Swift
[![Build Status](https://travis-ci.com/netfoundry/ziti-sdk-swift.svg?branch=master)](https://travis-ci.com/netfoundry/ziti-sdk-swift)

An SDK for accessing Ziti from macOS and iOS applications using the Swift programming language.

This SDK provides a Swift-friendly wrapper of the [Ziti C SDK](https://netfoundry.github.io/ziti-doc/api/clang/api/index.html), an implementation of `URLProtocol` for intercepting HTTP and HTTPS traffic, and examples of using the SDK in an application.

# Usage
The `Ziti` class is the main entry point for accessing Ziti networks. An instance of `Ziti` requires a `ZitiIdentity` at time of initialization.

## Enrollment
A `ZitiIdentity` is created as part of the enrollment process with a Ziti network.  `Ziti` support enrollment using a one-time JWT supplied by your Ziti network administror.

__Swift__
```Swift
import CZiti

let jwtFile = <...>
let outFile = <...>

Ziti.enroll(jwtFile) { zid, zErr in
    guard let zid = zid else {
        fputs("Invalid enrollment response, \(String(describing: zErr))\n", stderr)
        exit(-1)
    }
    guard zid.save(outFile) else {
        fputs("Unable to save to file \(outFile)\n", stderr)
        exit(-1)
    }
    
    print("Successfully enrolled id \"\(zid.id)\" with controller \"\(zid.ztAPI)\"")
}
```
__Objective-C__
```objective-c
#import "CZiti-Swift.h"

NSString *jwtFile = <...>
NSString *outFile = <...>

[Ziti enroll:jwtFile : ^(ZitiIdentity *zid, ZitiError *zErr) {
    if (zErr != NULL) {
        // Handle error
        return;
    }

    if (![zid save:outFile]) {
        // Handle error
        return;
    }
}];
```

The `Ziti.enroll(_:)` method validates the JWT is properly signed, creates a private key and stores it in the keychain, initiates a Certificate Signing Request (CSR) with the controller, and stores the resultant certificate in the keychain.

The identity file saved to `outfile` in the example code above contains information for contacting the Ziti controller and locally accessing the private key and certificate in the keychain.

## Running Ziti

A typical application flow would:
1. Check a well-known location for a stored identity file
2. If not present, initiate an enrollment (e.g., prompt the user for location of a one-time JWT enrollment file, or scan in a QR code)
3. When identity file is available, use it to create and run an instance of `Ziti`

`Ziti` executes on a loop, similar to `Foundation`'s `Runloop`. The `run(_:_:)` method essentially enters an infinite loop processing Ziti events, and will only exit after `Ziti` is shut down.

The `runAsync(_:_:)` method is provided as a convenience to spawn a new thread and call `run(_:_:)`. 

__Swift__
```swift
let zidFile = <...>

guard let ziti = Ziti(fromFile: zidFile) else {
    print("Unable to create Ziti identity from file \(zidFile)")
    return
}

ziti.runAsync { zErr in
    guard zErr == nil else {
        print("Unable to run Ziti: \(String(describing: zErr!))")
        return
    }
    print("Successfully initialized Ziti!")
}
```
__Objective-C__
```objective-c
NSString *zidFile = <...>

Ziti *ziti = [[Ziti alloc] initFromFile:[self zidFile]];
    
if (ziti != NULL) {
    [ziti runAsync: ^(ZitiError *zErr) {
        if (zErr != NULL) {
            // Handle error
            return;
        }
        [ZitiUrlProtocol register:ziti :10000];
    }];
}
```
To execute code on the thread running Ziti use the `perform(_:)` method.

## Using `ZitiUrlProtocol`

The SDK also includes `ZitiUrlProtocol`, which implements a `URLProtocol` that interceptes HTTP and HTTPS requests for Ziti services and routes them over a Ziti network.

`ZitiUrlProtocol` should be instantiated as part of the `InitCallback` of `Ziti` `run(_:_:)` to ensure `Ziti` is initialized before
     starting to intercept services.

__Swift__
```swift
ziti.runAsync { zErr in
    guard zErr == nil else {
        // Handle error
        return
    }
    ZitiUrlProtocol.register(ziti)
}
```
__Objective-C__
```objective-C
[ziti runAsync: ^(ZitiError *zErr) {
    if (zErr != NULL) {
        // Handle error
        return;
    }
    [ZitiUrlProtocol register:ziti :10000];
}];
```

If using your own `URLSession` insteal of `URLSession.shared`, `ZitiUrlProtocol` will need to be configured in your `URLSession`'s configuration:
     
```swift
    let configuration = URLSessionConfiguration.default
    configuration.protocolClasses?.insert(ZitiUrlProtocol.self, at: 0)
    urlSession = URLSession(configuration:configuration)
```
See also the documentation included in the `CZiti` module available in the `Xcode` Quick Help pane.

## Examples
This repository includes a few examples of using the library:
- [`ziti-mac-enroller`](ziti-mac-enroller/main.swift) is a utility that will enroll an identity using a supplied one-time JWT token.  It can optionally update the keychain to trust for the CA pool used by the Ziti controller
- [`sample-mac-host`](sample-mac-host/main.swift) is a command-line utility that can operate as either a client or a server for a specified Ziti server
- [`sample-ios`](cziti.sample-ios/README.md) exercises `ZitiUrlProtocol` to intercept `URLSesson` requests, route them over Ziti, and display the results
- [`sample-ios-objc`](sample-ios-objc/README.md) demonstrates using __Objective-C__ to exercise `ZitiUrlProtocol`

# Building

## From Script

This project conains the [`buid_all.sh`](build_all.sh) script that will build the project from the command-line for `macosx`, `iphoneos`, and `iphonesimulator` platforms.

Once the static libraries are built, the `build_all.sh` script executes  [`make_dist.sh`](make_dist.sh), creating two Frameworks, each called `CZiti.framework`, under the project's `./dist` directory.
* `./dist/iOS` containes a static Universal Framework suitable for use with both the simulator and a real device.
* `./dist/macOS` contains a static Framework for use on macOS.

The scripts require the following executables to be on the caller's path:
* `xcodebuild` used to build `CZiti-*` schemes in `CZiti.xcodeproj`, avaialble as part of your `Xcode` installation
* `cmake` used for building the __Ziti C SDK__ dependency.  (Can be installed via `brew install cmake`)
* `ninja` also used for building the __Ziti C SDK__. (Can be installed via `brew install ninja`)

```bash
$ git clone --recurse-submodules git@github.com:netfoundry/ziti-sdk-swift.git
$ cd ziti-sdk-swift
$ /bin/sh build_all.sh
```

By default, the scripts build for `Release` configuration.  To build for `Debug`, execute 
```bash
$ CONFIGURATION=Debug /bin/sh build_all.sh
```

The resultant `libCZiti.a` and `CZiti.swiftmodule` are available in the appropriate sub-directory of `./DerivedData`.

Tthe resultant `CZiti.framework` is available in the approprate sub-directory of `./dist`, and include `CZiti-Swift.h` (needed to use the framework from __Objective-C__ projects).

## Build Manually

The project depends on the __Ziti C SDK__, which is built directly into the  library.  It is maintained as a submodule at `./deps/ziti-sdk-c`.  This project expects builds to be built in `./deps/ziti-sdk-c/build-macosx-x86_64` for macOS and `./deps/ziti-sdk-c/build-iphoneos-arm64` for iOS (or `build-iphonesimulator-x86_64` for the simulator).  See also the build instructions in the [`ziti-sdk-c`](https://github.com/netfoundry/ziti-sdk-c/blob/master/building.md) repository.

```
$ git clone git@github.com:netfoundry/ziti-sdk-swift.git
$ cd ziti-sdk-swift
$ git submodule update --init --recursive
$ cd deps/ziti-sdk-c
$ mkdir build-macosx-x86_64
$ cd build-macosx-x86_64
$ cmake .. && make
$ cd ..
$ mkdir build-iphoneos-arm64
$ cd build-iphoneos-arm64
$ cmake .. -DCMAKE_TOOLCHAIN_FILE=../toolchains/iOS-arm64.cmake && make
$ cd ..
$ mkdir build-iphonesimulator-X86_64
$ cd build-iphonesimulator-X86_64
$ cmake .. -DCMAKE_TOOLCHAIN_FILE=../toolchains/iOS-x86_64.cmake && make
```

Once the C SDK is built, use `CZiti.xcodeproj` to build the libraries and examples.

The [`make_dist.sh`](make_dist.sh) script will package the static library, swiftmodule, and __Objective-C__ header file (`CZiti-Swift.h`) into static frameworks found under the `./dist` directory.

# Adding `CZiti` as a Dependency

`CZiti` is built into a static library (`libCZiti.a`) and packaged as a static Framework (`CZiti.framework`).
 
Note that that `libCZiti.a` is not built for Bitcode, and when building for a device the __Build Settings - Build Options__ should set `Enable Bitcode` to `No`. 

## Via `CZiti.framework`

* Drag the appropriate `CZiti.framework` into your project, selecting "Copy items if needed", "Create groups", and your target checked under "Add to targets:".
* Ensure the framework is shown under **General - Frameworks, Libraries, and Embedded Content**. If not present, click the "+" button to add it manually.  The "Embedded" entry should be set to "Do Not Embed".
* Ensure the framework is shown under **Build Phases - Link Binary with Libraries**.  The "Status" entry should be set to "Required"
* **Build Settings - Frameworks** should include an entry of the directory containing `CZiti.framework` in your project
* For __Swift__ projects, **Build Settings - Swift Compiler - Search Paths - Import Paths** should include `CZiti.framework`
* For __Objective-C__ projets, **Build Settings - Header Search Paths** should include `CZiti.framework`, allowing your __Objective-C__ files to `import `CZiti-Swift.h` successfully.

Wnen including `CZiti` in an __Objective-C__ project, addind (an empty) Swift file to your project will help ensure your project is setup correctly for accessing __Swift__ from __Objective-C__

Coming soon: Distribution via `CocoaPods`

## Via `libCZiti.a`

Add `libCZiti.a` library to your project's **Frameworks and Libraries**, and ensure it is listed in your project's **Build Phases** under **Link Binary with Libraries**.

Your **Library Search Path** and **Swift Compiler Seatch Paths - Import Paths** should include the directory containing `libCZiti.a` and `CZiti.swiftmodule/`

When this project is built from `Xcode`, the `CZiti-Swift.h` file is copied to `$(PROJECT_ROOT)/include/$(PLATFORM)` (e.g., `./include/iphoneos`).  `CZiti-Swift.h` can also be found the the `DerivedSources` directory under `./DerivedData` following a build from either `Xcode` or via `build_all.sh`.  This file is needed to use `CZiti` from Objective-C. Your  __Search Paths - Header Search Paths__ must include the directory containing `CZiti-Swift.h`.

# Getting Help

Please use these community resources for getting help. We use GitHub [issues](https://github.com/netfoundry/ziti-url-protocol/issues) 
for tracking bugs and feature requests.

- Read the [docs](https://netfoundry.github.io/ziti-doc/ziti/overview.html)
- Join our [Developer Community](https://ziti.dev)
- Participate in discussion on [Discourse](https://netfoundry.discourse.group/)

Copyright&copy; 2020. NetFoundry, Inc.
