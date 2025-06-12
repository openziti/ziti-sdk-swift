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

/// Class representation of ziti-url-client.v1 service configuration
public class ZitiUrlClientConfigV1 : Codable, ZitiServiceConfig {
    static var configType = "ziti-url-client.v1"
    
    /// Scheme name (e.g., http, https)
    public let scheme:String
    
    /// hostname
    public let hostname:String
    
    /// (optional) port number, which will be inferred from `scheme` if not set
    public var port:Int?
    
    /// HTTP header to inject into the response
    public var headers: [String: String]?
    
    
    /// Convenience function to resolve `port`
    public func getPort() -> Int { return port ?? (scheme == "https" ? 443 : 80) }
}
