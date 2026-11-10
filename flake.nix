{
  description = "IeumOffice (이음오피스) packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;
    in
    {
      packages.${system} = {
        # built from source (npm workspaces + Rust sidecar + nixpkgs Electron)
        ieumoffice = pkgs.callPackage ./package-source.nix { };
        # upstream release .deb, patched with autoPatchelfHook (no compilation)
        ieumoffice-bin = pkgs.callPackage ./package-bin.nix { };
        default = self.packages.${system}.ieumoffice;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = lib.getExe self.packages.${system}.default;
        };
        cli = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/ieumoffice-cli";
        };
      };

      overlays.default = final: prev: {
        ieumoffice = final.callPackage ./package-source.nix { };
        ieumoffice-bin = final.callPackage ./package-bin.nix { };
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
