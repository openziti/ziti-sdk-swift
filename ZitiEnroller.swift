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

@objc public class ZitiEnroller : NSObject, ZitiUnretained {
    
    public typealias EnrollmentCallback = (EnrollmentResponse?, ZitiError?) -> Void
    var enrollmentCallback:EnrollmentCallback?
    @objc public class EnrollmentResponse : NSObject, Codable {
        public class Identity : Codable { public var key:String, cert:String, ca:String? }
        public let ztAPI:String, id:Identity
    }
    
    @objc public func enroll(loop:UnsafeMutablePointer<uv_loop_t>?, jwtFile:String, cb:@escaping EnrollmentCallback) {
        enrollmentCallback = cb
        
       // DispatchQueue(label: "ZitiEnroller").async {
            let status = NF_enroll(jwtFile.cString(using: .utf8), loop, ZitiEnroller.on_enroll, self.toVoidPtr())
            guard status == ZITI_OK else {
                cb(nil, ZitiError(String(cString: ziti_errorstr(status)), errorCode: Int(status)))
                return
            }
       // }
    }
    
    static let on_enroll:nf_enroll_cb = { json, len, errMsg, ctx in
        guard let mySelf = zitiUnretained(ZitiEnroller.self, ctx) else {
            NSLog("ZitiUrlProtocol.on_enroll WTF unable to decode context")
            return
        }
        guard let json = json, errMsg == nil else {
            var errStr = errMsg != nil ?  String(cString: errMsg!) : "Unspecified enrollment error"
            var ze = ZitiError("enroll error: \(errStr)")
            mySelf.enrollmentCallback?(nil, ze)
            return
        }
        
        // Bad format coming back from C SDK.  Invalid jason ("\n" rather than "\\n" in values)
        var s = String(cString: json)
        s = s.replacingOccurrences(of: "\n\t", with: "")
        s = s.replacingOccurrences(of: "\n}", with: "}")
        s = s.replacingOccurrences(of: "\n", with: "\\n")
                
        let enrollResp = try? JSONDecoder().decode(
            EnrollmentResponse.self,
            from: Data(s.utf8))
        guard enrollResp != nil  else {
            var ze = ZitiError("enroll error: unable to parse result")
            mySelf.enrollmentCallback?(nil, ze)
            return
        }
        
        /*
        if let er = enrollResp {
            print("Identity JSON:" +
                "\nztAPI: \(er.ztAPI)" +
                "\nid.key: \(er.id.key)" +
                "\nid.cert: \(er.id.cert)" +
                "\nid.ca: \(er.id.ca ?? "")" +
                "\n")
        }*/
        
        mySelf.enrollmentCallback?(enrollResp, nil)
    }
}
