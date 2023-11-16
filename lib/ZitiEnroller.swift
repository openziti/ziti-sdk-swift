/*
Copyright NetFoundry Inc.

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
import CZitiPrivate

/**
 * Class that enroll an identity with Ziti controller using a one-time JWT file
 */
@objc public class ZitiEnroller : NSObject, ZitiUnretained {
    private static let log = ZitiLog(ZitiEnroller.self)
    private let log = ZitiEnroller.log
    
    /**
     * Class representing response to successful enrollment attempt
     */
    @objc public class EnrollmentResponse : NSObject, Codable {
        /// Identity portion of successful enrollment attempt
        public class Identity : Codable {
            ///locally generated private key used for generating CSR as part of enrollmen
            public var key:String?,
            
            /// signed certificate created as part of CSR process
            cert:String,
            
            /// root certificates for trusting the Ziti Controller
            ca:String?
            
            init(cert:String, key:String?, ca:String?) {
                self.cert = cert
                self.key = key
                self.ca = ca
            }
        }
        
        /**
         * URL of controller returned on successful enrollment attempt
         */
        public let ztAPI:String, id:Identity
        init(ztAPI:String, id:Identity) {
            self.ztAPI = ztAPI
            self.id = id
        }
    }
    
    /**
     * Name of file containing one-time JWT
     */
    @objc public var jwtFile:String

    /**
     * Initiaizel with a JWT file
     * - Parameters:
     *      - jwtFile: file containing one-time JWT
     */
    @objc public init(_ jwtFile:String) {
        self.jwtFile = jwtFile
    }
    
    /**
     * Type used for escaping callback closure called following an enrollment attempt
     *
     * - Parameters:
     *      - resp: EnrollmentResponse returned on successful enrollment.  `nil` on failed attempt
     *      - subj: `sub` field indicated in JWT, representing unique id for this Ziti identity. `nil` on failed attempt
     *      - error: `ZitiError` containing error information on failed enrollment attempt
     */
    public typealias EnrollmentCallback = (_ resp:EnrollmentResponse?, _ subj:String?, _ error:ZitiError?) -> Void
    
    class EnrollmentRequestData : NSObject, ZitiUnretained {
        var subj:String?
        var enrollmentCallback:EnrollmentCallback?
        var jwtFile_c:UnsafeMutablePointer<Int8>?
        var privatePem_c:UnsafeMutablePointer<Int8>?
        
        deinit {
            jwtFile_c?.deallocate()
            privatePem_c?.deallocate()
        }
    }
    
    /**
     * Enroll a Ziti identity using a supplied `uv_loop_t` and JWT file
     *
     * - Parameters:
     *      - loop: `uv_loop_t` used for executing the enrollment
     *      - privatePem: private key in PEM format
     *      - cb: callback called indicating status of enrollment attempt
     */
    func enroll(withLoop loop:UnsafeMutablePointer<uv_loop_t>?,
                      privatePem:String,
                      cb:@escaping EnrollmentCallback) {
        
        guard let subj = getSubj() else {
            let errStr = "Unable to retrieve sub from jwt file \(jwtFile)"
            log.error(errStr)
            cb(nil, nil, ZitiError(errStr))
            return
        }
                        
        let enrollData = UnsafeMutablePointer<EnrollmentRequestData>.allocate(capacity: 1)
        enrollData.initialize(to: EnrollmentRequestData())
        enrollData.pointee.enrollmentCallback = cb
        enrollData.pointee.subj = subj
        enrollData.pointee.jwtFile_c = UnsafeMutablePointer<Int8>.allocate(capacity: jwtFile.count + 1)
        enrollData.pointee.jwtFile_c!.initialize(from: jwtFile.cString(using: .utf8)!, count: jwtFile.count + 1)
        enrollData.pointee.privatePem_c = UnsafeMutablePointer<Int8>.allocate(capacity: privatePem.count + 1)
        enrollData.pointee.privatePem_c!.initialize(from: privatePem.cString(using: .utf8)!, count: privatePem.count + 1)
        
        var enroll_opts = ziti_enroll_opts(jwt: enrollData.pointee.jwtFile_c,
                                           enroll_key: enrollData.pointee.privatePem_c,
                                           enroll_cert: nil, enroll_name: nil, jwt_content: nil)
        let status = ziti_enroll(&enroll_opts, loop, ZitiEnroller.on_enroll, enrollData)
        guard status == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(status))
            log.error(errStr)
            cb(nil, nil, ZitiError(errStr, errorCode: Int(status)))
            return
        }
    }
    
    /**
     * Enroll a Ziti identity using a JWT file
     *
     * - Parameters:
     *      - privatePem: private key in PEM format
     *      - cb: callback called indicating status of enrollment attempt
     */
    @objc public func enroll(privatePem:String, cb:@escaping EnrollmentCallback) {
        var loop = uv_loop_t()
        
        let initStatus = uv_loop_init(&loop)
        guard initStatus == 0 else {
            let errStr = String(cString: uv_strerror(initStatus))
            log.error(errStr)
            cb(nil, nil, ZitiError(errStr, errorCode: Int(initStatus)))
            return
        }
        ziti_log_init_wrapper(&loop)
        self.enroll(withLoop: &loop, privatePem: privatePem, cb: cb)
        
        let runStatus = uv_run(&loop, UV_RUN_DEFAULT)
        guard runStatus == 0 else {
            let errStr = String(cString: uv_strerror(runStatus))
            log.error(errStr)
            cb(nil, nil, ZitiError(errStr, errorCode: Int(runStatus)))
            return
        }
    }
    
    /**
     * Extract the sub (id) field from HWT file
     */
    @objc public func getSubj() -> String? {
        return getClaims()?.sub
    }
    
    /**
     * Retreive the claims in the JWT file
     * - returns: The claims in the file or nil if enable to decode
     */
    public func getClaims() -> ZitiClaims? {
        do {
            // Get the contents
            let token = try String(contentsOfFile: jwtFile, encoding: .utf8)
            let comps = token.components(separatedBy: ".")
            
            if comps.count > 1, let data = base64UrlDecode(comps[1]),
                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let jsonSubj = json["sub"] as? String
            {
                return ZitiClaims(jsonSubj,
                                  json["iss"] as? String,
                                  json["em"] as? String,
                                  json["exp"] as? Int,
                                  json["jti"] as? String)
            } else {
                log.error("Enable to parse JWT file: \(jwtFile)")
            }
        }
        catch let error as NSError {
            log.error("Enable to load JWT file \(jwtFile): \(error)")
        }
        return nil
    }
    
    //
    // Private
    //
    static let on_enroll:ziti_enroll_cb = { zc, status, errMsg, ctx in
        guard let enrollData = ctx?.assumingMemoryBound(to: EnrollmentRequestData.self) else {
            log.wtf("unable to decode context", function:"on_enroll()")
            return
        }
        
        defer {
            enrollData.deinitialize(count: 1)
            enrollData.deallocate()
        }
        
        guard errMsg == nil else {
            let errStr = String(cString: errMsg!)
            log.error(errStr, function:"on_enroll()")
            let ze = ZitiError(errStr, errorCode: Int(status))
            enrollData.pointee.enrollmentCallback?(nil, nil, ze)
            return
        }
        guard status == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(status))
            log.error(errStr, function:"on_enroll()")
            let ze = ZitiError(errStr, errorCode: Int(status))
            enrollData.pointee.enrollmentCallback?(nil, nil, ze)
            return
        }
        guard let zc = zc?.pointee else {
            log.wtf("invalid config", function:"on_enroll()")
            return
        }
        guard let cert = String(cString: zc.id.cert, encoding: .utf8) else {
            let errStr = "Unable to convert cert to string"
            log.error(errStr, function:"on_enroll()")
            let ze = ZitiError(errStr, errorCode: -1)
            enrollData.pointee.enrollmentCallback?(nil, nil, ze)
            return
        }
        guard let ztAPI = String(cString: zc.controller_url, encoding: .utf8) else {
            let errStr = "Invaid ztAPI response"
            log.error(errStr, function:"on_enroll()")
            let ze = ZitiError(errStr, errorCode: -1)
            enrollData.pointee.enrollmentCallback?(nil, nil, ze)
            return
        }
        
        let id = EnrollmentResponse.Identity(cert: cert,
                                             key: String(cString: zc.id.key, encoding: .utf8),
                                             ca: String(cString: zc.id.ca, encoding: .utf8))
        let enrollResp = EnrollmentResponse(ztAPI: ztAPI, id: id)
        enrollData.pointee.enrollmentCallback?(enrollResp, enrollData.pointee.subj, nil)
    }
    
    //
    // Helpers...
    //
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
