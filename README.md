## Ziti URL Protocol

WIP: A static library containing a `URLProtocol` that intercepts http and https requests and routes them over a Ziti network.  Currently justs passes all requests via `um_http`.  Plan is to add support to `um_http` for a configurable `uv_linki` implmented to run over ziti (http -> (tls) -> [tcp|ziti])...

## Building

`./deps/ziti-sdk-c` is a git submodule.  This project expect builds to be built in `./deps/ziti-sdk-c/build-macosx-x86_64` for macOS and `./deps/ziti-sdk-c/build-iphoneos-arm64` for iOS (or `build-iphonesimulator-x86_64` for the simulator).  See the build instructions in the `ziti-sdk-c` repository.

```
$ cd ziti-url-protocol
$ git submodule update --init --recursive
$ mkdir build-macosx-x86_64
$ cd build-macosx-x86_64
$ cmake .. && make
$ cd ..
$ mkdir build-iphoneos-arm64
$ cd build-iphoneos-arm64
$ cmake .. -DCMAKE_TOOLCHAIN_FILE=../toolchains/iOS-arm64.cmake && make
```

Currently use `ZitiUrlProtocol.xcodeproj` to build the libraries...

## Getting Help

------------
Please use these community resources for getting help. We use GitHub [issues](https://github.com/NetFoundry/ziti-sdk-c/issues) 
for tracking bugs and feature requests and have limited bandwidth to address them.

- Read the [docs](https://netfoundry.github.io/ziti-doc/ziti/overview.html)
- Join our [Developer Community](https://developer.netfoundry.io)
- Participate in discussion on [Discourse](https://netfoundry.discourse.group/)

Copyright&copy; 2018-2020. NetFoundry, Inc.
