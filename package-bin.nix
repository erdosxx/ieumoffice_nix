# IeumOffice from the upstream release .deb (prebuilt Electron app),
# patched with autoPatchelfHook — same approach as viber / hancom_hangul_nix.
{
  lib,
  symlinkJoin,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeShellWrapper,
  wrapGAppsHook3,
  asar,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libsecret,
  libuuid,
  libva,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  wayland,
  xdg-utils,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxcb,
  libxtst,
  libxscrnsaver,
  libxshmfence,
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

  # libraries Electron/Chromium dlopen at run time (not in DT_NEEDED)
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

  unwrapped = stdenv.mkDerivation {
    pname = "ieumoffice";
    inherit version;

    src = fetchurl {
      url = "https://github.com/pblsketch/ieumoffice/releases/download/v${version}/ieumoffice_${version}_amd64.deb";
      hash = "sha256-2NeWepFpimqKCy6QxTkxgw/BYINXtfaRwBkY6UfJUP8=";
    };

    nativeBuildInputs = [
      dpkg
      autoPatchelfHook
      makeShellWrapper
      wrapGAppsHook3
      asar
    ];

    buildInputs = [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      glib
      gtk3
      libdrm
      libgbm
      libuuid
      nspr
      nss
      pango
      stdenv.cc.cc.lib
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxcb
      libxtst
      libxscrnsaver
      libxshmfence
    ]
    ++ runtimeLibs;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x $src .
      runHook postUnpack
    '';

    dontConfigure = true;
    dontBuild = true;
    dontWrapGApps = true; # wrapped manually below together with the Electron flags

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/opt
      cp -r opt/IeumOffice $out/opt/IeumOffice
      cp -r usr/share $out/share

      app=$out/opt/IeumOffice
      # The nix store is nosuid, so the setuid sandbox helper cannot work;
      # without it Chromium uses the user-namespace sandbox instead.
      rm -f $app/chrome-sandbox
      # Not a deb install anymore (the in-app updater is AppImage-only on Linux anyway).
      rm -f $app/resources/package-type $app/resources/app-update.yml $app/resources/apparmor-profile

      # On every launch the app symlinks its CLI launcher into /usr/local/bin or
      # ~/.local/bin. From the nix store that link would pin a store path and
      # shadow bin/ieumoffice, so skip it there (bin/ieumoffice-cli provides the CLI).
      asar extract $app/resources/app.asar asar-src
      substituteInPlace asar-src/out/main/index.js \
        --replace-fail 'const outcome = installCliLink({ launcher });' \
          'const outcome = process.resourcesPath.startsWith("/nix/store/") ? { status: "skipped (nix store)" } : installCliLink({ launcher });'
      rm $app/resources/app.asar
      asar pack asar-src $app/resources/app.asar
      rm -rf asar-src

      # Same fix as the deb postinst: let MIME types use the generic icons.
      sed -i '/<icon name="x-office-document"/d' $out/share/mime/packages/ieumoffice.xml

      substituteInPlace $out/share/applications/ieumoffice.desktop \
        --replace-fail "Exec=/opt/IeumOffice/ieumoffice" "Exec=$out/bin/ieumoffice"

      # "New document" templates (the deb copies them to /usr/share/templates)
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
      wrapProgramShell $app/ieumoffice \
        --run 'ulimit -Sn "$(ulimit -Hn)" 2>/dev/null || true' \
        "''${gappsWrapperArgs[@]}" \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs} \
        --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

      ln -s $app/ieumoffice $out/bin/ieumoffice
      # bundled command line tool (runs genoffice.cjs on the app's Electron in node mode)
      ln -s $app/resources/cli/ieumoffice $out/bin/ieumoffice-cli
    '';

    meta = {
      description = "Free, open-source AI office suite (Word, Excel, PowerPoint, PDF, HWP, Markdown, ...)";
      homepage = "https://github.com/pblsketch/ieumoffice";
      license = lib.licenses.asl20;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "ieumoffice";
    };
  };
in
withUiLanguage uiLanguage unwrapped
