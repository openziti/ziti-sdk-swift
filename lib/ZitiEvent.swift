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
        case MfaAuth = 0x08  // ZitiMfaAuthEvent.rawValue
        
        /// Indicates an `ApiEvent`
        case ApiEvent = 0x10 // ZitiApiEvent.rawValue
        
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
                
            /// Indicates `MfaAuthEvent`
            case .MfaAuth:  return ".MfaAuth"
                
            /// Indicates `ApiEvent`
            case .ApiEvent: return ".ApiEvent"
                
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
    
    /// Encapsulation of Ziti SDK C's MFA Auth Event
    @objc public class MfaAuthEvent : NSObject {
        
        /// The authentication query
        @objc public var mfaAuthQuery:ZitiMfaAuthQuery?
        init(_ cEvent:ziti_mfa_auth_event) {
            if cEvent.auth_query_mfa != nil {
                mfaAuthQuery = ZitiMfaAuthQuery(cEvent.auth_query_mfa)
            }
        }
    }
    
    /// Encapsulation of Ziti SDK C's API Event
    @objc public class ApiEvent : NSObject {
        
        /// New controller address
        @objc public let newControllerAddress:String
        init( _ cEvent:ziti_api_event) {
            var str = ""
            if let cStr = cEvent.new_ctrl_address {
                str = String(cString: cStr)
            }
            if !str.starts(with: "https://") {
                str.insert(contentsOf: "https://", at: str.startIndex)
             }
            newControllerAddress = str
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
    @objc public var mfaAuthEvent:MfaAuthEvent?
    
    /// Populated based on event `type`
    @objc public var apiEvent:ApiEvent?
    
    init(_ ziti:Ziti, _ cEvent:UnsafePointer<ziti_event_t>) {
        self.ziti = ziti
        type = EventType(rawValue: cEvent.pointee.type.rawValue) ?? .Invalid
        if type == .Context {
            contextEvent = ContextEvent(cEvent.pointee.event.ctx)
        } else if type == .Service {
            serviceEvent = ServiceEvent(cEvent.pointee.event.service)
        } else if type == .Router {
            routerEvent = RouterEvent(cEvent.pointee.event.router)
        } else if type == .MfaAuth {
            mfaAuthEvent = MfaAuthEvent(cEvent.pointee.event.mfa_auth_event)
        } else if type == .ApiEvent {
            apiEvent = ApiEvent(cEvent.pointee.event.api)
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
        
        if let e = mfaAuthEvent {
            if let mfaAuthQuery = e.mfaAuthQuery {
                str += "   provider: \(mfaAuthQuery.provider ?? "nil")\n"
                str += "   typeId: \(mfaAuthQuery.typeId ?? "nil")\n"
                str += "   httpMethod: \(mfaAuthQuery.httpMethod ?? "nil")\n"
                str += "   httpUrl: \(mfaAuthQuery.httpUrl ?? "nil")\n"
                str += "   minLength: \(mfaAuthQuery.minLength ?? -1)\n"
                str += "   maxLength: \(mfaAuthQuery.maxLength ?? -1)\n"
                str += "   format: \(mfaAuthQuery.format ?? "nil")\n"
            } else {
                str += "   mfaAuthQuery: nil\n"
            }
        }
        
        if let e = apiEvent {
            str += "   newControllerAddress: \(e.newControllerAddress)\n"
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
}
