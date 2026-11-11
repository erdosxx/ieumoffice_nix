# The rhwp HWP/HWPX engine (WebAssembly) that IeumOffice ships as vendor/rhwp-core,
# rebuilt from source: rhwp 0.9.0 + IeumOffice's patches (vendor/rhwp-core/patches,
# in the order of vendor/rhwp-core/package.json) + our fixes in ./rhwp/patches.
#
# Equivalent of upstream's tools/build-rhwp-core.mjs
# (`wasm-pack build --target web --release`), done as its three steps so nothing
# is downloaded: cargo (wasm32) -> wasm-bindgen --target web -> wasm-opt -O.
{
  lib,
  rustPlatform,
  fetchCrate,
  fetchgit,
  git,
  jq,
  lld,
  binaryen,
  wasm-bindgen-cli_0_2_127,
  # IeumOffice source tree (provides vendor/rhwp-core/{patches,package.json})
  ieumofficeSrc,
  # apply ./rhwp/patches (false = IeumOffice's engine as shipped, for comparisons)
  withFixes ? true,
}:

let
  version = "0.9.0";
  # vendor/rhwp-core/package.json -> rhwp.commit (the v0.9.0 tag)
  rhwpCommit = "c9095c5f67632e6721e800ccc7fb43ea49d26682";

  # The crates.io package is byte-identical to the tag's src/ etc. (verified file
  # by file); only its Cargo.lock is regenerated, see ./rhwp/Cargo.lock.
  crate = fetchCrate {
    pname = "rhwp";
    inherit version;
    hash = "sha256-Dw4Eak6a0ETFp7rv3jHvOVFKM7u+InNXoe7SMjNjT54=";
  };

  # IeumOffice's patch 0044 changes the vendored PDF backend, so take it from the
  # tag instead of crates.io (the repository itself is several GB: sparse fetch).
  pdfBackend = fetchgit {
    url = "https://github.com/edwardkim/rhwp.git";
    rev = rhwpCommit;
    sparseCheckout = [ "/vendor/rhwp-pdf-import-backend/" ];
    nonConeMode = true;
    hash = "sha256-p/Xdutkm/gMI8MLtz6vI1DLWSJH+gUxJOl7uvL+chW4=";
  };
in
rustPlatform.buildRustPackage {
  pname = "rhwp-core-wasm" + lib.optionalString (!withFixes) "-unfixed";
  inherit version;
  src = crate;

  # Same lock as the crate's, except rhwp-pdf-import-backend comes from the
  # vendored path (two lines: its registry source and checksum).
  cargoLock.lockFile = ./rhwp/Cargo.lock;

  nativeBuildInputs = [
    git
    jq
    lld
    binaryen
    wasm-bindgen-cli_0_2_127
  ];

  prePatch = ''
    cp ${./rhwp/Cargo.lock} Cargo.lock
    chmod u+w Cargo.lock

    mkdir -p vendor
    cp -r ${pdfBackend}/vendor/rhwp-pdf-import-backend vendor/
    chmod -R u+w vendor
    # Its sibling vendor crates are published on crates.io with the same locked
    # versions; use those instead of the ../ paths of the monorepo.
    sed -i '/^path = "\.\.\//d' vendor/rhwp-pdf-import-backend/Cargo.toml

    cat >> Cargo.toml <<'EOF'

    [patch.crates-io]
    rhwp-pdf-import-backend = { path = "vendor/rhwp-pdf-import-backend" }
    EOF
  '';

  postPatch = ''
    core=${ieumofficeSrc}/vendor/rhwp-core
    for p in $(jq -r '.rhwp.patches[]' $core/package.json); do
      echo "applying IeumOffice patch $p"
      # test files are not part of the crate
      git apply --exclude='tests/*' "$core/patches/$p"
    done
  ''
  + lib.optionalString withFixes ''
    for p in ${./rhwp/patches}/*.patch; do
      echo "applying $(basename $p)"
      git apply "$p"
    done
  '';

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

  passthru = { inherit crate pdfBackend; };

  meta = {
    description = "rhwp HWP/HWPX engine (WebAssembly) as used by IeumOffice, with fixes";
    homepage = "https://github.com/edwardkim/rhwp";
    license = lib.licenses.mit;
  };
}
