version = `cat ./version`.strip
Pod::Spec.new do |s|  
    s.deprecated_in_favor_of = 'CZiti Swift Package. See https://github.com/openziti/ziti-sdk-swift-dist.git'

    s.name      = 'CZiti-macOS'
    s.version   = version
    s.summary   = 'Ziti SDK for Swift (macOS)'
    s.homepage  = 'https://github.com/openziti/ziti-sdk-swift'

    s.author    = { 'ziti-ci' => 'ziti-ci@netfoundry.io'  }
    s.license   = { :type => 'Apache-2.0', :file => 'LICENSE' }

    s.platform  = :macos
    s.source    = { :http => "https://github.com/openziti/ziti-sdk-swift/releases/download/#{s.version}/CZiti-macOS.framework.tgz" }

    s.source_files  = '*.{swift,h,m}'
    s.swift_version = '5.0'
    s.public_header_files  = '*.h'

    s.xcconfig = { 'ENABLE_BITCODE' => 'NO' }

    s.frameworks = "Foundation"

    s.macos.deployment_target = '10.15'
    s.macos.vendored_frameworks = 'CZiti.framework'
end  
