Pod::Spec.new do |s|
  s.name             = 'table_car'
  s.version          = '0.1.0'
  s.summary          = 'Kurs dostawcy w CarPlay dla Table for employees.'
  s.description      = 'Ekran bieżącego kursu w CarPlay: adres, klient, płatność, nawigacja i telefon.'
  s.homepage         = 'https://github.com/197w/table'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Table' => 'kontakt@table.pl' }
  s.source           = { :path => '.' }
  s.source_files     = 'table_car/Sources/table_car/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks       = 'CarPlay'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
