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
`rhwp-core.nix` rebuilds it so engine bugs can be fixed here:

- Source: rhwp 0.9.0 from crates.io. It is byte-identical, file by file, to the
  tag IeumOffice pins (`c9095c5f`). The vendored PDF backend comes from that tag
  via a sparse `fetchgit`.
- Patches: IeumOffice's own patches (`vendor/rhwp-core/patches`, in the order of
  its `package.json`), then `rhwp/patches/*.patch`.
- The fetching and patching live in `rhwp/source.nix`, a single patched-source
  derivation shared by `rhwp-core.nix` (wasm engine) and `rhwp-cli.nix`
  (native command line tools), so both run the same code.
- Build: `cargo build --target wasm32-unknown-unknown`, then
  `wasm-bindgen --target web` (0.2.127, as locked), then `wasm-opt -O`. This is
  the same as upstream's `wasm-pack build --target web --release`.
- The generated `rhwp.js` glue is byte-identical to IeumOffice's, and the wasm
  import/export interface is identical. The source package copies the engine
  into `vendor/rhwp-core`; the deb package swaps the two `rhwp_bg.wasm` copies.
- Rendering with the rebuilt engine without our patches is identical to the
  official build. The only differences in a 48-document comparison were
  IeumOffice's own run-to-run noise, which also appears official-vs-official.

| Option | Effect |
| --- | --- |
| `ieumoffice.override { withRhwpFixes = false; }` | source build with the vendored prebuilt engine |
| `ieumoffice-bin.override { rhwpCore = null; }` | deb build with the shipped engine |
| `packages.*.rhwp-core` | the engine alone (`rhwp.js`, `rhwp_bg.wasm`, typings) |
| `packages.*.rhwp-cli` | native `rhwp`, `rhwp-q`, `rhwp-agent` from the same patched source |

### rhwp command line tools (`rhwp-cli.nix`)

`rhwp-core` contains no executables. `rhwp-cli` builds the crate's binaries
natively (default features) from `rhwp/source.nix`:

```sh
nix build .#rhwp-cli          # or: nix profile install .#rhwp-cli
./result/bin/rhwp info file.hwp
./result/bin/rhwp export-svg file.hwp
```

- `rhwp`: viewer / converter / exporter (`rhwp --help`)
- `rhwp-q`: document queries and diagnostics
- `rhwp-agent`: agent tooling
- `font-metric-gen` (`dev-tools` feature) is not built.

The overlay provides it as `pkgs.rhwp-cli` (also `ieumoffice.rhwpCli`).

## Upstream bugs patched here

- **HWP table column narrower than stored, with text pushed out of the cell**
  ([ieumoffice#490](https://github.com/pblsketch/ieumoffice/issues/490), same
  root cause as [rhwp#8626](https://github.com/edwardkim/rhwp/issues/8626)).
  `rhwp/patches/0001-table-stale-width-consensus.patch` fixes it in the engine.
  - The cause: the table object width is stale (41,563 HU), while every row that
    closes on its own agrees on 46,971 HU. rhwp discarded all those rows as
    "wider than the table". So a column defined by a single such row (영 수 인,
    8,846 HU) was split evenly with its neighbour.
  - The fix: when the closed rows agree, their width is the table's effective
    width, and each such row is drawn on its own accumulated cell boundaries,
    as Hancom does.
  - Render-tree regression over 378 documents (rhwp samples + local files):
    only the issue's document changes.

- **HWP 파일 → 문서 정보: 닫기 does nothing.** `DocumentInfoDialog`
  (`apps/hwp/studio-plugin/document-info.mjs`) relabels rhwp's `ModalDialog`
  confirm button to 닫기 but defines no `onConfirm()`. The click throws
  `this.onConfirm is not a function` before `hide()`, so only × closes the
  dialog. Both packages add `onConfirm() { return true }`. The source build
  patches the plugin; the deb build patches the minified studio bundle.
  When upgrading, drop the patch once upstream adds `onConfirm()`
  (`--replace-fail` makes the build fail if the code changes).
- **HWP editor freezes on font changes:** see the open-files limit note above.

## Updating to a new release

1. `package-bin.nix`: bump `version` and update the `.deb` `hash`.
2. `package-source.nix`: bump `version` and update `src.hash`, `cargoHash` and
   `npmDepsHash`.
3. If upstream changed them, update the pinned inputs:
   - `vendor/rhwp-core/package.json`: `rhwp.tag` / `rhwp.commit` give
     `rhwpTag` and the `rhwpStudio` rev. The sparse patterns are in
     `apps/hwp/scripts/build-studio.mjs`.
   - `apps/hwp/scripts/hanja-dict.mjs`: `HANJA_COMMIT`.
   - `vendor/drawio/drawio.json`: the draw.io version and sha256.
   - The Electron major (`electron_43`) in `package.json`.

Set a hash to `lib.fakeHash`, build, and copy the `got:` value Nix prints.
