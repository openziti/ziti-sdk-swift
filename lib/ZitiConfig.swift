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

protocol ZitiConfig {
    static var configType:String { get }
    static func parseConfig<T>(_ type: T.Type, _ zs: inout ziti_service) -> T? where T:Decodable, T:ZitiConfig
}

extension ZitiConfig {
    static func parseConfig<T>(_ type: T.Type, _ zs: inout ziti_service) -> T? where T:Decodable, T:ZitiConfig {
        if let cfg = ziti_service_get_raw_config(&zs, type.configType.cString(using: .utf8)) {
            return try? JSONDecoder().decode(type, from: Data(String(cString: cfg).utf8))
        }
        return nil
    }
}
