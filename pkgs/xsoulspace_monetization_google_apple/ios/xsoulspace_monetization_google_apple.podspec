#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint xsoulspace_monetization_google_apple.podspec` to validate.
#
Pod::Spec.new do |s|
  s.name             = 'xsoulspace_monetization_google_apple'
  s.version          = '0.1.0'
  s.summary          = 'A Flutter plugin for Google and Apple monetization.'
  s.description      = <<-DESC
A Flutter plugin for Google and Apple monetization.
                       DESC
  s.homepage         = 'https://github.com/xsoulspace/xsoulspace_monetization_google_apple'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Arenukvern' => 'anton@xsoulspace.dev' }
  s.source           = { :path => '.' }
  s.source_files = 'Sources/xsoulspace_monetization_google_apple/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
