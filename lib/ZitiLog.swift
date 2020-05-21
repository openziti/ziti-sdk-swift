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
import os.log

// For now just implement with OSLog...
class ZitiLog {
    var oslog:OSLog
    
    init(_ category:String = "ziti") {
        oslog = OSLog(subsystem: "io.netfoundry.ziti", category: category)
    }
    
    init(_ aClass:AnyClass) {
        oslog = OSLog(subsystem: "io.netfoundry.ziti", category:String(describing: aClass))
    }
    
    func debug(_ msg:String,
               file:StaticString=#file,
               function:StaticString=#function,
               line:UInt=#line) {
        guard oslog.isEnabled(type: .debug) else { return }
        log(.debug, msg, file, function, line)
    }
    
    func info(_ msg:String,
              file:StaticString=#file,
              function:StaticString=#function,
              line:UInt=#line) {
        log(.info, msg, file, function, line)
    }
    
    func warn(_ msg:String,
               file:StaticString=#file,
               function:StaticString=#function,
               line:UInt=#line) {
        log(.error, "(warn) \(msg)", file, function, line)
    }
    
    func error(_ msg:String,
               file:StaticString=#file,
               function:StaticString=#function,
               line:UInt=#line) {
        log(.error, msg, file, function, line)
    }
    
    func wtf(_ msg:String,
             file:StaticString=#file,
             function:StaticString=#function,
             line:UInt=#line) {
        log(.fault, msg, file, function, line)
    }
    
    private func typeToString(_ t:OSLogType) -> String {
        var tStr = ""
        switch t {
        case .debug: tStr = "DEBUG"
        case .info:  tStr = "INFO"
        case .error: tStr = "ERROR"
        case .fault: tStr = "WTF"
        default: tStr = ""
        }
        return tStr
    }
    
    private func log(_ type:OSLogType, _ msg:String,
                                        _ file:StaticString,
                                        _ function:StaticString,
                                        _ line:UInt) {
        
        let file = URL(fileURLWithPath: String(describing: file)).deletingPathExtension().lastPathComponent
        var function = String(describing: function)
        if function.contains("(") {
            function.removeSubrange(function.firstIndex(of: "(")!...function.lastIndex(of: ")")!)
        }
        
        let tStr = typeToString(type)
        os_log("%{public}@\t%{public}@.%{public}@():%ld %{public}@", log:oslog.self, type:type, tStr, file, function, line, msg)
    }
}
