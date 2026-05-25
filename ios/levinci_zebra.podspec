#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint levinci_zebra.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'levinci_zebra'
  s.version          = '1.0.0'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  
    # Include plugin's Swift/ObjC source
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

    # Zebra SDK as vendored framework
#  s.vendored_frameworks = '**/*.xcframework'
  s.vendored_libraries = '**/*.a'
    # Link system frameworks if SDK needs them
  s.frameworks       = 'CoreBluetooth', 'Foundation', 'QuartzCore', 'ExternalAccessory'
  s.static_framework = true


    # Required Flutter config
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
  'DEFINES_MODULE' => 'YES',
  'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
 }
  s.swift_version = '5.0'


  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'levinci_zebra_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
