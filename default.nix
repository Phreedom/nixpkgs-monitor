{ pkgs ? (import <nixpkgs> {}), stdenv ? pkgs.stdenv }:

let
  updater_runtime_deps = with pkgs; [ ruby_1_9 git patch curl bzip2 gnutar gnugrep coreutils gnused bash file ];

in stdenv.mkDerivation rec {
  name = "nixpkgs-monitor-dev";

  src = ./.;

  env = pkgs.bundlerEnv {
    name = "nixpkgs-monitor-dev";
    ruby = pkgs.ruby_1_9;
    gemfile = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset = ./gemset.nix;
  };

  buildInputs = [ pkgs.makeWrapper env.ruby pkgs.bundler ];

  installPhase = ''
    addToSearchPath GEM_PATH $out/${env.ruby.gemPath}
    export gemlibpath=$out/lib/
    mkdir -p $gemlibpath
    cp distro-package.rb $gemlibpath
    cp package-updater.rb $gemlibpath
    cp security-advisory.rb $gemlibpath
    cp reports.rb $gemlibpath
    cp build-log.rb $gemlibpath
    cp -r migrations $gemlibpath
    mkdir -p $out/bin
    cp updatetool.rb $out/bin
    cp nixpkgs-monitor-site $out/bin
    wrapProgram "$out/bin/updatetool.rb" \
        ${stdenv.lib.concatMapStrings (x: "--prefix PATH : ${x}/bin ") updater_runtime_deps} \
          --prefix PATH : "${env.ruby}/bin" \
          --prefix GEM_PATH : "${env}/${env.ruby.gemPath}" \
          --prefix RUBYLIB : "${env}/${env.ruby.gemPath}:$out/lib"  \
          --set RUBYOPT rubygems

    wrapProgram "$out/bin/nixpkgs-monitor-site" \
          --set PATH "${env.ruby}/bin:${pkgs.diffutils}/bin:${pkgs.which}/bin" \
          --prefix GEM_PATH : "${env}/${env.ruby.gemPath}" \
          --prefix RUBYLIB : "${env}/${env.ruby.gemPath}:$out/lib"  \
          --set RUBYOPT rubygems

  '';
}
