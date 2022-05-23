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

/// Class representation of intercept.v1 service configuration
public class ZitiInterceptConfigV1 : Codable, ZitiConfig {
    static var configType = "intercept.v1"
    
    /// Class representing port range to intercept
    public class PortRange : Codable {
        
        /// lowest port number to intercept
        public let low:Int
        
        /// highest port number to intercept
        public let high:Int
    }
    
    /// Class representing dialing options when connecting to Ziti over this intercept
    public class DialOptions : Codable {
        
        /// identity to connect
        public var identity:String?
        
        /// connection timeout in seconds
        public var connectTimeoutSeconds:Int?
    }
    
    /// intercepted protocols
    public let protocols:[String]
    
    /// intercepted addresses
    public let addresses:[String]
    
    /// intercepted port ranges
    public let portRanges:[PortRange]
    
    /// dial options
    public var dialOptions:DialOptions?
    
    /// sourceIp to present to dialed entity
    public var sourceIp:String?
}
