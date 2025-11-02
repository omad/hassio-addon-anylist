{
  description = "A Nix flake for AnyList";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    let
      systems = flake-utils.lib.defaultSystems;

      overlay = final: prev: {
        anylist = final.buildNpmPackage {
          pname = "anylist";
          version = "1.0.0";
          src = ./anylist;

          npmDepsHash = "sha256-UREIk+5l2hEUp2L/wdyUhBYDrIvLcd95+0aJ745wRL4=";
          dontNpmBuild = true;

          nativeBuildInputs = [ final.makeWrapper ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin $out/libexec/anylist
            cp -r ./. $out/libexec/anylist

            makeWrapper ${final.nodejs}/bin/node $out/bin/anylist-server \
              --add-flags $out/libexec/anylist/index.js
            runHook postInstall
          '';

          meta = with final.lib; {
            description = "Server for interacting with AnyList";
            homepage = "https://github.com/kevdliu/hassio-anylist";
            license = licenses.gpl3Only;
            platforms = platforms.unix;
            mainProgram = "anylist-server";
          };
        };
      };

      forAllSystems = nixpkgs.lib.genAttrs systems;
      anylistModule = import ./nixos/module.nix;
    in
    {
      overlays.default = overlay;

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          anylist = pkgs.anylist;
          default = pkgs.anylist;
        });

      nixosModules = {
        anylist = anylistModule;
        default = anylistModule;
      };
    };
}
