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

/// Class representation of ziti-tunneler-server.v1 service configuration
public class ZitiTunnelServerConfigV1 : Codable, ZitiServiceConfig {
    static var configType = "ziti-tunneler-server.v1"
    enum CodingKeys: String, CodingKey {
        case hostname
        case port
        case proto = "protocol"
    }
    
    /// hostname to connect
    public let hostname:String
    
    /// port to connect
    public let port:Int
    
    /// protocol to connect
    public let proto:String // `protocol` is a reserved word...
}
