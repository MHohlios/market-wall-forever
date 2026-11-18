{
  description = "MarketWall dev shell: Lua 5.1 (the game's version), busted and luacheck";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lua = pkgs.lua5_1.withPackages (ps: [ ps.busted ps.luacheck ]);
      in {
        devShells.default = pkgs.mkShellNoCC {
          name = "market-wall";
          packages = [ lua pkgs.gnumake ];
        };
      });
}
