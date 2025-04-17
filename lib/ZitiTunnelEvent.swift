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

/// Class to encapsulate a Ziti Tunneler SDK event
@objc public class ZitiTunnelEvent : NSObject {
    let log = ZitiLog(ZitiTunnelEvent.self)
    
    /// Weak reference to Ziti instnace associated with this event
    public weak var ziti:Ziti?
    
    init(_ ziti:Ziti) {
        self.ziti = ziti
    }
    
    func toStr(_ cStr:UnsafePointer<CChar>?) -> String {
        if let cStr = cStr { return String(cString: cStr) }
        return ""
    }
    
    /// Provide a debug description of the event
    /// - returns: String containing the debug description
    public override var debugDescription: String {
        return "ZitiTunnelEvent: \(String(describing: self))\n" +
        "   identity: \(ziti?.id.name ?? ""):\"\(ziti?.id.id ?? "")\""
    }
}

/// Class encapsulating Ziti Tunnel SDK C Context Event
@objc public class ZitiTunnelContextEvent : ZitiTunnelEvent {
    
    /// Controller status
    public var status:String = ""
    
    /// Controller name
    public var name:String = ""
    
    /// Controller version
    public var version:String = ""
    
    /// Controller address
    public var controller:String = ""
    
    /// Controller event code
    public var code:Int64
    
    init(_ ziti:Ziti, _ evt:UnsafePointer<ziti_ctx_event>) {
        self.code = evt.pointee.code
        super.init(ziti)
        self.status = toStr(evt.pointee.status)
        self.name = toStr(evt.pointee.name)
        self.version = toStr(evt.pointee.version)
        self.controller = toStr(evt.pointee.controller)
    }
    
    /// Debug description of event
    /// - returns: String containing the debug description
    public override var debugDescription: String {
        return super.debugDescription + "\n" +
            "   status: \(status)\n" +
            "   name: \(name)\n" +
            "   version: \(version)\n" +
            "   controller: \(controller)\n" +
            "   code: \(code)"
    }
}

/// Class encapsulating Ziti Tunnel SDK C MFA Event
@objc public class ZitiTunnelMfaEvent : ZitiTunnelEvent {
    
    /// Enumeration of MFA Status
    public enum MfaStatus  {
        
        /// MFA Authentication Status
        case AuthStatus
        
        /// MFA Authentication Challenge
        case AuthChallenge
        
        /// MFA Enrollment Verification
        case EnrollmentVerification
        
        /// MFA Removal
        case EnrollmentRemove
        
        /// MFA Enrollment Challenge
        case EnrollmentChallenge
        
        /// Unregognized status
        case Uknown
        
        init(_ mfaStatus:mfa_status) {
            switch mfaStatus {
            case mfa_status_mfa_auth_status: self = .AuthStatus
            case mfa_status_auth_challenge: self = .AuthChallenge
            case mfa_status_enrollment_verification: self = .EnrollmentVerification
            case mfa_status_enrollment_remove: self = .EnrollmentRemove
            case mfa_status_enrollment_challenge: self = .EnrollmentChallenge
            default: self = .Uknown
            }
        }
        
        var mfaStatus : mfa_status {
            switch self {
            case .AuthStatus: return mfa_status_mfa_auth_status
            case .AuthChallenge: return mfa_status_auth_challenge
            case .EnrollmentVerification: return mfa_status_enrollment_verification
            case .EnrollmentRemove: return mfa_status_enrollment_remove
            case .EnrollmentChallenge: return mfa_status_enrollment_challenge
            case .Uknown: return mfa_status_Unknown
            }
        }
    }
    
    /// MFA provider
    public var provider:String = ""
    
    /// MFA status
    public var status:String = ""
    
    /// MFA operation
    public var operation:String = ""
    
    /// MFA operation type
    public var operationType:MfaStatus
    
    /// MFA provisioning URL
    public var provisioningUrl:String = ""
    
    /// MFA recovery codes
    public var recovery_codes:[String]
    
    /// MFA authentication code
    public var code:Int64
    
    init(_ ziti:Ziti, _ evt:UnsafePointer<mfa_event>) {
        self.operationType = MfaStatus(evt.pointee.operation_type)
        self.code = evt.pointee.code
        
        self.recovery_codes = []
        if var ptr = evt.pointee.recovery_codes {
            while let s = ptr.pointee {
                self.recovery_codes.append(String(cString:s))
                ptr += 1
            }
        }
        super.init(ziti)
        
        self.provider = toStr(evt.pointee.provider)
        self.status = toStr(evt.pointee.status)
        self.operation = toStr(evt.pointee.operation)
        self.provisioningUrl = toStr(evt.pointee.provisioning_url)
    }
    
    /// Debug description
    /// - returns: String containing debug description of this event
    public override var debugDescription: String {
        return super.debugDescription + "\n" +
            "   provider: \(provider)\n" +
            "   status: \(status)\n" +
            "   operation: \(operation)\n" +
            "   operationType: \(operationType)\n" +
            "   provisioningUrl: \(provisioningUrl)\n" +
            "   code: \(code)"
    }
}

/// Class encapsulating Ziti Tunnel SDK C Service Event
@objc public class ZitiTunnelServiceEvent : ZitiTunnelEvent {
    
    /// Event status
    public var status:String = ""
    
    /// Listing of services removed
    public var removed:[ZitiService] = []
    
    /// Listing of services added
    public var added:[ZitiService] = []
    
    init(_ ziti:Ziti, _ evt:UnsafePointer<service_event>) {
        ZitiEvent.ServiceEvent.convert(evt.pointee.removed_services, &removed)
        ZitiEvent.ServiceEvent.convert(evt.pointee.added_services, &added)
        super.init(ziti)
        self.status = toStr(evt.pointee.status)
    }
    
    /// Debug description
    /// - returns: String containing debug description of this event
    public override var debugDescription: String {
        return super.debugDescription + "\n" +
            "   status: \(status)\n" +
            "   removed: (\(removed.count))\n\(ZitiEvent.svcArrToStr(removed))" +
            "   added: (\(added.count))\n\(ZitiEvent.svcArrToStr(added))"
    }
}

/// Class encapsulating Ziti Tunnel SDK C Config Event
@objc public class ZitiTunnelConfigEvent : ZitiTunnelEvent {
    
    /// Controller address (legacy)
    public var controllerUrl:String = ""
    
    /// Controller addresses
    public var controllers:[String] = []
    
    /// CA bundle
    public var caBundle:String = ""
    
    /// Certificte PEM (possibly multiple certificates)
    public var certPEM:String = ""

    /// pointer to result of parsing event's `config_json` field. allocated by ziti-sdk-c
    private var ziti_cfg_ptr:UnsafeMutablePointer<ziti_config>?
    
    init(_ ziti:Ziti, _ evt:UnsafePointer<config_event>) {
        super.init(ziti)
        parse_ziti_config_ptr(&ziti_cfg_ptr, evt.pointee.config_json, strlen(evt.pointee.config_json))
        self.controllerUrl = toStr(ziti_cfg_ptr?.pointee.controller_url)
        
        var ctrlList = ziti_cfg_ptr!.pointee.controllers
        withUnsafeMutablePointer(to: &ctrlList) { ctrlListPtr in
            var i = model_list_iterator(ctrlListPtr)
            while i != nil {
                let ctrlPtr = model_list_it_element(i)
                if let ctrl = UnsafeMutablePointer<CChar>(OpaquePointer(ctrlPtr)) {
                    let ctrlStr = toStr(ctrl)
                    controllers.append(ctrlStr)
                }
                i = model_list_it_next(i)
            }
        }
        self.caBundle = toStr(ziti_cfg_ptr?.pointee.id.ca)
        self.certPEM = toStr(ziti_cfg_ptr?.pointee.id.cert)
    }
    
    deinit {
        if ziti_cfg_ptr != nil {
            free_ziti_config_ptr(ziti_cfg_ptr)
        }
    }
    
    /// Debug description
    /// - returns: String containing debug description of this event
    public override var debugDescription: String {
        return super.debugDescription + "\n" +
            "   controller_url: \(controllerUrl)\n" +
            "   contrlollers: \(controllers)\n" +
            "   caBundle: \(caBundle)\n" +
            "   cert: \(certPEM)"
    }
}
