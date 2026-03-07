Pod::Spec.new do |s|
  s.name                  = 'xsoulspace_inference_apple_foundation'
  s.version               = '0.1.0'
  s.summary               = 'Apple Foundation Models inference bridge for macOS'
  s.description           = 'Method channel bridge to SystemLanguageModel for xsoulspace_inference_core (macOS 26+ when available).'
  s.homepage              = 'https://github.com/xsoulspace'
  s.license               = { :file => '../LICENSE' }
  s.author                = { 'xsoulspace' => 'dev@xsoulspace.com' }
  s.source                = { :path => '.' }
  s.source_files           = 'Classes/**/*'
  s.platform              = :osx, '10.15'
  s.osx.deployment_target = '10.15'
  s.swift_version         = '5.0'
  s.pod_target_xcconfig    = { 'DEFINES_MODULE' => 'YES' }
  s.frameworks            = 'Foundation'
  # FoundationModels is a system framework on macOS 26+; optional at link time.
  s.weak_frameworks       = 'FoundationModels'
end
