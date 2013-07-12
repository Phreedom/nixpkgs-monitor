let
  pkgs = import <nixpkgs> {};

in
with pkgs;
stdenv.mkDerivation {
  name = "nixpkgs-monitor-dev";

  src = ./.;

  buildInputs = [ rubygems ruby makeWrapper ];

  requiredUserEnvPkgs = [ rubyLibs.mechanize ];
  propagatedBuildInputs = [ rubyLibs.mechanize ];

  installPhase = ''

    addToSearchPath GEM_PATH $out/${ruby.gemPath}
echo $GEM_PATH

    export gemlibpath=$out/lib/
    ensureDir $gemlibpath
    cp distro-package.rb $gemlibpath
    cp package-updater.rb $gemlibpath
    echo $gemlibpath

    ensureDir $out/bin
    cp updatetool.rb $out/bin

    wrapProgram "$out/bin/updatetool.rb" \
          --prefix GEM_PATH : "$GEM_PATH" \
          --prefix RUBYLIB : "${rubygems}/lib:$gemlibpath" \
          --set RUBYOPT rubygems
  '';
}