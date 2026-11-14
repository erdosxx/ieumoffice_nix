# rhwp command line tools (rhwp, rhwp-q, rhwp-agent), built natively from the
# same patched source as IeumOffice's engine (./rhwp/source.nix, shared with
# rhwp-core.nix), so the CLI parses/renders documents exactly like the editor.
#
# Built like upstream's `cargo build --release --features native-skia`: the Skia
# renderer (raster/PDF/sixel/kitty outputs) is compiled from source
# (./rhwp/skia.nix) because the sandbox cannot download rust-skia's binaries.
{
  lib,
  rustPlatform,
  clangStdenv,
  callPackage,
  gn,
  ninja,
  python3,
  pkg-config,
  fontconfig,
  freetype,
  removeReferencesTo,
  # patched rhwp source (./rhwp/source.nix)
  rhwpSrc,
  # cargo feature native-skia (false = default features only, no Skia)
  withSkia ? true,
}:

let
  skiaSource = callPackage ./rhwp/skia.nix { };
in
# skia is built with clang (as rust-skia expects)
rustPlatform.buildRustPackage.override { stdenv = clangStdenv; } {
  pname =
    "rhwp-cli"
    + lib.optionalString (!rhwpSrc.withFixes) "-unfixed"
    + lib.optionalString (!withSkia) "-noskia";
  inherit (rhwpSrc) version;
  src = rhwpSrc;

  cargoLock.lockFile = ./rhwp/Cargo.lock;

  # default features (wasm-api is required by the `rhwp` binary);
  # font-metric-gen (dev-tools) is a developer tool and is not built.
  buildFeatures = lib.optional withSkia "native-skia";
  cargoBuildFlags = [
    "--bin=rhwp"
    "--bin=rhwp-q"
    "--bin=rhwp-agent"
  ];

  env = lib.optionalAttrs withSkia {
    SKIA_SOURCE_DIR = skiaSource;
    SKIA_GN_COMMAND = "${gn}/bin/gn";
    SKIA_NINJA_COMMAND = "${ninja}/bin/ninja";
  };

  nativeBuildInputs = lib.optionals withSkia [
    python3 # skia's build scripts
    pkg-config
    removeReferencesTo
  ];

  buildInputs = lib.optionals withSkia [
    fontconfig
    freetype
    rustPlatform.bindgenHook
  ];

  # skia embeds the path to its sources
  postFixup = lib.optionalString withSkia ''
    remove-references-to -t ${skiaSource} $out/bin/*
  '';
  disallowedReferences = lib.optional withSkia skiaSource;

  doCheck = false;

  passthru = {
    inherit rhwpSrc;
  }
  // lib.optionalAttrs withSkia { inherit skiaSource; };

  meta = {
    description = "rhwp HWP/HWPX command line tools, from the engine source used by IeumOffice";
    homepage = "https://github.com/edwardkim/rhwp";
    license = lib.licenses.mit;
    mainProgram = "rhwp";
    platforms = lib.platforms.linux;
  };
}
