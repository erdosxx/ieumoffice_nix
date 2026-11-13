# The rhwp HWP/HWPX engine (WebAssembly) that IeumOffice ships as vendor/rhwp-core,
# rebuilt from the patched source in ./rhwp/source.nix (shared with rhwp-cli.nix).
#
# Equivalent of upstream's tools/build-rhwp-core.mjs
# (`wasm-pack build --target web --release`), done as its three steps so nothing
# is downloaded: cargo (wasm32) -> wasm-bindgen --target web -> wasm-opt -O.
{
  lib,
  rustPlatform,
  lld,
  binaryen,
  wasm-bindgen-cli_0_2_127,
  # patched rhwp source (./rhwp/source.nix)
  rhwpSrc,
}:

rustPlatform.buildRustPackage {
  pname = "rhwp-core-wasm" + lib.optionalString (!rhwpSrc.withFixes) "-unfixed";
  inherit (rhwpSrc) version;
  src = rhwpSrc;

  cargoLock.lockFile = ./rhwp/Cargo.lock;

  nativeBuildInputs = [
    lld
    binaryen
    wasm-bindgen-cli_0_2_127
  ];

  buildPhase = ''
    runHook preBuild
    cargo build --offline --locked --release --lib \
      --target wasm32-unknown-unknown -j $NIX_BUILD_CORES
    wasm-bindgen --target web --typescript --out-dir pkg --out-name rhwp \
      target/wasm32-unknown-unknown/release/rhwp.wasm
    wasm-opt -O pkg/rhwp_bg.wasm -o pkg/rhwp_bg.wasm
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp pkg/rhwp.js pkg/rhwp.d.ts pkg/rhwp_bg.wasm pkg/rhwp_bg.wasm.d.ts $out/
    runHook postInstall
  '';

  doCheck = false;

  passthru = { inherit rhwpSrc; };

  meta = {
    description = "rhwp HWP/HWPX engine (WebAssembly) as used by IeumOffice, with fixes";
    homepage = "https://github.com/edwardkim/rhwp";
    license = lib.licenses.mit;
  };
}
