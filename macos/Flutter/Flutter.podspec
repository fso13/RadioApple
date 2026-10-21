Pod::Spec.new do |s|
  s.name             = 'Flutter'
  s.version          = '1.0.0'
  s.summary          = 'Placeholder to satisfy iOS Flutter deps on macOS'
  s.homepage         = 'https://flutter.dev'
  s.license          = { :type => 'BSD' }
  s.author           = { 'Flutter Dev Team' => 'flutter-dev@googlegroups.com' }
  s.source           = { :git => 'https://github.com/flutter/engine', :tag => s.version.to_s }
  s.osx.deployment_target = '10.14'
  s.vendored_frameworks = 'path/to/nothing'
end
