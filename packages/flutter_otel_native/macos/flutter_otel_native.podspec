Pod::Spec.new do |s|
  s.name             = 'flutter_otel_native'
  s.version          = '0.1.0'
  s.summary          = 'Native (Swift) telemetry foundation for flutter_otel.'
  s.description      = <<-DESC
On-disk span/log queue and MethodChannel bridge that let native macOS code
record telemetry before or without a running Dart isolate, forwarded into
flutter_otel's existing OTLP export pipeline.
                       DESC
  s.homepage         = 'https://github.com/cedricziel/flutter-otel'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Cedric Ziel' => 'cedric.ziel@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_otel_native/Sources/flutter_otel_native/**/*',
                    '../native/NativeTelemetryCore/Sources/NativeTelemetryCore/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
