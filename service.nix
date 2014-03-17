{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.services.nixpkgs-monitor;

  env_db = optionalAttrs (cfg.database != null) { DB = cfg.database; };

  npmon = import ./default.nix {};

in

{
  ###### interface

  options = {

    services.nixpkgs-monitor = rec {

      enable = mkOption {
        default = false;
        description = ''
          Whether to run Nixpkgs-monitor services.
        '';
      };

      baseDir = mkOption {
        default = "/var/lib/nixpkgs-monitor";
        description = ''
          The directory holding configuration, logs and temporary files.
        '';
      };

      user = mkOption {
        default = "nixpkgsmon";
        description = ''
          The user the Nixpkgs-monitor services should run as.
        '';
      };

      host = mkOption {
        default = "localhost";
        description = ''
          The IP address to listen at.
        '';
      };

      port = mkOption {
        default = 4567;
        description = ''
          The IP address to listen at.
        '';
      };

      baseUrl = mkOption {
        default = null;
        description = ''
          Base URL at which the monitor should run.
        '';
      };

      database = mkOption {
        default = null;
        example = "postgres://db_user:db_password@host/db_name";
        description = ''
          Use the specified database instead of the default(sqlite) one.
        '';
      };

      builderCount = mkOption {
        default = 1;
        description = ''
          The number of builds  to run in parallel
        '';
      };

    };

  };


  ###### implementation

  config = mkIf cfg.enable {

    users.extraUsers = singleton {
      name = cfg.user;
      description = "Nixpkgs-monitor";
      home = cfg.baseDir;
      createHome = true;
      useDefaultShell = true;
    };

    systemd.services."nixpkgs-monitor-site" = {
      wantedBy = [ "multi-user.target" ];

      environment =
        env_db //
        optionalAttrs (cfg.baseUrl != null) { BASE_URL = cfg.baseUrl; };

      serviceConfig = {
        ExecStart = "${npmon}/bin/nixpkgs-monitor-site -p ${toString cfg.port} -o ${cfg.host}";
        User = cfg.user;
        Restart = "always";
        WorkingDirectory = cfg.baseDir;
      };
    };

    systemd.services."nixpkgs-monitor-updater" = {
      path = [ pkgs.nix ];
      environment = {
        NIX_REMOTE = "daemon";
        NIX_CONF_DIR = "/etc/nix";
        OPENSSL_X509_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
        GIT_SSL_CAINFO = "/etc/ssl/certs/ca-bundle.crt";
        CURL_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
        NIX_PATH = "/nix/var/nix/profiles/per-user/root/channels/nixos"; # to be able to prefetch mirror:// urls
      } // env_db;

      script = ''
        ${npmon}/bin/updatetool.rb --all
        ${pkgs.curl}/bin/curl ${cfg.host}:${toString cfg.port}/refresh
        ${npmon}/bin/updatetool.rb --build --builder-count ${toString cfg.builderCount}
      '';

      serviceConfig = {
        User = cfg.user;
        WorkingDirectory = cfg.baseDir;
      };
    };

    systemd.services."nixpkgs-monitor-updater-drop-negative-cache" = {
      environment = env_db;
      serviceConfig = {
        ExecStart = "${npmon}/bin/updatetool.rb --redownload --rebuild";
        User = cfg.user;
        WorkingDirectory = cfg.baseDir;
      };
    };

  };
}
