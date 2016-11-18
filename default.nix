{ pkgs ? (import <nixpkgs> {}), stdenv ? pkgs.stdenv }:

let
  monitor_runtime_deps = with pkgs; [
    ruby_1_9 git patch curl bzip2 gzip gnutar gnugrep coreutils gnused bash file
  ];
  tame_nix = pkgs.lib.overrideDerivation pkgs.nixUnstable (a: {
    patches = [ ./build/expose-attrs.patch ./build/extra-meta.patch ];
  });

in stdenv.mkDerivation rec {
  name = "nixpkgs-monitor-dev";

  src = ./.;

  env = pkgs.bundlerEnv {
    name = "nixpkgs-monitor-dev";
    ruby = pkgs.ruby_1_9;
    gemfile = ./build/Gemfile;
    lockfile = ./build/Gemfile.lock;
    gemset = ./build/gemset.nix;
  };

  buildInputs = [ pkgs.makeWrapper env.ruby pkgs.bundler ];

  doCheck = true;
  checkPhase = "RUBYLIB=lib:${env}/${env.ruby.gemPath} GEM_PATH=${env}/${env.ruby.gemPath} ${env.ruby}/bin/ruby test/all.rb";

  installPhase = ''
    mkdir -p $out
    cp -r lib $out
    cp -r bin $out

    wrapProgram "$out/bin/nixpkgs-monitor" \
        ${stdenv.lib.concatMapStrings (x: "--prefix PATH : ${x}/bin ") monitor_runtime_deps} \
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
