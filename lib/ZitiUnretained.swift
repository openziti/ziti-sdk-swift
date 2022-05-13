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
import Foundation

protocol ZitiUnretained : AnyObject {
    func toVoidPtr() -> UnsafeMutableRawPointer
}

extension ZitiUnretained {
    func toVoidPtr() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }
}

func zitiUnretained<T>(_ type: T.Type, _ ctx:UnsafeMutableRawPointer?) -> T? where T:ZitiUnretained {
    guard ctx != nil else { return nil }
    return Unmanaged<T>.fromOpaque(UnsafeMutableRawPointer(ctx!)).takeUnretainedValue()
}
