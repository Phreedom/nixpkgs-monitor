{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.services.nixpkgs-monitor;

  npmon = import ./default.nix;

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
      };

      script = ''
        ${npmon}/bin/updatetool.rb --all
        ${pkgs.curl}/bin/curl ${cfg.host}:${toString cfg.port}/refresh
        ${npmon}/bin/updatetool.rb --build
      '';

      serviceConfig = {
        User = cfg.user;
        WorkingDirectory = cfg.baseDir;
      };
    };

  };
}
