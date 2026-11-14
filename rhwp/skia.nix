# Skia sources for skia-bindings, so the native-skia feature of rhwp-cli builds
# Skia from source offline instead of downloading rust-skia's prebuilt binaries.
# Same scheme as nixpkgs' neovide.
#
# When bumping skia-safe/skia-bindings (./Cargo.lock): set `tag` to
# skia-bindings' Cargo.toml [package.metadata] skia, and regenerate
# ./skia-externals.json from skia/DEPS (or take nixpkgs' neovide copy if it
# pins the same tag).
{
  lib,
  fetchFromGitHub,
  fetchgit,
  linkFarm,
  runCommand,
}:

let
  # skia-bindings 0.156.0: [package.metadata] skia = "m156.5"
  tag = "m156.5";
  repo = fetchFromGitHub {
    owner = "rust-skia";
    repo = "skia";
    inherit tag;
    hash = "sha256-ahqSduR4sCkcEmoo++PpxfcH0SZH4o6k/n8ZZmB1aA0=";
  };
  # third-party sources from skia/DEPS
  externals = linkFarm "skia-externals" (
    lib.mapAttrsToList (name: value: {
      inherit name;
      path = fetchgit value;
    }) (lib.importJSON ./skia-externals.json)
  );
in
runCommand "skia-source-${tag}" { passthru = { inherit tag repo externals; }; } ''
  cp -R ${repo} $out
  chmod -R +w $out
  ln -s ${externals} $out/third_party/externals
''
