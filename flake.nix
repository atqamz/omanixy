{
  description = "Nix-native integration layer for the Omarchy Quattro desktop shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    omarchy = {
      url = "github:basecamp/omarchy/8fcc9d6048af4cb0e3af8512c78049857a3b53dd";
      flake = false;
    };
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
