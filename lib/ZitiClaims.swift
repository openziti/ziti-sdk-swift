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

/**
 * Class that encapsulate the claims of a Ziti one-time JWT file.
 *
 * Claims are verified as part of the enrollment process.
 *
 * - See also:
 *      - `Ziti.enroll(_:,_:)`
 */
public class ZitiClaims : NSObject, Codable {
    private static let log = ZitiLog(ZitiClaims.self)
    private var log:ZitiLog { return ZitiClaims.log }
    
    /// Subject Clain (Required)
    public let sub:String
    
    /// Issuer Clain
    public var iss:String?
    
    /// Enrollment Method Clain
    public var em:String?
    
    /// Expiration Time Claim
    public var exp:Int?
    
    /// JWT ID Claim
    @objc public var jti:String?
    
    init(_ sub:String, _ iss:String?, _ em:String?, _ exp:Int?, _ jti:String?) {
        self.sub = sub
        self.iss = iss
        self.em  = em
        self.exp = exp
        self.jti = jti
        super.init()
    }
}
