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

@objc public class ZitiService : NSObject, Codable {
    private static let log = ZitiLog(ZitiService.self)
    enum CodingKeys: String, CodingKey {
        case name, id, encrypted, permFlags
        case tunnelClientConfigV1 = "ziti-tunneler-client.v1"
        case urlClientConfigV1    = "ziti-url-client.v1"
    }
    
    public var cService:UnsafeMutablePointer<ziti_service>?
        
    public var name:String?
    public var id:String?
    public var encrypted:Bool?
    public var permFlags:Int32?
    public var tunnelClientConfigV1:ZitiTunnelClientConfigV1?
    public var urlClientConfigV1:ZitiUrlClientConfigV1?
    
    init(_ cService:UnsafeMutablePointer<ziti_service>) {
        self.cService = cService
        name = String(cString: cService.pointee.name)
        id = String(cString: cService.pointee.id)
        encrypted = cService.pointee.encryption
        permFlags = cService.pointee.perm_flags
        
        if let cfg = ZitiService.parseConfig(ZitiTunnelClientConfigV1.self, &(cService.pointee)) {
            tunnelClientConfigV1 = cfg
        }
        if let cfg = ZitiService.parseConfig(ZitiUrlClientConfigV1.self, &(cService.pointee)) {
            urlClientConfigV1 = cfg
        }
    }
    
    static func parseConfig<T>(_ type: T.Type, _ zs: inout ziti_service) -> T? where T:Decodable, T:ZitiConfig {
        if let cfg = ziti_service_get_raw_config(&zs, type.configType.cString(using: .utf8)) {
            return try? JSONDecoder().decode(type, from: Data(String(cString: cfg).utf8))
        }
        return nil
    }
}
