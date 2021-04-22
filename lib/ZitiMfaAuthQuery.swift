/*
Copyright NetFoundry, Inc.

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

@objc public class ZitiMfaAuthQuery : NSObject, Codable {
    private static let log = ZitiLog(ZitiMfaAuthQuery.self)
    
    public var typeId:String?
    public var provider:String?
    public var httpMethod:String?
    public var httpUrl:String?
    public var minLength:Int32?
    public var maxLength:Int32?
    public var format:String?
    
    init(_ cAuthQuery:UnsafeMutablePointer<ziti_auth_query_mfa>) {
        super.init()
        
        typeId     = toStr(cAuthQuery.pointee.type_id)
        provider   = toStr(cAuthQuery.pointee.provider)
        httpMethod = toStr(cAuthQuery.pointee.http_method)
        httpUrl    = toStr(cAuthQuery.pointee.http_url)
        minLength  = cAuthQuery.pointee.min_length
        maxLength  = cAuthQuery.pointee.max_length
        format     = toStr(cAuthQuery.pointee.format)
    }
    
    private func toStr(_ cStr:UnsafePointer<CChar>?) -> String? {
        if let cStr = cStr { return String(cString: cStr) }
        return nil
    }
}
