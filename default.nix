{ pkgs ? (import <nixpkgs> {}), stdenv ? pkgs.stdenv }:

let
  updater_runtime_deps = with pkgs; [ ruby_1_9 git patch curl bzip2 gzip gnutar gnugrep coreutils gnused bash file ];
  tame_nix = pkgs.lib.overrideDerivation pkgs.nixUnstable (a: {
    patches = [ ./expose-attrs.patch ./extra-meta.patch ];
  });

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
    mkdir -p $out
    cp -r lib $out
    cp -r bin $out

    wrapProgram "$out/bin/updatetool.rb" \
        ${stdenv.lib.concatMapStrings (x: "--prefix PATH : ${x}/bin ") updater_runtime_deps} \
          --prefix PATH : "${env.ruby}/bin:${tame_nix}/bin" \
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
