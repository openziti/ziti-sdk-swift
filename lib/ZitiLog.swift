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

/// Logger class the uses Ziti C SDK's logging feature
public class ZitiLog {
    var category:String
    static var needDebugInit = true
    
    /// Maps to Ziti CSDK log levels, which cannot be imported directly
    public enum DebugLevel : Int32 {
        case NONE = 0, ERROR, WARN, INFO, DEBUG, VERBOSE, TRACE
    }
    
    /// Initial logger
    ///
    /// - Parameters:
    ///     - category: descriptive name to differentiate unique logging areas
    ///     - loop: uv_loop for logger
    public init(_ category:String = "CZiti", _ loop:UnsafeMutablePointer<uv_loop_t>! = uv_default_loop()) {
        self.category = category
        if ZitiLog.needDebugInit {
            ZitiLog.needDebugInit = false
            setenv("ZITI_TIME_FORMAT", "utc", 1)
            init_debug(loop)
        }
    }
    
    /// Initial logger
    ///
    /// - Parameters:
    ///     - aClass: use name of this class as the loggng categy
    ///     - loop: uv_loop for logger
    public init(_ aClass:AnyClass, _ loop:UnsafeMutablePointer<uv_loop_t>! = uv_default_loop()) {
        //category = String(describing: aClass)
        category = "CZiti"
        if ZitiLog.needDebugInit {
            ZitiLog.needDebugInit = false
            setenv("ZITI_TIME_FORMAT", "utc", 1)
            init_debug(loop)
        }
    }
    
    /// Set the system-wide log level
    ///
    /// - Parameters:
    ///     - level: only log messages at this level or higher (more severe)
    public class func setLogLevel(_ level:DebugLevel) {
        ziti_debug_level = level.rawValue
    }
    
    /// Set a custom logger
    ///
    /// - Parameters:
    ///     - logger: customer logging function
    ///     - loop: uv_loop for logger
    public class func setCustomerLogger(_ logger: @escaping log_writer, _ loop:UnsafeMutablePointer<uv_loop_t>! = uv_default_loop()) {
        // - TODO: Swiftify when updating for upcoming C SDK logging PR
        ziti_set_log(logger, loop)
    }
    
    /// Log a message at `.TRACE` level
    ///
    /// - Parameters:
    ///     - msg: message to log
    ///     - file: name of the file that makes this log message
    ///     - function: name of the function that makes this log message
    ///     - line: line number where this message was logged
    public func trace(_ msg:String,
               file:StaticString=#file,
               function:StaticString=#function,
               line:UInt=#line) {
        log(.TRACE, msg, file, function, line)
    }
    
    /// Log a message at `.VERBOSE` level
    ///
    /// - Parameters:
    ///     - msg: message to log
    ///     - file: name of the file that makes this log message
    ///     - function: name of the function that makes this log message
    ///     - line: line number where this message was logged
    public func verbose(_ msg:String,
               file:StaticString=#file,
               function:StaticString=#function,
               line:UInt=#line) {
        log(.VERBOSE, msg, file, function, line)
    }
    
    /// Log a message at `.DEBUG` level
    ///
    /// - Parameters:
    ///     - msg: message to log
    ///     - file: name of the file that makes this log message
    ///     - function: name of the function that makes this log message
    ///     - line: line number where this message was logged
    public func debug(_ msg:String,
               file:StaticString=#file,
               function:StaticString=#function,
               line:UInt=#line) {
        log(.DEBUG, msg, file, function, line)
    }
    
    /// Log a message at `.INFO` level
    ///
    /// - Parameters:
    ///     - msg: message to log
    ///     - file: name of the file that makes this log message
    ///     - function: name of the function that makes this log message
    ///     - line: line number where this message was logged
    public func info(_ msg:String,
              file:StaticString=#file,
              function:StaticString=#function,
              line:UInt=#line) {
        log(.INFO, msg, file, function, line)
    }
    
    /// Log a message at `.WARN` level
    ///
    /// - Parameters:
    ///     - msg: message to log
    ///     - file: name of the file that makes this log message
    ///     - function: name of the function that makes this log message
    ///     - line: line number where this message was logged
    public func warn(_ msg:String,
               file:StaticString=#file,
               function:StaticString=#function,
               line:UInt=#line) {
        log(.WARN, "\(msg)", file, function, line)
    }
    
    /// Log a message at `.ERROR` level
    ///
    /// - Parameters:
    ///     - msg: message to log
    ///     - file: name of the file that makes this log message
    ///     - function: name of the function that makes this log message
    ///     - line: line number where this message was logged
    public func error(_ msg:String,
               file:StaticString=#file,
               function:StaticString=#function,
               line:UInt=#line) {
        log(.ERROR, msg, file, function, line)
    }
    
    /// Log a message at `.ERROR` level with "what a terrible failure" designation
    ///
    /// - Parameters:
    ///     - msg: message to log
    ///     - file: name of the file that makes this log message
    ///     - function: name of the function that makes this log message
    ///     - line: line number where this message was logged
    public func wtf(_ msg:String,
             file:StaticString=#file,
             function:StaticString=#function,
             line:UInt=#line) {
        log(.ERROR, "(WTF) \(msg)", file, function, line)
    }
    
    private func levelToString(_ t:DebugLevel) -> String {
        var tStr = ""
        switch t {
        case .NONE:    tStr = "NONE   "
        case .ERROR:   tStr = "ERROR  "
        case .WARN:    tStr = "WARN   "
        case .INFO:    tStr = "INFO   "
        case .DEBUG:   tStr = "DEBUG  "
        case .VERBOSE: tStr = "VERBOSE"
        case .TRACE:   tStr = "TRACE  "
        }
        return tStr
    }
    
    private func log(_ level:DebugLevel, _ msg:String,
                                        _ file:StaticString,
                                        _ function:StaticString,
                                        _ line:UInt) {
        let file = "\(category):" + URL(fileURLWithPath: String(describing: file)).lastPathComponent
        var function = String(describing: function)
        if function.contains("(") {
            function.removeSubrange(function.firstIndex(of: "(")!...function.lastIndex(of: ")")!)
        }
        
        //let tStr = levelToString(type)
        //fputs("[\(Date())] \(tStr) \(category):\(file):\(line) \(function)(): \(msg)\n", stderr)
        if level.rawValue <= ziti_debug_level {
            ziti_logger_wrapper(level.rawValue,
                                file.cString(using: .utf8),
                                UInt32(line),
                                function.cString(using: .utf8),
                                msg.cString(using: .utf8))
        }
    }
}
