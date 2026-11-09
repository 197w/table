Pod::Spec.new do |s|
  s.name             = 'table_glass'
  s.version          = '0.1.0'
  s.summary          = 'Natywne przyciski Liquid Glass nad widokiem Fluttera.'
  s.description      = 'Szklany przycisk iOS 26 w oknie aplikacji, nad widokiem Fluttera, np. „Zamknij” w oknach od dołu.'
  s.homepage         = 'https://github.com/197w/table'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Table' => 'kontakt@table.pl' }
  s.source           = { :path => '.' }
  s.source_files     = 'table_glass/Sources/table_glass/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
