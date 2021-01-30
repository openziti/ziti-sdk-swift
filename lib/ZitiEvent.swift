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

@objc public class ZitiEvent : NSObject {
    private let log = ZitiLog(ZitiEvent.self)
    public weak var ziti:Ziti?
    
    @objc public enum EventType : UInt32 {
        case Invalid = 0x0
        case Context = 0x01 // ZitiContextEvent.rawValue
        case Router  = 0x02 // ZitiRouterEvent.rawValue
        case Service = 0x04 // ZitiServiceEvent.rawValue
        
        public var debug: String {
            switch self {
            case .Context: return ".Context"
            case .Router:  return ".Router"
            case .Service: return ".Service"
            case .Invalid: return ".Invalid"
            @unknown default: return "unknown \(self.rawValue)"
            }
        }
    }
    
    @objc public class ContextEvent : NSObject {
        @objc public let status:Int32
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
    
    @objc public enum RouterStatus : UInt32 {
        case Connected, Disconnected, Removed, Unavailable
        public var debug: String {
            switch self {
            case .Connected:    return ".Connected"
            case .Disconnected: return ".Disconnected"
            case .Removed:      return ".Removed"
            case .Unavailable:  return ".Unavailable"
            @unknown default:   return "unknown \(self.rawValue)"
            }
        }
    }
    @objc public class RouterEvent : NSObject {
        @objc public let status:RouterStatus
        @objc public let name:String
        @objc public let version:String
        init(_ cEvent:ziti_router_event) {
            status = RouterStatus(rawValue: cEvent.status.rawValue) ?? RouterStatus.Unavailable
            name = cEvent.name != nil ? String(cString: cEvent.name) : ""
            version = cEvent.version != nil ? String(cString: cEvent.version) : ""
        }
    }
    
    @objc public class ServiceEvent : NSObject {
        @objc public var removed:[ZitiService] = []
        @objc public var changed:[ZitiService] = []
        @objc public var added:[ZitiService] = []
        
        init(_ cEvent:ziti_service_event) {
            super.init()
            convert(cEvent.removed, &removed)
            convert(cEvent.changed, &changed)
            convert(cEvent.added, &added)
        }
        
        private func convert(_ cArr:ziti_service_array?, _ arr: inout [ZitiService]) {
            if var ptr = cArr  {
                while let svc = ptr.pointee {
                    arr.append(ZitiService(svc))
                    ptr += 1
                }
            }
        }
    }
    
    @objc public let type:EventType
    @objc public var contextEvent:ContextEvent?
    @objc public var routerEvent:RouterEvent?
    @objc public var serviceEvent:ServiceEvent?
    
    init(_ ziti:Ziti, _ cEvent:UnsafePointer<ziti_event_t>) {
        self.ziti = ziti
        type = EventType(rawValue: cEvent.pointee.type.rawValue) ?? .Invalid
        if type == .Context {
            contextEvent = ContextEvent(cEvent.pointee.event.ctx)
        } else if type == .Service {
            serviceEvent = ServiceEvent(cEvent.pointee.event.service)
        } else if type == .Router {
            routerEvent = RouterEvent(cEvent.pointee.event.router)
        } else {
            log.error("unrecognized event type \(cEvent.pointee.type.rawValue)")
        }
    }
    
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
            str += "   removed: (\(e.removed.count))\n\(svcArrToStr(e.removed))"
            str += "   changed: (\(e.changed.count))\n\(svcArrToStr(e.changed))"
            str += "   added: (\(e.added.count))\n\(svcArrToStr(e.added))"
        }
        return str
    }
    
    private lazy var enc = { () -> JSONEncoder in
        let e = JSONEncoder()
        //e.outputFormatting = .prettyPrinted
        return e
    }()
    
    private func svcArrToStr(_ arr:[ZitiService]) -> String {
        var str = ""
        for (i, svc) in arr.enumerated() {
            if let j = try? enc.encode(svc), let jStr = String(data:j, encoding:.utf8) {
                str += "      \(i):\(jStr)\n"
            }
        }
        return str
    }
}
