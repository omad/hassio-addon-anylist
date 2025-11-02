{ config, lib, pkgs, ... }:

let
  cfg = config.services.anylist;

  stateDirPath = "/var/lib/${cfg.stateDirectory}";

  credentialsFile =
    if cfg.credentialsFile != null then
      cfg.credentialsFile
    else
      "${stateDirPath}/.anylist-credentials.json";

  exportEnv = name: value: "export ${name}=${lib.escapeShellArg value}";

  extraEnv =
    if cfg.extraEnvironment == { } then
      ""
    else
      lib.concatMapStringsSep "\n"
        (name: exportEnv name (builtins.getAttr name cfg.extraEnvironment))
        (lib.attrNames cfg.extraEnvironment) + "\n";
in
{
  options.services.anylist = {
    enable = lib.mkEnableOption "the AnyList HTTP bridge service";

    package = lib.mkOption {
      type = lib.types.package;
      default = lib.attrByPath [ "anylist" ] (throw "services.anylist.package: set an explicit package or add the anylist overlay to pkgs.") pkgs;
      defaultText = lib.literalExpression "pkgs.anylist";
      description = "Package that provides the AnyList service executable.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port to bind for the AnyList service.";
    };

    email = lib.mkOption {
      type = lib.types.str;
      description = "Account email used to authenticate with AnyList.";
      example = "user@example.com";
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      description = ''
        Path to a file containing the AnyList account password.
        The file must be readable by the service at start-up.
      '';
      example = "/run/secrets/anylist-password";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "anylist";
      description = ''
        Name of the state directory that systemd should manage for the service.
        The directory will be created at `/var/lib/<name>` with strict permissions.
      '';
      example = "anylist";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional override for where the AnyList credentials cache should be written.
        Defaults to a `.anylist-credentials.json` file inside the state directory.
      '';
      example = "/var/lib/anylist/credentials.json";
    };

    ipFilter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Restrict requests to clients whose remote address begins with this value.";
      example = "192.168.1.";
    };

    defaultList = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default AnyList list name to target when a request omits one.";
      example = "Groceries";
    };

    dynamicUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the service with a dynamically allocated systemd user.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "anylist";
      description = "Static user account to run the service under when dynamicUser is false.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "anylist";
      description = "Static group to run the service under when dynamicUser is false.";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables to export before launching the service.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra command-line arguments appended to the AnyList executable.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.dynamicUser || cfg.user != "" && cfg.group != "";
      message = "services.anylist: user and group must be non-empty when dynamicUser is false.";
    }];

    users.users = lib.mkIf (!cfg.dynamicUser) {
      "${cfg.user}" = {
        isSystemUser = true;
        group = cfg.group;
        home = stateDirPath;
      };
    };

    users.groups = lib.mkIf (!cfg.dynamicUser) { "${cfg.group}" = { }; };

    systemd.services.anylist = {
      description = "AnyList HTTP bridge service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.coreutils ];

      script = ''
        set -euo pipefail
        umask 077

        export PORT=${toString cfg.port}
        export EMAIL=${lib.escapeShellArg cfg.email}
        export PASSWORD="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.passwordFile})"
        export CREDENTIALS_FILE=${lib.escapeShellArg credentialsFile}
        ${lib.optionalString (cfg.ipFilter != null) "export IP_FILTER=${lib.escapeShellArg cfg.ipFilter}\n"}
        ${lib.optionalString (cfg.defaultList != null) "export DEFAULT_LIST=${lib.escapeShellArg cfg.defaultList}\n"}
        ${extraEnv}

        exec ${cfg.package}/bin/anylist-server${lib.optionalString (cfg.extraArgs != [ ]) " \\\n          ${lib.concatMapStringsSep \" \\\n          \" lib.escapeShellArg cfg.extraArgs}"}
      '';

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = stateDirPath;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        DynamicUser = cfg.dynamicUser;
      } // lib.optionalAttrs (!cfg.dynamicUser) {
        User = cfg.user;
        Group = cfg.group;
      };
    };
  };
}
