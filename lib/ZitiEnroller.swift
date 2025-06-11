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
    /// use the same loop for all enrollments, otherwise the logger's loop will be invalid after the first enrollment.
    private static var loop: UnsafeMutablePointer<uv_loop_t> = {
        let l = UnsafeMutablePointer<uv_loop_t>.allocate(capacity: 1)
        l.initialize(to: uv_loop_t())
        uv_loop_init(l)
        ziti_log_init_wrapper(l)
        return l
    }()
    
    /**
     * Class representing response to successful enrollment attempt
     */
    @objc public class EnrollmentResponse : NSObject, Codable {
        /// Identity portion of successful enrollment attempt
        public class Identity : Codable {
            ///locally generated private key used for generating CSR as part of enrollment
            public var key:String?,
            
            /// signed certificate created as part of CSR process. will be nill for url enrollments
            cert:String?,
            
            /// root certificates for trusting the Ziti Controller
            ca:String?
            
            init(cert:String?, key:String?, ca:String?) {
                self.cert = cert
                self.key = key
                self.ca = ca
            }
        }
        
        /**
         * URL of controller returned on successful enrollment attempt
         */
        public let ztAPIs:[String], id:Identity
        init(ztAPIs:[String], id:Identity) {
            self.ztAPIs = ztAPIs
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
        var url_c:UnsafeMutablePointer<Int8>?
        
        deinit {
            jwtFile_c?.deallocate()
            privatePem_c?.deallocate()
            url_c?.deallocate()
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
        
        var enroll_opts = ziti_enroll_opts(url: nil, token: enrollData.pointee.jwtFile_c,
                                           key: enrollData.pointee.privatePem_c,
                                           cert: nil, name: nil, use_keychain: false)
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
        self.enroll(withLoop: ZitiEnroller.loop, privatePem: privatePem, cb: cb)
        
        let runStatus = uv_run(ZitiEnroller.loop, UV_RUN_DEFAULT)
        guard runStatus == 0 else {
            let errStr = String(cString: uv_strerror(runStatus))
            log.error(errStr)
            cb(nil, nil, ZitiError(errStr, errorCode: Int(runStatus)))
            return
        }
    }
    
    static func enroll(withLoop loop:UnsafeMutablePointer<uv_loop_t>?,
                       controllerURL:String,
                       cb:@escaping EnrollmentCallback) {
        let enrollData = UnsafeMutablePointer<EnrollmentRequestData>.allocate(capacity: 1)
        enrollData.initialize(to: EnrollmentRequestData())
        enrollData.pointee.enrollmentCallback = cb
        enrollData.pointee.url_c = UnsafeMutablePointer<Int8>.allocate(capacity: controllerURL.count + 1)
        enrollData.pointee.url_c!.initialize(from: controllerURL.cString(using: .utf8)!, count: controllerURL.count + 1)
        
        var enroll_opts = ziti_enroll_opts(url: enrollData.pointee.url_c, token: nil, key: nil,
                                           cert: nil, name: nil, use_keychain: false)
        let status = ziti_enroll(&enroll_opts, loop, ZitiEnroller.on_enroll, enrollData)
        guard status == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(status))
            log.error(errStr)
            cb(nil, nil, ZitiError(errStr, errorCode: Int(status)))
            return
        }
    }
    
    @objc public static func enroll(url:String, cb:@escaping EnrollmentCallback) {
        self.enroll(withLoop: ZitiEnroller.loop, controllerURL: url, cb: cb)
        
        let runStatus = uv_run(ZitiEnroller.loop, UV_RUN_DEFAULT)
        guard runStatus == 0 else {
            let errStr = String(cString: uv_strerror(runStatus))
            log.error(errStr)
            cb(nil, nil, ZitiError(errStr, errorCode: Int(runStatus)))
            return
        }
    }
    
    /**
     * Extract the sub (id) field from JWT file
     */
    @objc public func getSubj() -> String? {
        return getClaims()?.sub
    }
    
    /**
     * Retreive the claims in the JWT file
     * - returns: The claims in the file or nil if unable to decode
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
        // todo only do this if not using url.
        //guard let cert = String(cString: zc.id.cert, encoding: .utf8) else {
        //    let errStr = "Unable to convert cert to string"
        //    log.error(errStr, function:"on_enroll()")
        //    let ze = ZitiError(errStr, errorCode: -1)
        //    enrollData.pointee.enrollmentCallback?(nil, nil, ze)
        //    return
        //}
        
        var controllers:[String] = []
        var ctrlList = zc.controllers
        withUnsafeMutablePointer(to: &ctrlList) { ctrlListPtr in
            var i = model_list_iterator(ctrlListPtr)
            while i != nil {
                let ctrlPtr = model_list_it_element(i)
                if let ctrl = UnsafeMutablePointer<CChar>(OpaquePointer(ctrlPtr)) {
                    let ctrlStr = String(cString: ctrl)
                    controllers.append(ctrlStr)
                }
                i = model_list_it_next(i)
            }
        }
        guard let ztAPI = String(cString: zc.controller_url, encoding: .utf8) else {
            let errStr = "Invaid ztAPI response"
            log.error(errStr, function:"on_enroll()")
            let ze = ZitiError(errStr, errorCode: -1)
            enrollData.pointee.enrollmentCallback?(nil, nil, ze)
            return
        }
        
        let cert:String? = zc.id.cert != nil ? String(cString: zc.id.cert, encoding: .utf8)! : nil
        let key:String? = zc.id.key != nil ? String(cString: zc.id.key, encoding: .utf8)! : nil
        let ca:String? = zc.id.ca != nil ? String(cString: zc.id.ca, encoding: .utf8)! : nil
        
        let id = EnrollmentResponse.Identity(cert: cert, key: key, ca: ca)
        //let id = EnrollmentResponse.Identity(cert: cert,
        //                                     key: String(cString: zc.id.key, encoding: .utf8),
        //                                     ca: String(cString: zc.id.ca, encoding: .utf8))
        let enrollResp = EnrollmentResponse(ztAPIs: controllers, id: id)
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
