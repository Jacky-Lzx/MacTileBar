{
  description = "MacTileBar for macOS 26 and later";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/319e4cebef10cbb636c6ea392137b52ad105336a";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
    in
    {
      packages.aarch64-darwin = rec {
        mactilebar = pkgs.callPackage ./nix/package.nix { };
        default = mactilebar;
      };
    };
}
