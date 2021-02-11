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

public class ZitiHostConfigV1 : Codable, ZitiConfig {
    static var configType = "host.v1"
    
    enum CodingKeys: String, CodingKey {
        case proto = "protocol"
        case dialInterceptedProtocol
        case address
        case dialInterceptedAddress
        case port
        case dialInterceptedPort
        case listenOptions
    }
    
    public class ListenOptions : Codable {
        public var cost:Int?
        public var precedence:String?
        public var connectTimeoutSeconds:Int?
        public var maxConnections:Int?
        public var identity:String?
        public var bindUsingEdgeIdentity:Bool?
    }
    
    public var proto:String?
    public var dialInterceptedProtocol:Bool?
    
    public var address:String?
    public var dialInterceptedAddress:Bool?
    
    public var port:Int?
    public var dialInterceptedPort:Bool?
    
    public var listenOptions:ListenOptions?
}
