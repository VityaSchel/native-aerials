#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

readonly xcode_build=27A266a
readonly team_id=L3W5ZXTBAF
readonly notary_profile=native-aerials
readonly root=/private/tmp/native-aerials-release
readonly repo=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
readonly developer_dir=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
rebuild=
if [ "${1:-}" = --rebuild ]; then
	rebuild=1
	shift
fi
readonly rev=${1:-HEAD}

if [ -z "$rebuild" ] && [ -n "$(git -C "$repo" status --porcelain)" ]; then
	echo "commit or stash your changes first" >&2
	exit 1
fi
commit=$(git -C "$repo" rev-parse --verify "$rev^{commit}")
epoch=$(git -C "$repo" log -1 --no-show-signature --format=%ct "$commit")

hermetic() {
	env -i PATH="$PATH" HOME="$HOME" DEVELOPER_DIR="$developer_dir" TZ=UTC LC_ALL=C SOURCE_DATE_EPOCH="$epoch" "$@"
}

found=$(hermetic xcodebuild -version | awk '/Build version/ { print $3 }')
if [ "$found" != "$xcode_build" ]; then
	echo "Xcode $xcode_build is required, found ${found:-none} at $developer_dir" >&2
	exit 1
fi

signer=
if [ -z "$rebuild" ] && [ -n "$team_id" ]; then
	signer=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: .+ \('"$team_id"'\)"$/ && !found++ { print $2 }') || true
	if [ -z "$signer" ]; then
		echo "no valid Developer ID Application certificate of team $team_id in the keychain" >&2
		exit 1
	fi
fi

mkdir "$root.lock" 2>/dev/null || { echo "$root is in use by another release.sh or verify.sh, or remove $root.lock" >&2; exit 1; }
trap 'rmdir "$root.lock"' EXIT
rm -rf "$root"
mkdir -m 700 "$root"
mkdir "$root/src" "$root/out"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$repo" -c core.autocrlf=false archive "$commit" | tar -x -C "$root/src"
project="$root/src/Native Aerials.xcodeproj"

if [ -z "$rebuild" ]; then
	hermetic xcodebuild -project "$project" -scheme "Native Aerials" -destination platform=macOS -derivedDataPath "$root/test" test > "$root/test.log" 2>&1 ||
		{ echo "tests failed, see $root/test.log" >&2; exit 1; }
fi

hermetic xcodebuild -quiet -project "$project" -scheme "Native Aerials" -configuration Release \
	-destination generic/platform=macOS -derivedDataPath "$root/build" -archivePath "$root/Native Aerials.xcarchive" \
	MAC_OS_X_PRODUCT_BUILD_VERSION="$(hermetic xcrun --sdk macosx --show-sdk-build-version)" archive

app="$root/Native Aerials.xcarchive/Products/Applications/Native Aerials.app"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist"; }
zip="$root/out/native-aerials-v$(plist CFBundleShortVersionString)-macos.zip"
package() {
	rm -f "$zip"
	chmod -R u=rwX,go=rX "$app"
	find "$app" -exec touch -h -d "$(date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ)" {} +
	(cd "$(dirname "$app")" && find "Native Aerials.app" | LC_ALL=C sort | hermetic zip -q -X -y -9 -@ "$zip")
}
package

identity() {
	printf '%s\n' "$HOME" /Users/ "$(id -un)" "$(id -F)" "$(hostname)" "$(dirname "$(getconf DARWIN_USER_DIR)")" \
		"$(scutil --get ComputerName)" "$(scutil --get LocalHostName)" "$(dscl . -read "/Users/$(id -un)" GeneratedUID | cut -d ' ' -f 2)" \
		"$(git -C "$repo" config user.name)" "$(git -C "$repo" config user.email)" "$(git -C "$repo" config user.signingkey)"
	ioreg -rd1 -c IOPlatformExpertDevice | awk -F '"' '/"IOPlatform(UUID|SerialNumber)"/ { print $4 }'
}
if [ -z "$rebuild" ]; then
	leaks=$({ cat "$zip"; find "$app" -type f -exec cat {} +; find "$root/src" -type f -path '*.icon/*' -exec cat {} +; } |
		bundle=$(plist CFBundleIdentifier) perl -0777 -pe 's/\Q$ENV{bundle}\E//g' |
		LC_ALL=C grep -a -o -i -F -f <(identity 2>/dev/null | grep -v '^$') | sort -u | paste -s -d , -) || true
	if [ -n "$leaks" ]; then
		rm "$zip"
		echo "the release contains identifying data: $leaks" >&2
		exit 1
	fi
fi

if [ -n "$signer" ]; then
	rm "$zip"
	codesign --force --options runtime --timestamp --sign "$signer" "$app"
	package
	notarization=$(DEVELOPER_DIR="$developer_dir" xcrun notarytool submit "$zip" --keychain-profile "$notary_profile" --wait --output-format json) || true
	if [ "$(plutil -extract status raw -o - - <<< "$notarization" 2>/dev/null)" != Accepted ]; then
		rm "$zip"
		echo "notarization failed: $notarization" >&2
		exit 1
	fi
	rm "$zip"
	DEVELOPER_DIR="$developer_dir" xcrun stapler staple -q "$app"
	spctl --assess --type execute "$app"
	package
fi

(cd "$root/out" && shasum -a 256 "$(basename "$zip")")
echo "built $commit with Xcode $found into $root/out"
