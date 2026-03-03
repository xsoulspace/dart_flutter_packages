Pod::Spec.new do |s|
  s.name             = 'universal_storage_cloudkit_apple'
  s.version          = '0.1.0-dev.1'
  s.summary          = 'CloudKit native bridge plugin for universal_storage.'
  s.description      = <<-DESC
CloudKit native bridge plugin for universal_storage.
                       DESC
  s.homepage         = 'https://github.com/xsoulspace/universal_storage_sync'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'xsoulspace' => 'antonio@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
