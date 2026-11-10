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
- The app normally symlinks its CLI into `/usr/local/bin` or `~/.local/bin` on
  every launch. That is disabled when running from `/nix/store`: the link would
  pin a store path and shadow `bin/ieumoffice`. Use `ieumoffice-cli`, or
  `ln -s $(which ieumoffice-cli) ~/.local/bin/ieumoffice` if agent tools expect
  the `ieumoffice` name.
- The in-app updater is inactive. Upstream only enables it for AppImage on
  Linux, and the updater files are removed. Update by bumping this flake.
- Wayland: set `NIXOS_OZONE_WL=1` to run natively on Wayland.

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
