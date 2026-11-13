# rhwp command line tools (rhwp, rhwp-q, rhwp-agent), built natively from the
# same patched source as IeumOffice's engine (./rhwp/source.nix, shared with
# rhwp-core.nix), so the CLI parses/renders documents exactly like the editor.
{
  lib,
  rustPlatform,
  # patched rhwp source (./rhwp/source.nix)
  rhwpSrc,
}:

rustPlatform.buildRustPackage {
  pname = "rhwp-cli" + lib.optionalString (!rhwpSrc.withFixes) "-unfixed";
  inherit (rhwpSrc) version;
  src = rhwpSrc;

  cargoLock.lockFile = ./rhwp/Cargo.lock;

  # default features (wasm-api is required by the `rhwp` binary);
  # font-metric-gen (dev-tools) is a developer tool and is not built.
  cargoBuildFlags = [
    "--bin=rhwp"
    "--bin=rhwp-q"
    "--bin=rhwp-agent"
  ];

  doCheck = false;

  passthru = { inherit rhwpSrc; };

  meta = {
    description = "rhwp HWP/HWPX command line tools, from the engine source used by IeumOffice";
    homepage = "https://github.com/edwardkim/rhwp";
    license = lib.licenses.mit;
    mainProgram = "rhwp";
    platforms = lib.platforms.linux;
  };
}
