#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

readonly root=/private/tmp/native-aerials-release
readonly exe="Contents/MacOS/Native Aerials"
readonly car="Contents/Resources/Assets.car"
readonly work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

cp "${1:?usage: scripts/verify.sh <release zip> [commit]}" "$work/published.zip"
"$(dirname "${BASH_SOURCE[0]}")/release.sh" --rebuild "${2:-HEAD}"
rebuilt_zip=$(find "$root/out" -name '*.zip')
if cmp -s "$work/published.zip" "$rebuilt_zip"; then
	echo "✓ $(basename "$1") is byte-identical to this build"
	exit 0
fi

ditto -x -k "$work/published.zip" "$work/published"
ditto -x -k "$rebuilt_zip" "$work/rebuilt"
published="$work/published/Native Aerials.app"
rebuilt="$work/rebuilt/Native Aerials.app"

entitlements() { codesign -d --entitlements - --xml "$1" 2>/dev/null; }
if [ "$(entitlements "$published")" != "$(entitlements "$rebuilt")" ] || ! [[ $(codesign -dv "$published" 2>&1) =~ flags=[^[:space:]]*runtime ]]; then
	echo "✗ the published app is not signed with the hardened runtime and the entitlements of this build" >&2
	exit 1
fi

read -r offset size < <(otool -l "$published/$exe" | awk '/cmd LC_CODE_SIGNATURE/ { f = 1 } f && /dataoff/ { o = $2 } f && /datasize/ { print o, $2; exit }')
cp "$rebuilt/$exe" "$work/unsigned"
codesign --remove-signature "$work/unsigned"
xcrun codesign_allocate -i "$work/unsigned" -a arm64 "$size" -o "$work/grafted"
dd if="$published/$exe" of="$work/grafted" bs=1 skip="$offset" seek="$offset" count="$size" conv=notrunc 2>/dev/null
cat "$work/grafted" > "$rebuilt/$exe"
rm -rf "$rebuilt/Contents/_CodeSignature" "$rebuilt/Contents/CodeResources"
ditto "$published/Contents/_CodeSignature" "$rebuilt/Contents/_CodeSignature"
if [ -e "$published/Contents/CodeResources" ]; then
	ditto "$published/Contents/CodeResources" "$rebuilt/Contents/CodeResources"
fi

car_content() {
	assetutil --info "$1" | sed -E '/"(Timestamp|SHA1Digest)"/d; s/_[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}-[0-9]+-[0-9A-F]{16}\.png/.png/'
	perl -0777 -MDigest::SHA=sha256_hex -ne '
		s/_[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}-\d+-[0-9A-F]{16}\.png\0*/"\0" x length $&/ge;
		while (/ISTC/g) {
			my ($tlv, $data) = unpack "x168 V x8 V", substr $_, pos() - 4, 184;
			print sha256_hex(substr $_, pos() - 4, 184 + $tlv + $data), "\n";
		}' "$1" | sort
}
if [ -e "$published/$car" ] && [ -e "$rebuilt/$car" ] && [ "$(stat -f %z "$published/$car")" = "$(stat -f %z "$rebuilt/$car")" ] &&
	diff -q <(car_content "$published/$car") <(car_content "$rebuilt/$car") >/dev/null; then
	cat "$published/$car" > "$rebuilt/$car"
fi

listing() {
	(cd "$1" && find . | LC_ALL=C sort | while IFS= read -r path; do
		printf '%s %s %s\n' "$(stat -f %p "$path")" "$(test -f "$path" && shasum -a 256 < "$path")" "$path"
	done)
}
if diff <(listing "$work/published") <(listing "$work/rebuilt") && codesign --verify --deep --strict "$published"; then
	echo "✓ the published app is this build plus its own signature"
else
	echo "✗ the published app does not match this build" >&2
	exit 1
fi
