param(
  [ValidateSet('windows', 'android-apk', 'android-aab', 'linux', 'macos')]
  [string]$Target = 'windows'
)

$ErrorActionPreference = 'Stop'
flutter pub get
switch ($Target) {
  'windows' { flutter build windows --release }
  'android-apk' { flutter build apk --release }
  'android-aab' { flutter build appbundle --release }
  'linux' { flutter build linux --release }
  'macos' { flutter build macos --release }
}
