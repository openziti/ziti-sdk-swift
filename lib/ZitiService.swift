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

/// Class encapsulating a Ziti SDK C service
@objc public class ZitiService : NSObject, Codable {
    private let log = ZitiLog(ZitiService.self)
    enum CodingKeys: String, CodingKey {
        case name, id, encrypted, permFlags, postureQuerySets
        case tunnelClientConfigV1 = "ziti-tunneler-client.v1"
        case tunnelServerConfigV1 = "ziti-tunneler-server.v1"
        case urlClientConfigV1    = "ziti-url-client.v1"
        case interceptConfigV1    = "intercept.v1"
        case hostConfigV1         = "host.v1"
    }
    
    var cService:UnsafeMutablePointer<ziti_service>?
    
    /// Opaque reference to Ziti SDK C service
    public var cServicePtr:OpaquePointer? { return OpaquePointer(cService) }
        
    /// Name of the service
    public var name:String?
    
    /// ID of the service
    public var id:String?
    
    /// Indicates wheter or not this service is end-to-end encrypted
    public var encrypted:Bool?
    
    /// Service permisions (e.g., DIAL and/or BIND)
    public var permFlags:Int32?
    
    /// Listing of posture query sets
    public var postureQuerySets:[ZitiPostureQuerySet]?
    
    /// Tunnel client configuration (if provided)
    public var tunnelClientConfigV1:ZitiTunnelClientConfigV1?
    
    /// Tunnel server configuation (if provided)
    public var tunnelServerConfigV1:ZitiTunnelServerConfigV1?
    
    /// URL client configuration (if provided)
    public var urlClientConfigV1:ZitiUrlClientConfigV1?
    
    /// Intercept configuration (f provided)
    public var interceptConfigV1:ZitiInterceptConfigV1?
    
    /// Host configuation (if provided)
    public var hostConfigV1:ZitiHostConfigV1?
    
    init(_ cService:UnsafeMutablePointer<ziti_service>) {
        self.cService = cService
        name = String(cString: cService.pointee.name)
        id = String(cString: cService.pointee.id)
        encrypted = cService.pointee.encryption
        permFlags = cService.pointee.perm_flags
        
        var i = model_map_iterator(&(cService.pointee.posture_query_map))
        while i != nil {
            let pqsPtr = model_map_it_value(i)
            if let pqs = UnsafeMutablePointer<ziti_posture_query_set>(OpaquePointer(pqsPtr)) {
                if postureQuerySets == nil { postureQuerySets = [] }
                postureQuerySets?.append(ZitiPostureQuerySet(pqs))
            }
            i = model_map_it_next(i)
        }
        
        if let cfg = ZitiService.parseConfig(ZitiTunnelClientConfigV1.self, &(cService.pointee)) {
            tunnelClientConfigV1 = cfg
        }
        if let cfg = ZitiService.parseConfig(ZitiTunnelServerConfigV1.self, &(cService.pointee)) {
            tunnelServerConfigV1 = cfg
        }
        if let cfg = ZitiService.parseConfig(ZitiUrlClientConfigV1.self, &(cService.pointee)) {
            urlClientConfigV1 = cfg
        }
        if let cfg = ZitiService.parseConfig(ZitiInterceptConfigV1.self, &(cService.pointee)) {
            interceptConfigV1 = cfg
        }
        if let cfg = ZitiService.parseConfig(ZitiHostConfigV1.self, &(cService.pointee)) {
            hostConfigV1 = cfg
        }
    }
    
    static func parseConfig<T>(_ type: T.Type, _ zs: inout ziti_service) -> T? where T:Decodable, T:ZitiConfig {
        if let cfg = ziti_service_get_raw_config(&zs, type.configType.cString(using: .utf8)) {
            return try? JSONDecoder().decode(type, from: Data(String(cString: cfg).utf8))
        }
        return nil
    }
}
