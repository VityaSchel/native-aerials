# Native Aerials Reproducibility

Reproducibility verifies that a released artifact was built from a given source code snapshot. Anyone with the pinned Xcode on an Apple silicon Mac can rebuild a release from its commit and compare it with the published zip, so you trust the code rather than whoever built it. The release notes carry the zip's SHA-256 in a message signed with the maintainer's GPG key, and the release tag is signed with the same key.

- [Native Aerials Reproducibility](#native-aerials-reproducibility)
    - [What is reproducible](#what-is-reproducible)
    - [Pinned inputs](#pinned-inputs)
    - [Building a release](#building-a-release)
    - [Signing and notarizing](#signing-and-notarizing)
    - [Verifying a release](#verifying-a-release)
    - [Known limits](#known-limits)

## What is reproducible

- **Canonical builder:** macOS 27 on Apple silicon with Xcode 27.0 (27A266a)
- **Official releases:** built locally by the maintainer with `scripts/release.sh`, not attested
- **Artifact:** `native-aerials-v<version>-macos.zip`, Apple silicon only, signed with the maintainer's Developer ID and the hardened runtime, notarized, with the ticket stapled

Apart from the signature and the ticket, the zip does not depend on where the repository is cloned, `HOME`, `TMPDIR`, `USER`, `PATH`, locale, shell, umask, your global Git config or where Xcode is installed. The builder's macOS build is replaced by the SDK's. The build contains nothing about the person who built it, such as a user name, home path, host name or hardware ID, and `scripts/release.sh` refuses to produce a zip that does. The Developer ID signature, added after that check, is the only part that names the maintainer and their team.

## Pinned inputs

| Input                                       | Where it's pinned                                                                                    |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Swift compiler, linker, macOS SDK, `actool` | Xcode build `27A266a`, checked by `scripts/release.sh`                                               |
| Source tree                                 | the commit, exported with `git archive` without your global and system Git config                    |
| Build path                                  | `/private/tmp/native-aerials-release`                                                                |
| `BuildMachineOSBuild` in `Info.plist`       | the SDK build instead of the builder's macOS build                                                   |
| Command line tools                          | `/usr/bin`, `/bin`, `/usr/sbin` and `/sbin` only                                                     |
| Environment of `xcodebuild` and `zip`       | reset with `env -i` to `PATH`, `HOME`, `DEVELOPER_DIR`, `TZ=UTC`, `LC_ALL=C` and `SOURCE_DATE_EPOCH` |
| Timestamps                                  | the commit time                                                                                      |
| File modes                                  | `755` for folders and executables, `644` for the rest                                                |
| Zip layout                                  | sorted entries, no extra fields (`zip -X -y -9`)                                                     |

`codesign`, `zip`, `ditto` and `assetutil` come from macOS itself and cannot be pinned.

The icon's layer images in `Native Aerials/AppIcon.icon/Assets` are committed, and the build doesn't regenerate them. To check them, run `swift scripts/icon-panes.swift DIR && swift scripts/icon-satin.swift DIR` and compare `DIR` with that folder: all eight files match byte for byte. `icon-satin.swift` reads the pane SVGs that `icon-panes.swift` writes, so run it second. Without `DIR`, both scripts write into the repository.

The build always runs at the same absolute path, because Swift and the linker record it in ways that no flag removes. The Swift compiler writes the length of each source file's path into the escape checks for closures passed to Objective-C blocks. With debug info, the linker records the Swift module's path, which changes the binary's `LC_UUID`. `-file-prefix-map` and `-oso_prefix` fix neither. The build path says nothing about the builder, and the script exports the commit there, so the clone itself can live anywhere.

## Building a release

You need a clean working tree and Xcode 27A266a. Set `DEVELOPER_DIR` if Xcode is not at `/Applications/Xcode.app`. Signing and notarizing also need the [one-time setup](#signing-and-notarizing).

```bash
scripts/release.sh          # or scripts/release.sh <commit or tag>
```

The script exports the commit, runs the tests, archives the Release build, zips it and scans it for identifying data. When `team_id` is set, it then signs the app with Developer ID, notarizes it, staples the ticket and zips it again the same way. It writes `native-aerials-v<version>-macos.zip` to `/private/tmp/native-aerials-release/out` and prints the zip's SHA-256 and the commit it was built from. The version comes from the app.

To publish, commit everything first, because the commit time sets the zip's timestamps. Sign a tag with `git tag -s v<version>`, run `scripts/release.sh v<version>`, push the tag and attach the zip to a release for it. Put the script's last two lines, the zip's SHA-256 and `built <commit> with Xcode <build>`, in the release notes as a message signed with `gpg --clearsign`.

The scan runs before signing, because a Developer ID signature necessarily carries the maintainer's name and team ID from the certificate. It fails the release if the zip, the unpacked app or the icon sources contain any of these from the builder's Mac:

- home path, `/Users/` or per-user folder in `/var/folders`
- user name, full name or account UUID
- host name or computer name
- Git name, email or signing key
- hardware UUID or serial number

The bundle identifier and the repository URL `https://git.hloth.dev/hloth/native-aerials`, which the About window links to, are the only places the user name may appear. The scan reads the `.icon` sources because `actool` compresses them into `Assets.car`, where SVG metadata such as an export path or creator name would otherwise go unnoticed.

The archive in the build root holds the matching dSYM for symbolicating crash reports. The next `release.sh` or `verify.sh` run deletes it along with `out/`, so copy both somewhere else first.

## Signing and notarizing

`team_id` at the top of `scripts/release.sh` is the maintainer's Apple Developer team ID. After the scan, `release.sh` signs the app with that team's Developer ID Application certificate, with the hardened runtime, a secure timestamp and no entitlements. It submits the zip with `xcrun notarytool submit --wait` and stops unless the result is `Accepted`, then staples the ticket to the app with `xcrun stapler staple`, checks the result with `spctl` and zips it again. If any of these steps fails, no zip is left in `out/`. These steps run outside the `env -i` environment, because they need your keychain and Apple's servers.

With `team_id` empty, `release.sh` skips these steps, and the zip holds the app as Xcode signed it: ad-hoc with the hardened runtime, not notarized. Setting `team_id` is the only change needed to switch to Developer ID.

Before the first signed release, set up the Mac that builds it once:

1. Create a Developer ID Application certificate in your Apple Developer account and install it with its private key in your login keychain. `security find-identity -v -p codesigning` must list it as `Developer ID Application: <name> (<team ID>)`; if it doesn't, install the Developer ID G2 intermediate certificate from apple.com/certificateauthority.
2. Create an app-specific password for your Apple Account at account.apple.com and store it as the `native-aerials` profile that `release.sh` uses. `notarytool` asks for the password, checks it with Apple and saves it in your login keychain:

    ```bash
    xcrun notarytool store-credentials native-aerials --apple-id <Apple Account email> --team-id <team ID>
    ```

3. Set `readonly team_id=<team ID>` in `scripts/release.sh` and commit it.

`release.sh` looks for the certificate before it builds anything and stops if there is none. `release.sh --rebuild`, which `verify.sh` runs, never signs or notarizes, so verifying a release needs neither the certificate nor an Apple Account.

## Verifying a release

```bash
# 1. Check out the release's tag and its signature
git checkout v1.0.1
git verify-tag v1.0.1

# 2. Fetch the zip from https://git.hloth.dev/hloth/native-aerials/releases, then rebuild and compare
scripts/verify.sh /path/to/native-aerials-v1.0.1-macos.zip
```

`verify.sh` rebuilds the checked-out commit, or the one given as a second argument, skipping the tests, the scan, signing and notarizing. If the zips are identical, it stops there. They never are: the rebuild has no Developer ID signature or ticket, and `Assets.car` differs on every build anyway (see [Known limits](#known-limits)). Otherwise it unpacks both and:

1. requires the published app to have the hardened runtime and the same entitlements as the rebuild
2. copies the published signature, `_CodeSignature` and stapled ticket in `Contents/CodeResources`, if any, onto the rebuild
3. compares `Assets.car` by size and content (see below)
4. requires every file and mode to match byte for byte, and the published signature to be valid

A Developer ID signature can't be reproduced without the maintainer's key, and the ticket comes from Apple's notary service, so a rebuild has neither. Signing and stapling change nothing but the signature in the executable, `Contents/_CodeSignature` and `Contents/CodeResources`. With those grafted, every other byte must be this build, and the published signature, which seals the hash of every file, must be valid.

To also check who signed the app and that Apple notarized it, unpack the zip and run `spctl -a -vv "Native Aerials.app"`. It prints `source=Notarized Developer ID` and `origin=Developer ID Application: <name> (<team ID>)`, and the team ID must match `team_id` in `scripts/release.sh`.

## Known limits

- Only Xcode 27A266a reproduces the release. Another Xcode build produces a different binary.
- Tested on macOS 27.0 (26A428) on Apple silicon. `codesign` and `zip` on another macOS may produce different signature or zip bytes. `verify.sh` handles both because it compares the unpacked apps.
- The release is Apple silicon only: `verify.sh` grafts an arm64 signature and expects a thin arm64 executable.
- `actool` writes a different `Assets.car` on every build, because it names the icon's flattened fallback image after a random temporary file, which also changes the catalog's index. No `actool` option or environment variable changes this. The icon is rendered by Xcode's own asset runtime (`assetutil --info` reports `via AssetCatalogAgent-AssetRuntime`), not by the CoreUI in macOS. `verify.sh` therefore compares `Assets.car` by content: the `assetutil --info` rendition list without timestamps and digests, and a sorted SHA-256 of every rendition with the random names blanked. It also requires the same file size, but does not compare the bytes outside the renditions, such as the BOM index and free space. `AppIcon.icns` is identical. A verifier on another macOS build may get a different `Assets.car`.
- `verify.sh` checks what the published signature covers, its entitlements and the hardened runtime. It does not check who signed the app or the ticket; `spctl` does, as above.
- The export ignores your global and system Git config, so a file stored in Git LFS would be built from its pointer. Keep every build input, such as the PNG layers in `AppIcon.icon`, out of LFS.
- Both scripts wipe and reuse `/private/tmp/native-aerials-release`, including `out/` and the archive, so only one runs at a time. A killed run can leave `/private/tmp/native-aerials-release.lock` behind; remove it with `rmdir /private/tmp/native-aerials-release.lock`.
