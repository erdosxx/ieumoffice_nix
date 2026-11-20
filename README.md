# IeumOffice (이음오피스) for Nix

Nix flake for [IeumOffice](https://github.com/pblsketch/ieumoffice), a free
open-source office suite (Word, Excel, PowerPoint, PDF, HWP/HWPX, Markdown,
mind maps, draw.io diagrams) with AI.

## Run

```shell
nix run github:erdosxx/ieumoffice_nix                    # GUI (source build)
nix run github:erdosxx/ieumoffice_nix -- report.hwpx
nix run github:erdosxx/ieumoffice_nix#cli -- --help      # command line tool
nix run github:erdosxx/ieumoffice_nix#ieumoffice-bin     # from the release .deb
```

## Versions

| Package | Upstream |
| --- | --- |
| `ieumoffice` (source) | `main` at [`18cfc71`](https://github.com/pblsketch/ieumoffice/commit/18cfc7150a2028487a2ae669a324d02bae93570a) (v0.13.0 + 33 commits), version `0.13.0-unstable-2026-11-19` |
| `ieumoffice-bin` (deb) | release [v0.13.0](https://github.com/pblsketch/ieumoffice/releases/tag/v0.13.0) |
| `rhwp-core`, `rhwp-cli` | rhwp 0.9.0 + the source build's `vendor/rhwp-core` patches (41, `0.9.0-ieum.34`) |

## Outputs

| Output                    | Description                                                     |
| ------------------------- | --------------------------------------------------------------- |
| `packages.*.ieumoffice`   | **Built from source** (default)                                 |
| `packages.*.ieumoffice-bin` | Upstream release `.deb`, patched with `autoPatchelfHook`      |
| `apps.*.default` / `apps.*.cli` | GUI / `ieumoffice-cli`                                    |
| `overlays.default`        | Adds `pkgs.ieumoffice` and `pkgs.ieumoffice-bin`               |

Both packages install:

- `bin/ieumoffice`: the GUI.
- `bin/ieumoffice-cli`: the bundled CLI (`info`, `convert`, `render`, `hwp`, `sheet`, `mcp`, ...).
- A desktop entry, icons, MIME types and "new document" templates.

## Use in NixOS / home-manager

```nix
inputs.ieumoffice = {
  url = "github:erdosxx/ieumoffice_nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

home.packages = [ inputs.ieumoffice.packages.${system}.default ];   # or .ieumoffice-bin
```

## UI language

The UI follows the OS locale (`LANG`), so it is English with `en_US.UTF-8`. To
fix the language, use `uiLanguage` (works for both packages):

```nix
inputs.ieumoffice.packages.${system}.default.override { uiLanguage = "ko"; }
```

- It sets upstream's `GENOFFICE_LANG` in `bin/ieumoffice`, `bin/ieumoffice-cli`
  and the desktop entry. Every module (home, docs, sheets, HWP, ...) reads it.
- It is a thin wrapper around the unchanged package (`passthru.unwrapped`), so
  changing the language never rebuilds the app.
- Supported values: `zh en ja ko fr de es th id ru ar pt it pl cs nl ms he hi
  zh-TW vi`. Anything else fails at evaluation.
- While it is set, a language picked in the app's settings lasts only until the
  next start. To override it for one run: `GENOFFICE_LANG=en ieumoffice`.
- Without the option (`null`, the default), you can still choose the language in
  the app's own settings. The app stores it in
  `~/.config/IeumOffice/app-settings.json`.

## How the source build works (`package-source.nix`)

- `xlsx-sidecar` (Rust, `apps/sheets/native/xlsx-engine`) is built with
  `rustPlatform.buildRustPackage`.
- The npm workspace is installed with `buildNpmPackage` (`npmDepsHash`). The
  root `postinstall` (Electron download) is removed. nixpkgs `electron_43` is
  placed in `node_modules/electron/dist`.
- The upstream build downloads three things itself. They are prefetched and put
  in its caches:
  - `rhwp-studio`: sparse `fetchgit` of `edwardkim/rhwp` at the pinned commit,
    without the GBs of sample documents.
  - libhangul `hanja.txt`.
  - draw.io `draw.war`.
- `npm run build:all` runs, then `electron-builder --linux --dir` on top of the
  nixpkgs Electron. The output is the same layout as the official deb, under
  `opt/IeumOffice`.
- `THIRD-PARTY-NOTICES.txt` is generated offline. The two Rust crate lists
  (which need `cargo metadata` with network) remain pointers.

## Nix-specific adjustments (both packages)

- `chrome-sandbox` is removed. The nix store is `nosuid`, so Chromium uses its
  user-namespace sandbox instead. The source build also sets
  `CHROME_DEVEL_SANDBOX=""`; nixpkgs' source-built Chromium crashes (SIGILL)
  without it.
- The Electron binary is wrapped **in place** (`opt/IeumOffice/ieumoffice`).
  The bundled CLI and the headless export (`convert … --to pdf`, `render`)
  start that path directly, so they get the same environment.
- The wrapper raises the soft open-files limit (`ulimit -Sn`) to the hard
  limit. Desktop sessions usually start programs with a soft limit of 1024.
  Chromium raises it only for its browser process, after the zygote is forked,
  so every renderer keeps 1024. The HWP editor keeps a file descriptor open for
  each installed font it touches (font picker previews, name lookups, font data
  for its renderer). With thousands of fonts it reaches 1024, and the next
  `FontData.blob()` deadlocks in a synchronous `BlobRegistry::Register` call.
  The editor then freezes on font changes, in the official build too.
- The app normally symlinks its CLI into `/usr/local/bin` or `~/.local/bin` on
  every launch. That is disabled when running from `/nix/store`: the link would
  pin a store path and shadow `bin/ieumoffice`. Use `ieumoffice-cli`, or
  `ln -s $(which ieumoffice-cli) ~/.local/bin/ieumoffice` if agent tools expect
  the `ieumoffice` name.
- The in-app updater is inactive. Upstream only enables it for AppImage on
  Linux, and the updater files are removed. Update by bumping this flake.
- Wayland: set `NIXOS_OZONE_WL=1` to run natively on Wayland.

## rhwp engine rebuilt from source (`rhwp-core.nix`)

IeumOffice ships the rhwp HWP/HWPX engine prebuilt as `vendor/rhwp-core/rhwp_bg.wasm`.
`rhwp-core.nix` rebuilds it so engine bugs can be fixed here. The rebuilt engine
replaces the shipped one only while `rhwp/patches/` has patches; there are none
at the moment (upstream took our fix, see below), so both packages run
IeumOffice's own engine and `rhwp-core` is the same engine rebuilt.

- Source: rhwp 0.9.0 from crates.io. It is byte-identical, file by file, to the
  tag IeumOffice pins (`c9095c5f`). The vendored PDF backend comes from that tag
  via a sparse `fetchgit`.
- Patches: IeumOffice's own patches (`vendor/rhwp-core/patches`, in the order of
  its `package.json`), then `rhwp/patches/*.patch` in name order (the
  directory may be absent).
- The fetching and patching live in `rhwp/source.nix`, a single patched-source
  derivation shared by `rhwp-core.nix` (wasm engine) and `rhwp-cli.nix`
  (native command line tools), so both run the same code.
- Build: `cargo build --target wasm32-unknown-unknown`, then
  `wasm-bindgen --target web` (0.2.127, as locked), then `wasm-opt -O`. This is
  the same as upstream's `wasm-pack build --target web --release`.
- The generated `rhwp.js` glue is byte-identical to IeumOffice's, and the wasm
  import/export interface is identical (checked again at `18cfc71`; the
  typings differ only in declaration order). With local patches, the source
  package copies the engine into `vendor/rhwp-core`, and the deb package swaps
  its two `rhwp_bg.wasm` copies.
- The deb (a release) and the source build (a commit) can carry different
  `vendor/rhwp-core` patch sets: v0.13.0 ships `0.9.0-ieum.33` (40 patches),
  `18cfc71` has `0.9.0-ieum.34` (41). Before swapping the deb's engine, check
  that the rebuilt `rhwp.d.ts` matches the deb's engine interface.
- Rendering with the rebuilt engine without our patches is identical to the
  official build. The only differences in a 48-document comparison were
  IeumOffice's own run-to-run noise, which also appears official-vs-official.

| Option | Effect |
| --- | --- |
| `ieumoffice.override { withRhwpFixes = false; }` | source build with the vendored prebuilt engine even when `rhwp/patches` has fixes |
| `ieumoffice-bin.override { rhwpCore = null; }` | deb build with the shipped engine even when `rhwp/patches` has fixes |
| `packages.*.rhwp-core` | the engine alone (`rhwp.js`, `rhwp_bg.wasm`, typings) |
| `packages.*.rhwp-cli` | native `rhwp`, `rhwp-q`, `rhwp-agent` from the same patched source |

### rhwp command line tools (`rhwp-cli.nix`)

`rhwp-core` contains no executables. `rhwp-cli` builds the crate's binaries
natively from `rhwp/source.nix`, like upstream's
`cargo build --release --features native-skia`:

```sh
nix build .#rhwp-cli          # or: nix profile install .#rhwp-cli
./result/bin/rhwp info file.hwp
./result/bin/rhwp export-svg file.hwp
./result/bin/rhwp export-png file.hwp -o out   # native-skia
```

- `native-skia` enables the Skia renderer: `export-png`, `export-sixel`,
  `export-kitty`. skia-bindings would download rust-skia's prebuilt
  binaries, which the sandbox forbids, so Skia is compiled from source (as in
  nixpkgs' neovide): `rhwp/skia.nix` provides `SKIA_SOURCE_DIR` (rust-skia/skia
  `m156.5`, the tag skia-bindings 0.156.0 pins, plus the externals from
  `rhwp/skia-externals.json`). When skia-bindings is bumped, update the tag
  and the externals (from skia's `DEPS`).
- `rhwp-cli.override { withSkia = false; }` builds the default features only.

- `rhwp`: viewer / converter / exporter (`rhwp --help`)
- `rhwp-q`: document queries and diagnostics
- `rhwp-agent`: agent tooling
- `font-metric-gen` (`dev-tools` feature) is not built.

The overlay provides it as `pkgs.rhwp-cli` (also `ieumoffice.rhwpCli`).

## Upstream bugs patched here

- **HWP editor freezes on font changes:** see the open-files limit note above.
  The wrapper keeps raising the limit. `18cfc71` also reads installed font
  metadata in the main process instead of renderer blobs (#591), which may
  make it unnecessary for the source build (not verified; the v0.13.0 deb
  does not have #591).

### Fixed upstream (our patches dropped)

- **HWP table column narrower than stored, with text pushed out of the cell**
  ([ieumoffice#490](https://github.com/pblsketch/ieumoffice/issues/490),
  [rhwp#8626](https://github.com/edwardkim/rhwp/issues/8626)). Our
  `rhwp/patches/0001-table-stale-width-consensus.patch` (until 0.12.12) is
  replaced by IeumOffice's `0047-stale-table-width-rows-outvote.patch` (in
  v0.13.0), which no longer lets ours apply. It draws such tables at the cell
  widths, as Hancom's print does. Checked with the issue's document: 영 수 인
  is drawn at full width with the text inside.
- **HWP 파일 → 문서 정보: 닫기 does nothing** (`this.onConfirm is not a
  function`, #487). `DocumentInfoDialog` defines `onConfirm()` since v0.13.0;
  both packages dropped their patch.

## Updating to a new release

1. `package-bin.nix`: bump `version` and update the `.deb` `hash`.
2. `package-source.nix`: set `rev` (a tag is `"v${version}"`) and `version`
   (`X.Y.Z-unstable-YYYY-MM-DD` for a commit), then update `src.hash`,
   `cargoHash` and `npmDepsHash`.
3. If upstream changed them, update the pinned inputs:
   - `vendor/rhwp-core/package.json`: `rhwp.tag` / `rhwp.commit` give
     `rhwpTag` and the `rhwpStudio` rev. The sparse patterns are in
     `apps/hwp/scripts/build-studio.mjs`.
   - `apps/hwp/scripts/hanja-dict.mjs`: `HANJA_COMMIT`.
   - `vendor/drawio/drawio.json`: the draw.io version and sha256.
   - The Electron major (`electron_43`) in `package.json`.

4. Check every local patch against the new tree: the `substituteInPlace
   --replace-fail` calls in both packages fail the build when their target
   changes, and `rhwp/patches/*.patch` must still apply after the new
   `vendor/rhwp-core/patches` list. Drop the ones upstream has fixed.

Set a hash to `lib.fakeHash`, build, and copy the `got:` value Nix prints.
