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
import CZitiPrivate

@objc public class ZitiTunnelEvent : NSObject {
    private let log = ZitiLog(ZitiTunnelEvent.self)
    public weak var ziti:Ziti?
    
    init(_ ziti:Ziti) {
        self.ziti = ziti
    }
}

@objc public class ZitiTunnelContextEvent : ZitiTunnelEvent {
    public var status:String
    public var name:String
    public var version:String
    public var controller:String
    public var code:Int32
    
    init(_ ziti:Ziti, _ evt:UnsafePointer<ziti_ctx_event>) {
        self.status = String(cString: evt.pointee.status)
        self.name = String(cString: evt.pointee.name)
        self.version = String(cString: evt.pointee.version)
        self.controller = String(cString: evt.pointee.controller)
        self.code = evt.pointee.code
        super.init(ziti)
    }
}

@objc public class ZitiTunnelMfaEvent : ZitiTunnelEvent {
    public enum MfaStatus  {
        case AuthStatus
        case AuthChallenge
        case EnrollmentVerification
        case EnrollmentRemove
        case EnrollmentChallenge
        case Uknown
        
        public init(_ mfaStatus:mfa_status) {
            switch mfaStatus {
            case mfa_status_mfa_auth_status: self = .AuthStatus
            case mfa_status_auth_challenge: self = .AuthChallenge
            case mfa_status_enrollment_verification: self = .EnrollmentVerification
            case mfa_status_enrollment_remove: self = .EnrollmentRemove
            case mfa_status_enrollment_challenge: self = .EnrollmentChallenge
            default: self = .Uknown
            }
        }
        
        public var mfaStatus : mfa_status {
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
    public var provider:String
    public var status:String
    public var operation:String
    public var operation_type:MfaStatus
    public var provisioningUrl:String
    public var recovery_codes:[String]
    public var code:Int32
    
    init(_ ziti:Ziti, _ evt:UnsafePointer<mfa_event>) {
        self.provider = String(cString: evt.pointee.provider)
        self.status = String(cString: evt.pointee.status)
        self.operation = String(cString: evt.pointee.operation)
        self.operation_type = MfaStatus(evt.pointee.operation_type)
        self.provisioningUrl = String(cString: evt.pointee.provisioning_url)
        self.code = evt.pointee.code
        
        self.recovery_codes = []
        if var ptr = evt.pointee.recovery_codes {
            while let s = ptr.pointee {
                self.recovery_codes.append(String(cString:s))
                ptr += 1
            }
        }
        super.init(ziti)
    }
}

@objc public class ZitiTunnelServiceEvent : ZitiTunnelEvent {
    public var status:String
    public var removed:[ZitiService] = []
    public var added:[ZitiService] = []
    
    init(_ ziti:Ziti, _ evt:UnsafePointer<service_event>) {
        self.status = String(cString: evt.pointee.status)
        ZitiEvent.ServiceEvent.convert(evt.pointee.removed_services, &removed)
        ZitiEvent.ServiceEvent.convert(evt.pointee.added_services, &added)
        super.init(ziti)
    }
}

@objc public class ZitiTunnelApiEvent : ZitiTunnelEvent {
    public var newControllerAddress:String
    
    init(_ ziti:Ziti, _ evt:UnsafePointer<api_event>) {
        self.newControllerAddress = String(cString: evt.pointee.new_ctrl_address)
        super.init(ziti)
    }
}
