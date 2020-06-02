version = `cat ./version`.strip
Pod::Spec.new do |s|  
    s.name      = 'CZiti-iOS'
    s.version   = version
    s.summary   = 'Ziti SDK for Swift (iOS)'
    s.homepage  = 'https://github.com/openziti/ziti-sdk-swift'

    s.author    = { 'ziti-ci' => 'ziti-ci@netfoundry.io'  }
    s.license   = { :type => 'Apache-2.0', :file => 'LICENSE' }

    s.platform  = :ios
    s.source    = { :http => "https://netfoundry.jfrog.io/artifactory/ziti-sdk-swift/#{s.version}/CZiti-iOS.framework.tgz" }

    s.source_files  = '*.{swift,h,m}'
    s.swift_version = '5.0'
    s.public_header_files  = '*.h'

    # s.xcconfig = { 'ENABLE_BITCODE' => 'NO', 'CLANG_ENABLE_MODULES' => 'YES', 'SWIFT_VERSION' => '5.0' }
    # s.xcconfig = { 'ENABLE_BITCODE' => 'NO', 'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'YES' }
    s.xcconfig = { 'ENABLE_BITCODE' => 'NO' }

    s.frameworks = "Foundation"    

    s.ios.deployment_target = '13.4'
    s.ios.vendored_frameworks = 'CZiti.framework'
end  
