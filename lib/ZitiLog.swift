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

/// Logger class that mirrors the Ziti C SDK's logging feature
public class ZitiLog {
    var category:String
    let df = DateFormatter()
    
    /// Maps to Ziti CSDK log levels, which cannot be imported directly
    public enum LogLevel : Int32 {
        case WTF = -2, DEFAULT = -1, NONE, ERROR, WARN, INFO, DEBUG, VERBOSE, TRACE
        func toStr() -> String {
            let tStr:String
            switch self {
            case .WTF:     tStr = "    WTF"
            case .DEFAULT: tStr = "    WTF"
            case .NONE:    tStr = "    WTF"
            case .ERROR:   tStr = "  ERROR"
            case .WARN:    tStr = "   WARN"
            case .INFO:    tStr = "   INFO"
            case .DEBUG:   tStr = "  DEBUG"
            case .VERBOSE: tStr = "VERBOSE"
            case .TRACE:   tStr = "  TRACE"
            }
            return tStr
        }
    }
    
    /// Initialize logger
    ///
    /// - Parameters:
    ///     - category: descriptive name to differentiate unique logging areas
    public init(_ category:String = "CZiti") {
        self.category = category
        df.timeZone = TimeZone(abbreviation: "UTC") 
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss:SSS'Z'"
        setenv("ZITI_TIME_FORMAT", "utc", 1)
    }
    
    /// Initialize logger
    ///
    /// - Parameters:
    ///     - aClass: use name of this class as the loggng categy
    public convenience init(_ aClass:AnyClass) {
        //self.init(String(describing: aClass))
        self.init("CZiti")
    }
    
    /// Set the system-wide log level
    ///
    /// - Parameters:
    ///     - level: only log messages at this level or higher severity
    public class func setLogLevel(_ level:LogLevel) {
        ziti_log_set_level(level.rawValue);
    }
    
    /// Get the system-wide log level
    public class func getLogLevel() -> LogLevel {
        if ziti_log_level < LogLevel.WTF.rawValue { return .WTF }
        if ziti_log_level > LogLevel.TRACE.rawValue { return .TRACE }
        return LogLevel(rawValue: ziti_log_level) ?? .WTF
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
    
    /// Log a message at `.WTF` level ("what a terrible failure")
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
        log(.WTF, msg, file, function, line)
    }
    
    private func log(_ lvl:LogLevel,
                     _ msg:String,
                     _ file:StaticString,
                     _ function:StaticString,
                     _ line:UInt) {
        let file = "\(category):" + URL(fileURLWithPath: String(describing: file)).lastPathComponent
        var function = String(describing: function)
        if function.contains("(") {
            function.removeSubrange(function.firstIndex(of: "(")!...function.lastIndex(of: ")")!)
        }
        
        if lvl.rawValue <= ziti_log_level {
            fputs("[\(df.string(from: Date()))] \(lvl.toStr()) \(file):\(line) \(function)() \(msg)\n", stderr)
        }
    }
}
