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
 * Class that enroll an identity with Ziti controller using a one-time JWT file
 */
@objc public class ZitiEnroller : NSObject, ZitiUnretained {
    /**
     * Class representing response to successful enrollment attempt
     */
    @objc public class EnrollmentResponse : NSObject, Codable {
        /**
         * Identity portion of successful enrollment attempt
         *
         *  - .key: locally generated private key used for generating CSR as part of enrollment
         *  - .cert: signed certificate created as part of CSR process
         *  - .ca: root certificates for trusting the Ziti Controller
         */
        public class Identity : Codable { public var key:String, cert:String, ca:String? }
        
        /**
         * URL of controller returned on successful enrollment attempt
         */
        public let ztAPI:String, id:Identity
    }
    
    /**
     * Type used for escaping callback closure called following an enrollment attempt
     *
     * - Parameters:
     *      - resp: EnrollmentResponse returned on successful enrollment.  `nil` on failed attempt
     *      - subj: `sub` field indicated in JWT, representing unique id for this Ziti identity. `nil on failed attempt`
     *      - error: `ZitiError` containing error information on failed enrollment attempt
     */
    public typealias EnrollmentCallback = (_ resp:EnrollmentResponse?, _ subj:String?, _ error:ZitiError?) -> Void
    var enrollmentCallback:EnrollmentCallback?
    var subj:String?
    
    /**
     * Enroll a Ziti identity using a supplied `uv_loop_t` and JWT file
     *
     * - Parameters:
     *      - loop: `uv_loop_t` used for executing the enrollment
     *      - jwtFile: file containing one-time JWT
     *      - cb: callback called indicating status of enrollment attempt
     */
    @objc func enroll(withLoop loop:UnsafeMutablePointer<uv_loop_t>?, jwtFile:String, cb:@escaping EnrollmentCallback) {
        guard let subj = getSubj(jwtFile) else {
            cb(nil, nil, ZitiError("Unable to retrieve sub from jwt file \(jwtFile)"))
            return
        }
        self.subj = subj
        enrollmentCallback = cb
        
        let status = NF_enroll(jwtFile.cString(using: .utf8), loop, ZitiEnroller.on_enroll, self.toVoidPtr())
        guard status == ZITI_OK else {
            cb(nil, nil, ZitiError(String(cString: ziti_errorstr(status)), errorCode: Int(status)))
            return
        }
    }
    
    /**
     * Enroll a Ziti identity using a JWT file
     *
     * - Parameters:
     *      - jwtFile: file containing one-time JWT
     *      - cb: callback called indicating status of enrollment attempt
     */
    @objc public func enroll(jwtFile:String, cb:@escaping EnrollmentCallback) {
        var loop = uv_loop_t()
        
        let initStatus = uv_loop_init(&loop)
        guard initStatus == 0 else {
            cb(nil, nil, ZitiError(String(cString: uv_strerror(initStatus)), errorCode: Int(initStatus)))
            return
        }
        
        self.enroll(withLoop: &loop, jwtFile: jwtFile, cb: cb)
        
        let runStatus = uv_run(&loop, UV_RUN_DEFAULT)
        guard runStatus == 0 else {
            cb(nil, nil, ZitiError(String(cString: uv_strerror(runStatus)), errorCode: Int(runStatus)))
            return
        }
        
        let closeStatus = uv_loop_close(&loop)
        guard closeStatus == 0 else {
            NSLog("\(className):\(#function) error \(closeStatus) closing uv loop \(String(cString: uv_strerror(runStatus)))")
            return
        }
    }
    
    //
    // Private
    //
    static let on_enroll:nf_enroll_cb = { json, len, errMsg, ctx in
        guard let mySelf = zitiUnretained(ZitiEnroller.self, ctx) else {
            NSLog("\(className()).on_enroll WTF unable to decode context")
            return
        }
        guard let json = json, errMsg == nil else {
            var errStr = errMsg != nil ?  String(cString: errMsg!) : "Unspecified enrollment error"
            var ze = ZitiError("enroll error: \(errStr)")
            mySelf.enrollmentCallback?(nil, nil, ze)
            return
        }
        
        // Bad format coming back from C SDK.  Invalid json ("\n" rather than "\\n" in values)
        var s = String(cString: json)
        s = s.replacingOccurrences(of: "\n\t", with: "")
        s = s.replacingOccurrences(of: "\n}", with: "}")
        s = s.replacingOccurrences(of: "\n", with: "\\n")
                
        let enrollResp = try? JSONDecoder().decode(
            EnrollmentResponse.self,
            from: Data(s.utf8))
        guard enrollResp != nil  else {
            var ze = ZitiError("enroll error: unable to parse result")
            mySelf.enrollmentCallback?(nil, nil, ze)
            return
        }
        mySelf.enrollmentCallback?(enrollResp, mySelf.subj, nil)
    }
    
    //
    // Helpers...
    //
    func getSubj(_ jwtFile:String) -> String? {
        do {
            // Get the contents
            let token = try String(contentsOfFile: jwtFile, encoding: .utf8)
            let comps = token.components(separatedBy: ".")
            
            if comps.count > 1, let data = base64UrlDecode(comps[1]),
                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let jsonSubj = json["sub"] as? String
            {
                return jsonSubj
            }
        }
        catch let error as NSError {
            print("Enable to load JWT file: \(error)")
            exit(-1)
        }
        return nil
    }

    func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let length = Double(base64.lengthOfBytes(using: String.Encoding.utf8))
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = requiredLength - length
        if paddingLength > 0 {
            let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
            base64 += padding
        }
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }
}
