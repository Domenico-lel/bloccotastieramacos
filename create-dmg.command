#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  print "Uso: create-dmg.command /percorso/iBlock.app /percorso/iBlock.dmg"
  exit 2
fi

app_path="$1"
dmg_path="$2"

if [[ ! -d "$app_path" ]]; then
  print "Errore: app non trovata: $app_path"
  exit 1
fi

staging_dir="$(mktemp -d /tmp/iblock-dmg.XXXXXX)"
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

cp -R "$app_path" "$staging_dir/iBlock.app"
ln -s /Applications "$staging_dir/Applications"

if [[ -f "Installer/background.png" ]]; then
  mkdir -p "$staging_dir/.background"
  cp "Installer/background.png" "$staging_dir/.background/background.png"
fi
if [[ -f "Installer/dmg-layout.DS_Store" ]]; then
  cp "Installer/dmg-layout.DS_Store" "$staging_dir/.DS_Store"
fi

hdiutil create \
  -volname "Installa iBlock" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path" >/dev/null

hdiutil verify "$dmg_path" >/dev/null
print "Installer: $dmg_path"
