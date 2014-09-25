{nix_src ? null}:
let

  pkgs = import <nixpkgs> {
    config = {
      gems.generated = import ./gems.nix;
      gems.patches = { gems, postgresql }: {
        pg = {
          buildInputs = [ postgresql ];
        };
      };
    };
  };

  required_gems = with pkgs.rubyLibs; [ mechanize sequel sqlite3 sinatra haml diffy pg ];
  tame_nix = pkgs.lib.overrideDerivation pkgs.nixUnstable (a: {
      patches = [ ./expose-attrs.patch ./extra-meta.patch ];
    });

  updater_runtime_deps = with pkgs; [ ruby_1_9 git patch curl bzip2 gnutar gnugrep coreutils gnused bash file ];

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
          --prefix PATH : ${tame_nix}/bin \
          --prefix GEM_PATH : "$GEM_PATH" \
          --prefix RUBYLIB : "${rubygems}/lib:$gemlibpath" \
          --set RUBYOPT rubygems

    wrapProgram "$out/bin/nixpkgs-monitor-site" \
          --set PATH "${ruby_1_9}/bin:${diffutils}/bin:${which}/bin" \
          --prefix GEM_PATH : "$GEM_PATH" \
          --prefix RUBYLIB : "${rubygems}/lib:$gemlibpath" \
          --set RUBYOPT rubygems

  '';
}
