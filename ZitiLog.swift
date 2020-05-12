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
import OSLog

extension OSLog {
    convenience init(_ category:String = "ziti") {
        //self.init(subsystem: Bundle.main.bundleIdentifier ?? "", category:category)
        self.init(subsystem: "io.netfoundry.ziti", category: category)
    }
    convenience init(_ aClass:AnyClass) {
        self.init(String(describing: aClass))
    }

    // For now send everything though with "file:func(): line"
    // (redundant when looking at in Console or via `log` utility...
    func debug(_ msg:String,
                          file:StaticString=#file,
                          function:StaticString=#function, line:UInt=#line) {
        guard isEnabled(type: .debug) else { return }
        log(.debug, msg, file, function, line)
    }
    
    func info(_ msg:String,
                          file:StaticString=#file,
                          function:StaticString=#function,
                          line:UInt=#line) {
        log(.info,  msg, file, function, line)
    }
    
    func error(_ msg:String,
                          file:StaticString=#file,
                          function:StaticString=#function,
                          line:UInt=#line) {
        log(.error,  msg, file, function, line)
    }
    
    func wtf(_ msg:String,
                          file:StaticString=#file,
                          function:StaticString=#function,
                          line:UInt=#line) {
        log(.fault,  msg, file, function, line)
    }

    internal func typeToString(_ t:OSLogType) -> String {
        var tStr = ""
        switch t {
        case .debug: tStr = "DEBUG"
        case .info: tStr = "INFO"
        case .error: tStr = "ERROR"
        case .fault: tStr = "WTF"
        default: tStr = ""
        }
        return tStr
    }
    internal func log(_ type:OSLogType, _ msg:String,
                                        _ file:StaticString,
                                        _ function:StaticString,
                                        _ line:UInt) {
        let file = URL(fileURLWithPath: String(describing: file)).deletingPathExtension().lastPathComponent
        var function = String(describing: function)
        if function.contains("(") && function.contains(")") {
            function.removeSubrange(function.firstIndex(of: "(")!...function.lastIndex(of: ")")!)
        } else {
            function = "<static>"
        }
        
        let tStr = typeToString(type)
        os_log("%{public}@\t%{public}@.%{public}@():%ld %{public}@", log:self, type:type, tStr, file, function, line, msg)
    }
}
