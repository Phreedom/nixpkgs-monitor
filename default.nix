let

  pkgs = import <nixpkgs> {
    config = {
      gems.generated = import ./gems.nix;
    };
  };

  required_gems = with pkgs.rubyLibs; [ mechanize sequel sqlite3 sinatra haml ];
in
with pkgs;
stdenv.mkDerivation {
  name = "nixpkgs-monitor-dev";

  src = ./.;

  buildInputs = [
    rubygems ruby makeWrapper swig2 nix 
    boehmgc # Nix fails to propagate headers. TODO: upstream this
  ];

  requiredUserEnvPkgs = required_gems;
  propagatedBuildInputs = required_gems;


  NIX_CFLAGS_COMPILE="-I${nix}/include/nix";
  NIX_LDFLAGS="-L${nix}/lib/nix";

  installPhase = ''
    addToSearchPath GEM_PATH $out/${ruby.gemPath}

    export gemlibpath=$out/lib/
    ensureDir $gemlibpath
    cp distro-package.rb $gemlibpath
    cp package-updater.rb $gemlibpath
    cp security-advisory.rb $gemlibpath
    echo $gemlibpath

    g++ nix-env-patched.cc -lexpr -lformat -lstore -lutil -lmain -lgc -o nix-env-patched

    ensureDir $out/bin
    cp updatetool.rb $out/bin
    cp nix-env-patched $out/bin
    cp nixpkgs-monitor-site $out/bin

    wrapProgram "$out/bin/updatetool.rb" \
          --prefix GEM_PATH : "$GEM_PATH" \
          --prefix RUBYLIB : "${rubygems}/lib:$gemlibpath" \
          --set RUBYOPT rubygems

    wrapProgram "$out/bin/nixpkgs-monitor-site" \
          --prefix GEM_PATH : "$GEM_PATH" \
          --prefix RUBYLIB : "${rubygems}/lib:$gemlibpath" \
          --set RUBYOPT rubygems

  '';
}
