## Ziti URL Protocol

WIP: A Framework containing a URLProtocol that intercepts http and https requests and channles them over a Ziti network.  Currently justs passes all requests over um_http.  Plan is to add support to um_http for a configurable uv_link implmented to run over ziti (http -> (tls) -> [tcp|ziti])...

## Building

`./deps/ziti-sdk-c` is a git submodule.  This project expect builds to be built in `./deps/ziti-sdk-c/build-darwin-x86_64` for macOS and `./deps/ziti-sdk-c/build-iOS-arm64` for iOS (simulator not currently supported).  See the build instructions in the `ziti-sdk-c` repository.

## Getting Help

------------
Please use these community resources for getting help. We use GitHub [issues](https://github.com/NetFoundry/ziti-sdk-c/issues) 
for tracking bugs and feature requests and have limited bandwidth to address them.

- Read the [docs](https://netfoundry.github.io/ziti-doc/ziti/overview.html)
- Join our [Developer Community](https://developer.netfoundry.io)
- Participate in discussion on [Discourse](https://netfoundry.discourse.group/)

Copyright&copy; 2018-2020. NetFoundry, Inc.
