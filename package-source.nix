# IeumOffice built from source: npm workspaces (electron-vite) + the Rust
# xlsx-sidecar, packaged with electron-builder on top of nixpkgs' Electron.
#
# Network inputs the upstream build fetches itself are prefetched here:
#   - rhwp-studio (sparse checkout of edwardkim/rhwp at the pinned commit)
#   - libhangul's hanja.txt
#   - draw.io's draw.war
{
  lib,
  symlinkJoin,
  stdenv,
  buildNpmPackage,
  rustPlatform,
  fetchFromGitHub,
  fetchgit,
  fetchurl,
  nodejs_22,
  electron_43,
  makeShellWrapper,
  wrapGAppsHook3,
  gtk3,
  gsettings-desktop-schemas,
  libGL,
  libnotify,
  libsecret,
  libva,
  pipewire,
  systemd,
  wayland,
  libxkbcommon,
  xdg-utils,
  # UI language, e.g. "ko". null follows the OS locale (LANG). Sets upstream's
  # GENOFFICE_LANG as a default, so GENOFFICE_LANG=... at run time still wins.
  uiLanguage ? null,
}:

# languages of packages/i18n/src/index.ts (LANGS)
assert
  uiLanguage == null
  || lib.assertOneOf "uiLanguage" uiLanguage [
    "zh"
    "en"
    "ja"
    "ko"
    "fr"
    "de"
    "es"
    "th"
    "id"
    "ru"
    "ar"
    "pt"
    "it"
    "pl"
    "cs"
    "nl"
    "ms"
    "he"
    "hi"
    "zh-TW"
    "vi"
  ];

let
  version = "0.12.12";
  electron = electron_43;

  src = fetchFromGitHub {
    owner = "pblsketch";
    repo = "ieumoffice";
    tag = "v${version}";
    hash = "sha256-bUYY5v7SujPe1wgChzQ2OBCrma+xAMRd7sNiZuT4hBY=";
  };

  # --- pinned inputs (must match the upstream tree at `version`) -----------
  # vendor/rhwp-core/package.json -> rhwp.tag / rhwp.commit
  rhwpTag = "v0.9.0";
  rhwpStudio = fetchgit {
    url = "https://github.com/edwardkim/rhwp.git";
    rev = "c9095c5f67632e6721e800ccc7fb43ea49d26682";
    # SPARSE_PATTERNS in apps/hwp/scripts/build-studio.mjs (skips GBs of samples)
    sparseCheckout = [
      "/LICENSE"
      "/THIRD_PARTY_LICENSES.md"
      "/rhwp-studio/index.html"
      "/rhwp-studio/src/"
      "/rhwp-studio/public/"
      "!/rhwp-studio/public/fonts"
      "!/rhwp-studio/public/samples"
      "/npm/hwpctrl-ocx/src/"
      "/rhwp-shared/"
      "/assets/fonts/enclosed-pua-metrics.json"
      "/src/renderer/square_gradient.sksl"
    ];
    nonConeMode = true;
    hash = "sha256-TRY9nSo5dQLZ8jKRH6obVIxMS+e4EP+LG770sFCOjIc=";
  };

  # apps/hwp/scripts/hanja-dict.mjs -> HANJA_COMMIT
  hanjaCommit = "717409ce61524bb3d8426060a384822f21354c62";
  hanja = fetchurl {
    url = "https://raw.githubusercontent.com/libhangul/libhangul/${hanjaCommit}/data/hanja/hanja.txt";
    hash = "sha256-sQBANFifE1farqNTSmE29rXvglr6h3mIayDwt5CLvjs=";
  };

  # vendor/drawio/drawio.json
  drawioVersion = "v32.6.9";
  drawWar = fetchurl {
    url = "https://github.com/jgraph/drawio/releases/download/${drawioVersion}/draw.war";
    sha256 = "31afc82b7920c409d0591f6126ccb6c377d7800e7f11ab324f88bdf1e4249ce7";
  };

  xlsx-sidecar = rustPlatform.buildRustPackage {
    pname = "ieumoffice-xlsx-sidecar";
    inherit version src;
    sourceRoot = "${src.name}/apps/sheets/native/xlsx-engine";
    cargoHash = "sha256-olgv8fw54naD4HIYmukSG8claEP7koGcK5f5PYOGYZ4=";
    doCheck = false;
  };

  # libraries Electron/Chromium dlopen at run time
  runtimeLibs = [
    libGL
    libnotify
    libsecret
    libva
    pipewire
    systemd
    wayland
    libxkbcommon
  ];
  withUiLanguage = import ./with-ui-language.nix { inherit lib symlinkJoin makeShellWrapper; };

  unwrapped = buildNpmPackage {
    pname = "ieumoffice";
    inherit version src;

    nodejs = nodejs_22;
    npmDepsHash = "sha256-lQysdzi8POdLUcHOZKD8pScfkAqoNWAt83v16d7YQdM=";
    makeCacheWritable = true;

    env = {
      ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    };

    nativeBuildInputs = [
      makeShellWrapper
      wrapGAppsHook3
    ];
    buildInputs = [
      gtk3
      gsettings-desktop-schemas
    ];
    dontWrapGApps = true;

    postPatch = ''
          # the root postinstall downloads Electron; nixpkgs' Electron is used instead
          substituteInPlace package.json \
            --replace-fail '"postinstall": "install-electron",' ""

          # the sidecar is built by the xlsx-sidecar derivation
          substituteInPlace apps/sheets/package.json \
            --replace-fail '"build": "npm run native:build && electron-vite build"' '"build": "electron-vite build"'

          # rhwp-studio is prefetched (no git / network in the sandbox)
          substituteInPlace apps/hwp/scripts/build-studio.mjs \
            --replace-fail '  fetchSource()
        checkPluginHooks()' '  checkPluginHooks()'

          # Don't symlink the CLI into ~/.local/bin from the nix store
          # (bin/ieumoffice-cli provides it); see package-bin.nix.
          substituteInPlace apps/shell/src/main/cli-link.ts \
            --replace-fail 'const outcome = installCliLink({ launcher })' \
              'const outcome = process.resourcesPath.startsWith("/nix/store/") ? { status: "skipped (nix store)" } : installCliLink({ launcher })'

          # Third-party notices are generated in buildPhase without network; the rhwp
          # crate list (needs a git checkout + cargo metadata) stays a pointer.
          substituteInPlace apps/shell/electron-builder.cjs \
            --replace-fail '    ensureThirdPartyNotices()
      ' ""
    '';

    buildPhase = ''
      runHook preBuild

      # nixpkgs' Electron where the npm package would have downloaded it
      # (electron-builder copies it into the app and reads LICENSES.chromium.html)
      rm -rf node_modules/electron/dist
      cp -r ${electron.dist} node_modules/electron/dist
      chmod -R u+w node_modules/electron/dist

      mkdir -p apps/sheets/native/xlsx-engine/target/release
      cp ${xlsx-sidecar}/bin/xlsx-sidecar apps/sheets/native/xlsx-engine/target/release/

      mkdir -p vendor/drawio/.cache/${drawioVersion}
      cp ${drawWar} vendor/drawio/.cache/${drawioVersion}/draw.war

      mkdir -p apps/hwp/node_modules/.cache/libhangul-hanja/${hanjaCommit}
      cp ${hanja} apps/hwp/node_modules/.cache/libhangul-hanja/${hanjaCommit}/hanja.txt

      mkdir -p apps/hwp/node_modules/.cache/rhwp-studio
      cp -r ${rhwpStudio} apps/hwp/node_modules/.cache/rhwp-studio/${rhwpTag}
      chmod -R u+w apps/hwp/node_modules/.cache/rhwp-studio

      npm run build:all
      node tools/gen-third-party-notices.mjs

      pushd apps/shell
      npx electron-builder --linux --dir --publish never \
        -c.electronDist=$PWD/../../node_modules/electron/dist \
        -c.electronVersion=${electron.version}
      popd

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      app=$out/opt/IeumOffice
      mkdir -p $out/opt $out/bin
      cp -r apps/shell/release/linux-unpacked $app
      rm -f $app/chrome-sandbox $app/resources/app-update.yml $app/resources/default_app.asar

      # icons, desktop entry, MIME types, "new document" templates
      for s in 16 32 48 64 128 256 512; do
        install -Dm644 apps/shell/build/icons/''${s}x''${s}.png \
          $out/share/icons/hicolor/''${s}x''${s}/apps/ieumoffice.png
      done
      install -Dm644 ${./ieumoffice.desktop} $out/share/applications/ieumoffice.desktop
      substituteInPlace $out/share/applications/ieumoffice.desktop --subst-var out
      mkdir -p $out/share/templates
      cp $app/resources/shell-new/blank.docx "$out/share/templates/IeumOffice Document.docx"
      cp $app/resources/shell-new/blank.xlsx "$out/share/templates/IeumOffice Spreadsheet.xlsx"
      cp $app/resources/shell-new/blank.pptx "$out/share/templates/IeumOffice Presentation.pptx"

      runHook postInstall
    '';

    postFixup = ''
      app=$out/opt/IeumOffice
      # Wrapped in place: the bundled CLI (resources/cli/ieumoffice) and the app's
      # headless export start ../../ieumoffice directly, so they need the env too.
      #
      # ulimit: raise the soft open-files limit (often 1024 in desktop sessions) to
      # the hard limit. Chromium raises it only for the browser process, after the
      # zygote is forked, so renderers keep 1024. The HWP editor keeps one fd per
      # local font it touches; at 1024 the next font blob() deadlocks and the editor
      # freezes.
      #
      # CHROME_DEVEL_SANDBOX: nixpkgs' source-built Chromium traps (SIGILL) when it
      # is unset; any value makes it fall back to the user-namespace sandbox.
      wrapProgramShell $app/ieumoffice \
        --run 'ulimit -Sn "$(ulimit -Hn)" 2>/dev/null || true' \
        --set-default CHROME_DEVEL_SANDBOX "" \
        "''${gappsWrapperArgs[@]}" \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs} \
        --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

      ln -s $app/ieumoffice $out/bin/ieumoffice
      # bundled command line tool (runs genoffice.cjs on the app's Electron in node mode)
      ln -s $app/resources/cli/ieumoffice $out/bin/ieumoffice-cli
    '';

    passthru = {
      inherit
        xlsx-sidecar
        rhwpStudio
        hanja
        drawWar
        ;
    };

    meta = {
      description = "Free, open-source AI office suite (Word, Excel, PowerPoint, PDF, HWP, Markdown, ...)";
      homepage = "https://github.com/pblsketch/ieumoffice";
      license = lib.licenses.asl20;
      platforms = [ "x86_64-linux" ];
      mainProgram = "ieumoffice";
    };
  };
in
withUiLanguage uiLanguage unwrapped
