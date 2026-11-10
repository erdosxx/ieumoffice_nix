{
  description = "IeumOffice (이음오피스) packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        ieumoffice-bin = pkgs.callPackage ./package-bin.nix { };
        default = self.packages.${system}.ieumoffice-bin;
      };

      apps.${system}.default = {
        type = "app";
        program = nixpkgs.lib.getExe self.packages.${system}.default;
      };

      overlays.default = final: prev: {
        ieumoffice-bin = final.callPackage ./package-bin.nix { };
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
