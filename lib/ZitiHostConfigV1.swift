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

/// Class representation of host.v1 service configuration
public class ZitiHostConfigV1 : Codable, ZitiServiceConfig {
    static var configType = "host.v1"
    
    enum CodingKeys: String, CodingKey {
        case proto = "protocol"
        case forwardProtocol
        case allowedProtocols
        case address
        case forwardAddress
        case allowedAddresses
        case allowedSourceAddresses
        case port
        case forwardPort
        case allowedPortRanges
        case listenOptions
    }
    
    /// Class representing port range
    public class PortRange : Codable {
        
        /// lowest port number in range
        public let low:Int
        
        /// highest port number in range
        public let high:Int
    }
    
    
    /// Class representing listening options
    public class ListenOptions : Codable {
        
        /// connection timeout in seconds
        public var connectTimeoutSeconds:Int?
        
        /// maximum number of connections
        public var maxConnections:Int?
        
        /// hosting identity
        public var identity:String?
        
        /// indicates whether or not to bind using endge identity
        public var bindUsingEdgeIdentity:Bool?
    }
    
    /// protocol
    public var proto:String?
    
    /// indicates whether or not to forward protocol
    public var forwardProtocol:Bool?
    
    /// listing of allowed protocols
    public var allowedProtocols:[String]?
    
    /// address
    public var address:String?
    
    /// indicates whether or not to forward address
    public var forwardAddress:Bool?
    
    /// listing of allowed addresses
    public var allowedAddresses:[String]?
    
    /// listing of allowed source addresses
    public var allowedSourceAddresses:[String]?
    
    /// port number
    public var port:Int?
    
    /// Indicates whether or not to forward port number
    public var forwardPort:Bool?
    
    /// listing of allowed port ranges
    public var allowedPortRanges:[PortRange]?
    
    /// Listen options
    public var listenOptions:ListenOptions?
}
