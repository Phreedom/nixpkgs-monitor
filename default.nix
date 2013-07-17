let

  pkgs = import <nixpkgs> {
    config = {
      gems.generated = import ./gems.nix;
    };
  };

  required_gems = with pkgs.rubyLibs; [ mechanize sequel sqlite3 ];
in
with pkgs;
stdenv.mkDerivation {
  name = "nixpkgs-monitor-dev";

  src = ./.;

  buildInputs = [ rubygems ruby makeWrapper ];


  requiredUserEnvPkgs = required_gems;
  propagatedBuildInputs = required_gems;

  installPhase = ''
    addToSearchPath GEM_PATH $out/${ruby.gemPath}

    export gemlibpath=$out/lib/
    ensureDir $gemlibpath
    cp distro-package.rb $gemlibpath
    cp package-updater.rb $gemlibpath
    cp security-advisory.rb $gemlibpath
    echo $gemlibpath

    ensureDir $out/bin
    cp updatetool.rb $out/bin

    wrapProgram "$out/bin/updatetool.rb" \
          --prefix GEM_PATH : "$GEM_PATH" \
          --prefix RUBYLIB : "${rubygems}/lib:$gemlibpath" \
          --set RUBYOPT rubygems
  '';
}