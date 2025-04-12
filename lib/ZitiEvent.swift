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

/// Class encapsulating Swft representations of Ziti SDK C events
@objc public class ZitiEvent : NSObject {
    private let log = ZitiLog(ZitiEvent.self)
    
    /// weak reference to Ziti instance generating this event
    public weak var ziti:Ziti?
    
    /// Enumeration of possible event types
    @objc public enum EventType : UInt32 {
        
        /// Unrecognized event type
        case Invalid = 0x0
        
        /// Indicates a `ContextEvent`
        case Context = 0x01  // ZitiContextEvent.rawValue
        
        /// Indicates a `RouterEvent`
        case Router  = 0x02  // ZitiRouterEvent.rawValue
        
        /// Indicates a `ServiceEvent`
        case Service = 0x04  // ZitiServiceEvent.rawValue
        
        /// Indicates an `MfaAuthEvent`
        case Auth = 0x08     // ZitiAuthEvent.rawValue
        
        /// Indicates an `ApiEvent`
        case ConfigEvent = 0x10 // ZitiConfigEvent.rawValue
        
        /// Generates a string describing the event
        /// - returns: String describing the event
        public var debug: String {
            switch self {
                
            /// Indicates `ContextEvent`
            case .Context:  return ".Context"
                
            /// Indicates `RouterEvent`
            case .Router:   return ".Router"
                
            /// Indicates `ServiceEvent`
            case .Service:  return ".Service"
                
            /// Indicates `AuthEvent`
            case .Auth:     return ".Auth"
                
            /// Indicates `ConfigEvent`
            case .ConfigEvent: return ".ConfigEvent"
                
            /// Indicates unrecognized event
            case .Invalid:  return ".Invalid"
            @unknown default: return "unknown \(self.rawValue)"
            }
        }
    }
    
    /// Encapsulation of Ziti SDK C context event
    @objc public class ContextEvent : NSObject {
        /// Event status
        @objc public let status:Int32
        
        /// Error string (if present, else nil)
        @objc public let err:String?
        init(_ cEvent:ziti_context_event) {
            status = cEvent.ctrl_status
            if let err = cEvent.err {
                self.err = String(cString: err)
            } else {
                self.err = nil
            }
        }
    }
    
    /// Enumeration of possible router status settings
    @objc public enum RouterStatus : UInt32 {
        /// Router added
        case Added,
             
             /// Router connected
             Connected,
             
             /// Router disconnected
             Disconnected,
             
             /// Router removed
             Removed,
             
             /// Router unavailable
             Unavailable
        
        /// Returns string representation of router status
        public var debug: String {
            switch self {
            case .Added:        return ".Added"
            case .Connected:    return ".Connected"
            case .Disconnected: return ".Disconnected"
            case .Removed:      return ".Removed"
            case .Unavailable:  return ".Unavailable"
            @unknown default:   return "unknown \(self.rawValue)"
            }
        }
    }
    
    /// Encapsulation of Ziti SDK C's Router Event
    @objc public class RouterEvent : NSObject {
        
        /// Status triggering the event
        @objc public let status:RouterStatus
        
        /// Name of router associated with this event
        @objc public let name:String
        
        /// Version of router associated with this event
        @objc public let version:String
        init(_ cEvent:ziti_router_event) {
            status = RouterStatus(rawValue: cEvent.status.rawValue) ?? RouterStatus.Unavailable
            name = cEvent.name != nil ? String(cString: cEvent.name) : ""
            version = cEvent.version != nil ? String(cString: cEvent.version) : ""
        }
    }
    
    /// Encapsulation of Ziti SDK C's Service Event
    @objc public class ServiceEvent : NSObject {
        
        /// List of services removed
        @objc public var removed:[ZitiService] = []
        
        /// List of services changed
        @objc public var changed:[ZitiService] = []
        
        /// List of services added
        @objc public var added:[ZitiService] = []
        
        init(_ cEvent:ziti_service_event) {
            super.init()
            ZitiEvent.ServiceEvent.convert(cEvent.removed, &removed)
            ZitiEvent.ServiceEvent.convert(cEvent.changed, &changed)
            ZitiEvent.ServiceEvent.convert(cEvent.added, &added)
        }
        
        static func convert(_ cArr:ziti_service_array?, _ arr: inout [ZitiService]) {
            if var ptr = cArr  {
                while let svc = ptr.pointee {
                    arr.append(ZitiService(svc))
                    ptr += 1
                }
            }
        }
    }

    /// Enumeration of possible authentication actions
    @objc public enum AuthAction : UInt32 {
        /// Request for MFA code
        case PromptTotp
             
        /// Request for HSM/TPM key pin (not yet implemented)
        case PromptPin
             
        /// Request for app to launch external program/browser that can authenticate with url in [detail] field of auth event
        case LoginExternal
        
        case Unknown
        
        init(_ action:ziti_auth_action) {
            switch action {
            case ziti_auth_prompt_totp:    self = .PromptTotp
            case ziti_auth_prompt_pin:     self = .PromptPin
            case ziti_auth_login_external: self = .LoginExternal
            default: self = .Unknown
            }
        }
        
        /// Returns string representation of AuthAction
        public var debug: String {
            switch self {
            case .PromptTotp:    return ".PromptTotp"
            case .PromptPin:     return ".PromptPin"
            case .LoginExternal: return ".LoginExternal"
            case .Unknown:       return ".Unknown"
            @unknown default:    return "unknown \(self.rawValue)"
            }
        }
    }

    /// Encapsualtion of Ziti SDK C's JWTSigner
    @objc public class JwtSigner : NSObject {
        /// ID
        @objc public let id:String
        
        /// Name
        @objc public let name:String
        
        /// Enabled
        @objc public let enabled:Bool

        /// Provider URL
        @objc public let providerUrl:String
        
        /// Client ID
        @objc public let clientId:String
        
        /// Audience
        @objc public let audience:String
        
        /// Claim
        @objc public var scopes:[String]?
        
        init(_ cSigner:UnsafeMutablePointer<ziti_jwt_signer>) {
            id = cSigner.pointee.id != nil ? String(cString: cSigner.pointee.id) : ""
            name = cSigner.pointee.name != nil ? String(cString: cSigner.pointee.name) : ""
            enabled = cSigner.pointee.enabled
            providerUrl = cSigner.pointee.provider_url != nil ? String(cString: cSigner.pointee.provider_url) : ""
            clientId = cSigner.pointee.client_id != nil ? String(cString: cSigner.pointee.client_id) : ""
            audience = cSigner.pointee.audience != nil ? String(cString: cSigner.pointee.audience) : ""
            scopes = []
            var i = model_list_iterator(&(cSigner.pointee.scopes))
            while i != nil {
                let scopePtr = model_list_it_element(i)
                if let scope = UnsafeMutablePointer<CChar>(OpaquePointer(scopePtr)) {
                    scopes?.append(String(scope.pointee))
                }
                i = model_list_it_next(i)
            }
        }
    }

    /// Encapsulation of Ziti SDK C's  Auth Event
    @objc public class AuthEvent : NSObject {
        
        /// The authentication action
        @objc public var action:AuthAction
        
        /// The authentication type
        @objc public var type:String
        
        /// The authentication detail
        @objc public var detail:String
        
        /// Authentication providers
        @objc public var providers:Array<JwtSigner>
        
        init(_ cEvent:ziti_auth_event) {
            action = AuthAction(cEvent.action)
            type = cEvent.type != nil ? String(cString: cEvent.type) : ""
            detail = cEvent.detail != nil ? String(cString: cEvent.detail) : ""
            providers = [] // todo populate
        }
    }
    
    /// Encapsulation of Ziti SDK C's Config Event
    @objc public class ConfigEvent : NSObject {
        
        /// Controller address
        @objc public let controllerUrl:String
        @objc public let controllers:[String]
        @objc public let cfgSource:String
        @objc public let cert:String
        @objc public let caBundle:String
        
        init( _ cEvent:ziti_config_event) {
            var str = ""
            if let cStr = cEvent.config.pointee.controller_url {
                str = String(cString: cStr)
            }
            if !str.starts(with: "https://") {
                str.insert(contentsOf: "https://", at: str.startIndex)
            }
            controllerUrl = str
            
            var cfgSourceStr = ""
            if let cStr = cEvent.config.pointee.cfg_source {
                cfgSourceStr = String(cString: cStr)
            }
            cfgSource = cfgSourceStr

            var caStr = ""
            if let cStr = cEvent.config.pointee.id.ca {
                caStr = String(cString: cStr)
            }
            caBundle = caStr
            
            var certStr = ""
            if let cStr = cEvent.config.pointee.id.cert {
                certStr = String(cString: cStr)
            }
            cert = certStr

            var ctrlsArray:[String] = []
            var ctrlList = cEvent.config.pointee.controllers
            withUnsafeMutablePointer(to: &ctrlList) { ctrlListPtr in
                var i = model_list_iterator(ctrlListPtr)
                while i != nil {
                    let ctrlPtr = model_list_it_element(i)
                    if let ctrl = UnsafeMutablePointer<CChar>(OpaquePointer(ctrlPtr)) {
                        ctrlsArray.append(String(ctrl.pointee))
                    }
                    i = model_list_it_next(i)
                }
            }
            controllers = ctrlsArray
        }
    }
    
    /// The type of event
    @objc public let type:EventType
    
    /// Populated based on event `type`
    @objc public var contextEvent:ContextEvent?
    
    /// Populated based on event `type`
    @objc public var routerEvent:RouterEvent?
    
    /// Populated based on event `type`
    @objc public var serviceEvent:ServiceEvent?
    
    /// Populated based on event `type`
    @objc public var authEvent:AuthEvent?
    
    /// Populated based on event `type`
    @objc public var configEvent:ConfigEvent?
    
    init(_ ziti:Ziti, _ cEvent:UnsafePointer<ziti_event_t>) {
        self.ziti = ziti
        type = EventType(rawValue: cEvent.pointee.type.rawValue) ?? .Invalid
        if type == .Context {
            contextEvent = ContextEvent(cEvent.pointee.ctx)
        } else if type == .Service {
            serviceEvent = ServiceEvent(cEvent.pointee.service)
        } else if type == .Router {
            routerEvent = RouterEvent(cEvent.pointee.router)
        } else if type == .Auth {
            authEvent = AuthEvent(cEvent.pointee.auth)
        } else if type == .ConfigEvent {
            configEvent = ConfigEvent(cEvent.pointee.cfg)
        } else {
            log.error("unrecognized event type \(cEvent.pointee.type.rawValue)")
        }
    }
    
    /// Plain text description of event
    /// - returns:  String containing debug description
    public override var debugDescription: String {
        var str = "\(String(describing: self)):\n"
        str += "   type: \(type.debug)\n"
        
        if let e = contextEvent {
            str += "   status: \(e.status)\n"
            str += "   err: \(e.err ?? "")\n"
        }
        
        if let e = routerEvent {
            str += "   status: \(e.status.debug)\n"
            str += "   name: \(e.name)\n"
            str += "   version: \(e.version)"
        }
        
        if let e = serviceEvent {
            str += "   removed: (\(e.removed.count))\n\(ZitiEvent.svcArrToStr(e.removed))"
            str += "   changed: (\(e.changed.count))\n\(ZitiEvent.svcArrToStr(e.changed))"
            str += "   added: (\(e.added.count))\n\(ZitiEvent.svcArrToStr(e.added))"
        }
        
        if let e = authEvent {
            str += "   action: \(e.type)\n"
            str += "   type: \(e.type)\n"
            str += "   detail: \(e.detail)\n"
            str += "   providers: (\(e.providers.count))\n\(ZitiEvent.jwtSignerArrToStr(e.providers))"
        }
        
        if let e = configEvent {
            str += "   controller_url: \(e.controllerUrl)\n"
            str += "   controllers: \(e.controllers))\n"
            str += "   cfgSource: \(e.cfgSource)\n"
            str += "   caBundle: \(e.caBundle)\n"
            str += "   cert: \(e.cert)\n"
        }
        return str
    }
    
    static var enc = { () -> JSONEncoder in
        let e = JSONEncoder()
        //e.outputFormatting = .prettyPrinted
        return e
    }()
    
    static func svcArrToStr(_ arr:[ZitiService]) -> String {
        var str = ""
        for (i, svc) in arr.enumerated() {
            if let j = try? enc.encode(svc), let jStr = String(data:j, encoding:.utf8) {
                str += "      \(i):\(jStr)\n"
            }
        }
        return str
    }
    
    static func jwtSignerArrToStr(_ arr:[JwtSigner]) -> String {
        var str = ""
        for (i, signer) in arr.enumerated() {
            str += "      \(i):\(signer.description)\n"
        }
        return str
    }
}
