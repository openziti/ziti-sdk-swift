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

/// Class used for passing information about error conditions encountered while using Ziti
public class ZitiError : NSError, @unchecked Sendable {

    /// Machine-parseable error code string from the controller (e.g. "ENROLLMENT_IDENTITY_ALREADY_ENROLLED")
    @objc public let errorCodeString:String?

    /// Initialize a ZitiError instance
    /// - Parameters:
    ///     - desc: error description
    ///     - errorCode: numeric error code
    ///     - errorCodeString: machine-parseable error code string from the controller
    init(_ desc:String, errorCode:Int=Int(-1), errorCodeString:String?=nil) {
        self.errorCodeString = errorCodeString
        super.init(domain: "ZitiError", code: errorCode,
                   userInfo: [NSLocalizedDescriptionKey:NSLocalizedString(desc, comment: "")])
    }
    required init?(coder: NSCoder) {
        self.errorCodeString = nil
        fatalError("init(coder:) has not been implemented")
    }
}
