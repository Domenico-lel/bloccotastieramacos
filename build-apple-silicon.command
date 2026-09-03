#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  print "Errore: gli strumenti Apple non sono ancora installati."
  print "Installa gli strumenti proposti da macOS e riprova."
  exit 1
fi

build_dir="$PWD/build-apple-silicon"
app_path="$build_dir/iBlock.app"
contents_path="$app_path/Contents"
executable_path="$contents_path/MacOS/iBlock"
compiled_executable="$build_dir/iBlock-arm64.compiled"
module_cache="$build_dir/ModuleCache"

mkdir -p "$build_dir" "$module_cache"

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -parse-as-library -O -target arm64-apple-macosx13.0 -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  KeyboardLock/KeyboardLockApp.swift KeyboardLock/KeyboardEventLock.swift \
  -o "$compiled_executable"

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp KeyboardLock/Info.plist "$contents_path/Info.plist"
cp KeyboardLock/AppIcon.icns "$contents_path/Resources/AppIcon.icns"
cp "$compiled_executable" "$executable_path"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable iBlock" "$contents_path/Info.plist"

codesign --force --deep --sign - "$app_path"
ditto -c -k --keepParent "$app_path" "$build_dir/iBlock-Apple-Silicon.zip"

print ""
print "Creata: $app_path"
print "Archivio: $build_dir/iBlock-Apple-Silicon.zip"
file "$executable_path"
