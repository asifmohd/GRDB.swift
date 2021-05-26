Pod::Spec.new do |s|
  s.name     = 'GRDB.swift'
  s.version  = '5.8.0'
  
  s.license  = { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'A toolkit for SQLite databases, with a focus on application development.'
  s.homepage = 'https://github.com/groue/GRDB.swift'
  s.author   = { 'Gwendal Roué' => 'gr@pierlis.com' }
  s.source   = { :git => 'https://github.com/groue/GRDB.swift.git', :tag => "v#{s.version}" }
  s.module_name = 'GRDB'
  
  s.swift_versions = ['5.2']
  s.platform = :ios, '10.0'
  s.vendored_frameworks = 'GRDB.xcframework'
end
