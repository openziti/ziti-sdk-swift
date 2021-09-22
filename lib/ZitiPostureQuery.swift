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
import CZitiPrivate

@objc public class ZitiPostureQuery : NSObject, Codable {
    private static let log = ZitiLog(ZitiPostureQuery.self)
    
    public var isPassing:Bool?
    public var queryType:String?
    public var id:String?
    public var timeout:Int32?
    public var timeoutRemaining:Int32?
         
    init(_ cPQ:UnsafeMutablePointer<ziti_posture_query>) {
        isPassing = cPQ.pointee.is_passing
        id = cPQ.pointee.id != nil ? String(cString: cPQ.pointee.id) : ""
        queryType = cPQ.pointee.query_type != nil ? String(cString:cPQ.pointee.query_type) : ""
        timeout = cPQ.pointee.timeout
        timeoutRemaining = cPQ.pointee.timeoutRemaining != nil ? cPQ.pointee.timeoutRemaining.pointee : -1
        //cPQ.pointee.process
        //cPQ.pointee.processes
    }
}
