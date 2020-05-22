## Ziti SDK for Swift

An SDK for accessing Ziti from macOS and iOS applications using the Swift programming language.

This SDK provides a Swift-friendly wrapper of the [Ziti C SDK](https://netfoundry.github.io/ziti-doc/api/clang/api/index.html), an implementation of `URLProtocol` for intercepting http and https traffic, and examples of using the SDK in an application.

## Usage
The `Ziti` class is the main entry point for accessing Ziti networks. An instance of `Ziti` requires a `ZitiIdentity` at time of initialization.

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

    if (![zid save:[self outFile]]) {
        // Handle error
        return;
    }
}];
```

The `Ziti.enroll(_:)` method validates the JWT is properly signed, creates a private key and stores it in the keychain, and initiates a Certificate Signing Request (CSR) with the controller, and stores the resultant certificate in the keychain.

The identity file saved to `outfile` in the example code above contains information for contacting the Ziti controller and locally accessing the private key and certificate in the keychain.

A typical application flow would:
1. Check a well-known location for a stored identity file
2. If not present, initiate an enrollment (e.g., prompt the user for location of a one-time JWT enrollment file, or scan in a QR code)
3. When identity file is available, use it to create an instance of `Ziti`

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
            // Handle errpr
            return;
        }
        [ZitiUrlProtocol register:ziti :10000];
    }];
}
```

The SDK also includes `ZitiUrlProtocol`, which implements a `URLProtocol` that interceptes http and https requests for Ziti services and routes them over a Ziti network.

`ZitiUrlProtocol` should be instantiated as part of the `InitCallback` of `Ziti` `run(_:)` to ensure `Ziti` is initialized before
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

In some cases, `ZitiUrlProtocol` will need to be configured in your `URLSession`'s configuration ala:
     
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

## Adding `CZiti` as a Dependency
The Swift SDK for Ziti is built into a static library (`libCZiti.a`).  Add this library to your project's **Frameworks and Libraries**, and ensure it is listed in your project's **Build Phases** under **Link Binary with Libraries**.

Your **Library Search Path** and **Swift Compiler Seatch Paths - Import Paths** should include the directory containing `libCZiti.a` and `CZiti.swiftmodule/`

Be sure to import the module to your Swift files that need to access `Ziti`.

__Swift__
```swift
import CZiti
```
__Objective-C__
```objective-C
#import "CZiti-Swift.h"
```

## Building

The Ziti C SDK is built into this static library.  It is maintained as a submodule at `./deps/ziti-sdk-c`.  This project expect builds to be built in `./deps/ziti-sdk-c/build-macosx-x86_64` for macOS and `./deps/ziti-sdk-c/build-iphoneos-arm64` for iOS (or `build-iphonesimulator-x86_64` for the simulator).  See also the build instructions in the [`ziti-sdk-c`](https://github.com/netfoundry/ziti-sdk-c/blob/master/building.md) repository.

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
```

Once the C SDK is built, use `CZiti.xcodeproj` to build the libraries and examples.

## Getting Help

Please use these community resources for getting help. We use GitHub [issues](https://github.com/netfoundry/ziti-url-protocol/issues) 
for tracking bugs and feature requests.

- Read the [docs](https://netfoundry.github.io/ziti-doc/ziti/overview.html)
- Join our [Developer Community](https://ziti.dev)
- Participate in discussion on [Discourse](https://netfoundry.discourse.group/)

Copyright&copy; 2020. NetFoundry, Inc.
