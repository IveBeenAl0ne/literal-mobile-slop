# Tycoon Hub

A native Godot 4.5.1 app for **Android and iOS** that runs a collection of downloadable, data-driven 3D tycoon games. One installed app contains the shared mechanics; new games are published as JSON packs and downloaded from your catalog server. Downloaded packs and progress remain on the device for offline play.

This is a working first foundation, not a polished commercial engine or a reproduction of any screenshot's original game. The source is maintained in [IveBeenAl0ne/literal-mobile-slop](https://github.com/IveBeenAl0ne/literal-mobile-slop). There is no deployed catalog server yet. The GitHub workflows are supplied but have not been run on hosted runners.

![Native runtime preview](docs/runtime-preview.png)

## Included

- Native 3D world, orthographic follow camera, animated simple characters, visible carried stacks, joystick and keyboard movement.
- Sources, processors, shops, gradual spending on unlock pads, prerequisites, helpers, customer visuals, and progression prompts.
- Three independently playable starter games: Sunny Farm, Corner Café, Dusty Depot.
- Library screen with HTTP catalog, download/update buttons, SHA-256 checks, bounded and validated packs, atomic installation, independent saves.
- Python catalog server, browser pack editor with draggable layout, JSON import/export, and authenticated local publishing.
- GitHub Actions: gameplay/server tests, Android debug APK, unsigned iOS device build and Xcode project. Optional signed iOS export using your certificate and profile.

## Run on a computer now

1. Install **Godot 4.5.1 standard**, not the .NET edition.
2. Import `client/project.godot`, then press **F6/F5** (F5 runs the app).
3. Pick a starter pack. Use WASD/arrows or drag the joystick. Stand beside a station to harvest, deliver, collect cash, or pay toward a purchase.
4. Harvest from the source on the left; stock the station on the right. Café/depot require taking the processed output to the shop farther north. Standing beside a shop with no items to deliver collects its money.

No Node, Unity, or third-party Python modules are required.

## Create and download a new game

From this repository's root:

```sh
python server/server.py
```

Open `http://localhost:8787/editor` on the server computer. Paste the editor token printed by the server. Select a starter, click **Clone as new game**, change its ID/title/theme/layout and balance, then **Publish**. On updates, keep the same ID and increase the version.

In the phone app enter the server's address and tap **Connect / Refresh catalog**, then **Download**. Use the computer's LAN address on a phone, not `127.0.0.1` (that points at the phone itself). For iOS local development use a local hostname such as `http://your-computer.local:8787`; the iOS preset permits local networking. **Use HTTPS for a hosted server**; arbitrary public HTTP is not enabled in iOS.

Both devices must reach the server. Allow port 8787 in your computer's firewall for LAN testing. The editor only accepts connections/publishing from localhost. Public users only get the catalog and pack files. For production, terminate HTTPS with a reverse proxy or serve the catalog and pack directory from ordinary static hosting.

## GitHub builds

Upload this folder's **contents at the repository root**, including `.github`. On pushes to `main`/`master`, PRs, or manual runs, `Build Tycoon Hub` runs:

1. Python tests and native Godot simulation/world/download tests.
2. Android job creates `TycoonHub-Android-debug` containing an arm64 debug APK.
3. macOS job exports an Xcode project and compiles a device app, packaged as `TycoonHub-unsigned.ipa`. An unsigned IPA requires signing before installation. It is not a directly installable App Store/TestFlight build.

The Android debug keystore is cached to preserve signing identity between builds. Keep that cache; changing keys can require uninstalling the previous APK, which removes its local saves. Release Android signing is not configured yet.

Optional iOS signing: see [docs/builds.md](docs/builds.md). Godot's iOS exports run on macOS with Xcode; simulator exports are not supported by the pinned Godot version. No certificates or provisioning files belong in the repository.

## Pack format and extension boundary

See [docs/pack-format.md](docs/pack-format.md). Packs can define items, stations, production chains, prerequisites, costs, sale prices, timing, colors, positions, and compound low-poly prop models. They contain no executable scripts and no `.pck` mounts. A new pack using existing mechanics needs no app rebuild. Adding a new mechanic, loading arbitrary GLB/textures/audio, or changing shared UI/runtime behavior currently requires an app update.

Saves are per pack ID and reconcile stations by ID. Keep existing station/item IDs stable when publishing updates. Removing an item discards its carried stock on next restore; changing economic rules does not reset an existing balance. Simulation pauses when the app is closed; offline earnings and cloud saves are not implemented.

Customer characters currently provide simple animated presentation. Sales happen on each shop's configured timer and do not depend on a full customer navigation/queue simulation. Workers transfer matching stock on a timer. Detailed character rigs, sound, terrain editing, obstacle navigation, and imported artwork remain future work.

## Checks

```sh
python -m unittest discover -s tests -v
godot --headless --path client --editor --import --quit
godot --headless --path client --script res://tests/test_simulation.gd
godot --headless --path client --script res://tests/test_world.gd
```

The Actions workflow additionally exercises the native client against a real local HTTP server. Tests cover harvesting, processing, delivery, sales, partial purchases, helper transfers, save restoration, invalid packs, publishing/version conflicts, checksums, offline reload, and launching downloaded games.

Engine code in this repository is MIT licensed. Godot is a separate MIT licensed dependency. Original screenshot art has not been copied into the project.
