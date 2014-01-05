let

  pkgs = import <nixpkgs> {
    config = {
      gems.generated = import ./gems.nix;
    };
  };

  required_gems = with pkgs.rubyLibs; [ mechanize sequel sqlite3 sinatra haml ];
  nix_fresh = pkgs.lib.overrideDerivation pkgs.nix (a: {
      src = pkgs.fetchurl {
        url = http://hydra.nixos.org/build/6861519/download/5/nix-1.7pre3292_709cbe4.tar.xz;
        sha256 = "1pajn8yrrh3dfkyp4xq1y30hrd6n8dbskd1dq13g4rpqn2kg1440";
      };
      doInstallCheck = false;
      patches = [ ./expose-attrs.patch ];
    });
in
with pkgs;
stdenv.mkDerivation {
  name = "nixpkgs-monitor-dev";

  src = ./.;

  buildInputs = [
    rubygems ruby ruby makeWrapper nix_fresh
    boehmgc # Nix fails to propagate headers. TODO: upstream this
  ];

  requiredUserEnvPkgs = required_gems;
  propagatedBuildInputs = required_gems;


  NIX_CFLAGS_COMPILE="-I${nix_fresh}/include/nix";
  NIX_LDFLAGS="-L${nix_fresh}/lib/nix";

  installPhase = ''
    addToSearchPath GEM_PATH $out/${ruby.gemPath}

    export gemlibpath=$out/lib/
    ensureDir $gemlibpath
    cp distro-package.rb $gemlibpath
    cp package-updater.rb $gemlibpath
    cp security-advisory.rb $gemlibpath

    g++ nix-env-patched.cc -lexpr -lformat -lstore -lutil -lmain -lgc -o nix-env-patched

    ensureDir $out/bin
    cp updatetool.rb $out/bin
    cp nix-env-patched $out/bin
    cp nixpkgs-monitor-site $out/bin

    wrapProgram "$out/bin/updatetool.rb" \
          --prefix PATH : "${ruby19}/bin:${git}/bin:${patch}/bin:${curl}/bin:${bzip2}/bin:${gnutar}/bin/:${gnugrep}/bin/:${coreutils}/bin:$out/bin:${gnused}/bin/" \
          --prefix GEM_PATH : "$GEM_PATH" \
          --prefix RUBYLIB : "${rubygems}/lib:$gemlibpath" \
          --set RUBYOPT rubygems

    wrapProgram "$out/bin/nixpkgs-monitor-site" \
          --set PATH "${ruby19}/bin" \
          --prefix GEM_PATH : "$GEM_PATH" \
          --prefix RUBYLIB : "${rubygems}/lib:$gemlibpath" \
          --set RUBYOPT rubygems

  '';
}
