{nix_src ? null}:
let

  pkgs = import <nixpkgs> {
    config = {
      gems.generated = import ./gems.nix;
    };
  };

  required_gems = with pkgs.rubyLibs; [ mechanize sequel sqlite3 sinatra haml ];
  nix_fresh = pkgs.lib.overrideDerivation pkgs.nix (a: {
      src = if nix_src != null then nix_src else
      pkgs.fetchurl {
        url = http://hydra.nixos.org/build/7526615/download/5/nix-1.7pre3306_5ba5993.tar.xz;
        sha256 = "21f0809915f387e4c9e811ed56dab5dc8f8156e26574014a027b94ba8ea5a34e";
      };
      doInstallCheck = false;
      patches = [ ./expose-attrs.patch ];
    });

  updater_runtime_deps = with pkgs; [ ruby19 git patch curl bzip2 gnutar gnugrep coreutils gnused bash ];

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
          ${stdenv.lib.concatMapStrings (x: "--prefix PATH : ${x}/bin ") updater_runtime_deps} \
          --prefix PATH : $out/bin \
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
