/*
Copyright 2020 NetFoundry, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#import <Foundation/Foundation.h>

//! Project version number for ZitiUrlProtocol
FOUNDATION_EXPORT double ZitiUrlProtocol_VersionNumber;

//! Project version string for ZitiUrlProtocol
FOUNDATION_EXPORT const unsigned char ZitiUrlProtocol_VersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <ZitiUrlProtocol/PublicHeader.h>

#import "uv_mbed/um_http.h"
#import "uv_mbed/queue.h"
#import "uv_mbed/tls_engine.h"
#import "uv_mbed/um_http.h"
#import "uv_mbed/uv_mbed.h"
#import "uv/darwin.h"
#import "uv/errno.h"
#import "uv/threadpool.h"
#import "uv/unix.h"
#import "uv/version.h"
#import "uv_link_t.h"
#import "uv.h"
#import "http_parser.h"
