{
  description = "A Nix flake for Anylist";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib stdenv nodejs npm;

        # Anylist package
        anylist-pkg = pkgs.buildNpmPackage {
          pname = "anylist";
          version = "1.0.0"; # Version from package.json

          src = ./anylist;

          # IMPORTANT: This is a placeholder hash.
          # You must obtain the correct hash by attempting to build this package
          # and replacing this value with the hash Nix provides.
          # Example: nix build .#anylist
          # Nix will fail and output something like:
          # error: hash mismatch in fixed-output derivation '/nix/store/...-node-modules-anylist-1.0.0.drv':
          #          specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
          #             got:    sha256-...........................................
          # Replace the placeholder with the "got" hash.
          npmDepsHash = "sha256-UREIk+5l2hEUp2L/wdyUhBYDrIvLcd95+0aJ745wRL4=";

          # The original error indicates "npm error Missing script: "build"".
          # Since the package.json only has a "start" script and no "build" script,
          # we instruct buildNpmPackage not to run the build phase.
          dontNpmBuild = true;

          # Remove git from buildInputs, buildNpmPackage should handle it if needed.
          # nativeBuildInputs = [ pkgs.git ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin $out/libexec/anylist
            cp -r ./* $out/libexec/anylist/
            # Ensure node_modules is copied if it's built locally by buildNpmPackage
            # This is usually the case if npmDepsHash is correct.
            if [ -d "node_modules" ]; then
              cp -r node_modules $out/libexec/anylist/
            fi

            # Create a wrapper script
            makeWrapper ${nodejs}/bin/node $out/bin/anylist-server \
              --add-flags $out/libexec/anylist/index.js
            runHook postInstall
          '';

          meta = with lib; {
            description = "Server for interacting with AnyList";
            homepage = "https://github.com/kevdliu/hassio-anylist"; # Original project
            license = licenses.gpl3Only; # License updated from LICENSE file
            maintainers = with maintainers; [ ]; # Add your handle if you want
          };
        };
      in
      {
        packages.default = anylist-pkg;
        packages.anylist = anylist-pkg;

        nixosModules.default = {config, ...}: {
          options = {
            services.anylist = {
              enable = lib.mkEnableOption "Enable the Anylist service";

              port = lib.mkOption {
                type = lib.types.port;
                default = 8080;
                description = "Port for the Anylist server to listen on.";
              };

              email = lib.mkOption {
                type = lib.types.str;
                description = "Email address for AnyList login.";
                example = "user@example.com";
              };

              passwordFile = lib.mkOption {
                type = lib.types.path;
                description = ''
                  Path to a file containing the AnyList password.
                  Note: Ensure this file is protected and not world-readable.
                '';
                example = "/run/secrets/anylist-password";
              };

              credentialsFileDir = lib.mkOption {
                type = lib.types.path;
                default = "/var/lib/anylist";
                description = ''
                  Directory where the credentials file (e.g., .anylist-credentials.json) will be stored.
                  The service will have write access to this directory.
                '';
              };

              ipFilter = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "IP filter string (e.g., '192.168.1.').";
                example = "192.168.0.0/24";
              };

              defaultList = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Default AnyList list name.";
                example = "Groceries";
              };

              user = lib.mkOption {
                type = lib.types.str;
                default = "anylist";
                description = "User to run the Anylist service as.";
              };

              group = lib.mkOption {
                type = lib.types.str;
                default = "anylist";
                description = "Group to run the Anylist service as.";
              };
            };
          };

          config = lib.mkIf config.services.anylist.enable {
            users.users.${config.services.anylist.user} = {
              isSystemUser = true;
              group = config.services.anylist.group;
              home = config.services.anylist.credentialsFileDir; # Home dir for credentials
            };
            users.groups.${config.services.anylist.group} = {};

            systemd.services.anylist = {
              description = "Anylist Service";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                User = config.services.anylist.user;
                Group = config.services.anylist.group;
                Restart = "always";
                WorkingDirectory = config.services.anylist.credentialsFileDir;
                ExecStart = ''
                  ${anylist-pkg}/bin/anylist-server \
                    --port ${toString config.services.anylist.port} \
                    --email "${config.services.anylist.email}" \
                    --password "$(<${config.services.anylist.passwordFile})" \
                    ${lib.optionalString (config.services.anylist.ipFilter != null) "--ip-filter \"${config.services.anylist.ipFilter}\""} \
                    ${lib.optionalString (config.services.anylist.defaultList != null) "--default-list \"${config.services.anylist.defaultList}\""} \
                    --credentials-file "${config.services.anylist.credentialsFileDir}/.anylist-credentials.json"
                '';
                # Ensure the credentials directory exists and has correct permissions
                StateDirectory = "anylist"; # This will create /var/lib/anylist
                StateDirectoryMode = "0700";
              };

              # Make password file available to the service
              LoadCredential = [
                "anylist-password:${config.services.anylist.passwordFile}"
              ];
            };
          };
        };
      }
    );
}
