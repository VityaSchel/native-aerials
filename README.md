# Native Aerials

**Merge macOS video wallpapers into a single dynamic automatic video aerial.** Notarized, reproducible, no setup.

[<img src="./docs/demo.avif" loading="lazy" width="756" height="395" />](./docs/demo.mp4)

<a href="https://git.hloth.dev/hloth/native-aerials/releases/download/v1.0.0/native-aerials-v1.0.0-macos.zip"><img src="./docs/download-for-the-macos-27-button.svg" width="175" height="56" /></a>

Download → drag to Applications → launch. To uninstall, drag to Trash.

<details>
<summary>How it works under the hood</summary>

- A patched copy of Apple's aerial catalog in `~/Library/Application Support/com.apple.wallpaper/aerials/custom/` that adds only the sun data for the combined sets
- `AerialManifestLocalPathOverride` and `AerialManifestForceLocal` in the `com.apple.wallpaper.aerial` preferences, which point the wallpaper at that copy
- Your saved wallpaper choice, followed by a restart of the wallpaper processes
- `~/Library/LaunchAgents/dev.hloth.native-aerials.agent.plist`, which runs a copy of the app from `~/Library/Application Support/Native Aerials/` whenever the app, the videos or Apple's catalog change

</details>

<details>
<summary>Command line usage (advanced)</summary>

```sh
"/Applications/Native Aerials.app/Contents/MacOS/Native Aerials" --help
# usage: "Native Aerials" <enable|disable|status> [--dry-run DIR]
#        "Native Aerials" sync [set ID] [--dry-run DIR]
#        "Native Aerials" select <asset ID | set ID> [--dry-run DIR]

#   enable     combine every set whose four videos are on disk into one wallpaper with an
#              Automatic option, restart the wallpaper processes, add the background helper
#              and open Wallpaper settings; works only from /Applications or ~/Applications
#   disable    undo everything and put a single-video wallpaper choice back; the next enable
#              brings Automatic back wherever that video is still the choice
#   sync       combine sets that became complete, split sets that lost a video, rebuild after
#              macOS updates (what the background helper runs); with a set ID, also pick
#              that set's Automatic item in the same restart
#   select     set the wallpaper on every desktop; a set ID picks its combined Automatic item.
#              A single video must be on disk: macOS downloads an aerial only when it is
#              picked in System Settings > Wallpaper
#   status     report what is installed, including every set ID and asset ID, read-only
```

</details>

<details>
<summary>Build from source code (advanced)</summary>

You need Xcode 27 on macOS 27. The tests run in dry-run sandboxes and don't touch your settings:

```sh
xcodebuild -project "Native Aerials.xcodeproj" -scheme "Native Aerials" -destination platform=macOS -derivedDataPath /tmp/native-aerials-build test
```

Releases are reproducible, signed & notarized; see [REPRODUCIBILITY.md](REPRODUCIBILITY.md).

</details>

## License

[MIT](./LICENSE)
