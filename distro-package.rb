require 'nokogiri'

module DistroPackage

  DB = nil

  # Generic distro package
  class Package
    attr_accessor :internal_name, :name, :version, :url, :revision


    def initialize(internal_name, name = internal_name, version = '0', url = "", revision = "" )
      @internal_name = internal_name
      @name = name.downcase
      @version = version
      @url = url
      @revision = ( revision ? revision : "" )
    end


    def serialize
      return {
        :internal_name =>@internal_name,
        :name => @name,
        :version => @version,
        :url => @url,
        :revision => @revision
      }
    end


    def self.deserialize(val)
      new(val[:internal_name], val[:name], val[:version], val[:url], val[:revision])
    end


    def self.table_name
      "packages_#{@cache_name}".to_sym
    end


    def self.list
      unless @list
        @list = {}
        @by_internal_name = {}

        if DB.table_exists?(table_name)
          DB[table_name].each do |record|
            package = deserialize(record)
            @list[package.name] = package
            @by_internal_name[package.internal_name] = package
          end
        else
          STDERR.puts "#{table_name} doesn't exist"
        end
      end

      return @list
    end


    def self.packages
      list.values
    end


    def self.by_internal_name
      unless @by_internal_name
        list
      end
      return @by_internal_name
    end


    def self.create_table(db)
      db.create_table!(table_name) do
        String :internal_name, :unique => true, :primary_key => true
        String :name
        String :version
        String :url
        String :revision
      end
    end


    def self.serialize_list(list)
      DB.transaction do
        create_table(DB)
        list.values.each do |package|
          DB[table_name] << package.serialize
        end
      end
    end


    def self.http_agent
      agent = Mechanize.new
      agent.user_agent = 'NixPkgs software update checker'
      return agent
    end

  end


  class GenericArch < Package

    # FIXME: support multi-output PKGBUILDs
    def self.parse_pkgbuild(entry, path)
      dont_expand = [ 'pidgin' ]
      override = {
        'lzo2'              => 'lzo',
        'grep'          => 'gnugrep',
        'make'         => 'gnumake',
        'gnuplot '      => 'gnuplot',
        'tar'            => 'gnutar',
        'grep'           => 'gnugrep',
        'sed'            => 'gnused',
        'tidyhtml'      => 'html-tidy',
        'apache'        => 'apache-httpd',
        'bzr'           => 'bazaar',
        'libmp4v2'      => 'mp4v2',
        '"gummiboot"'   => 'gummiboot',
        'lm_sensors'    => 'lm-sensors',
      }

      pkgbuild = File.read(path, :encoding => 'ISO-8859-1') 
      pkg_name = (pkgbuild =~ /pkgname=(.*)/ ? $1.strip : nil)
      pkg_ver = (pkgbuild =~ /pkgver=(.*)/ ? $1.strip : nil)

      pkg_name = entry if dont_expand.include? entry
      unless pkg_name and pkg_ver
        puts "skipping #{entry}: no package name or version"
        return nil
      end
      if pkg_name.include? "("
        puts "skipping #{entry}: unsupported multi-package PKGBUILD"
        return nil
      end
      pkg_name = override[pkg_name] if override[pkg_name]

      pkg_name = $1 if pkg_name =~ /xorg-(.*)/
      pkg_name = $1 if pkg_name =~ /kdeedu-(.*)/
      pkg_name = $1 if pkg_name =~ /kdemultimedia-(.*)/
      pkg_name = $1 if pkg_name =~ /kdeutils-(.*)/
      pkg_name = $1 if pkg_name =~ /kdegames-(.*)/
      pkg_name = $1 if pkg_name =~ /kdebindings-(.*)/
      pkg_name = $1 if pkg_name =~ /kdegraphics-(.*)/
      pkg_name = $1 if pkg_name =~ /kdeaccessibility-(.*)/

      pkg_name = "aspell-dict-#{$1}" if pkg_name =~ /aspell-(.*)/
      pkg_name = "haskell-#{$1}-ghc7.6.3" if pkg_name =~ /haskell-(.*)/
      pkg_name = "ktp-#{$1}" if pkg_name =~ /telepathy-kde-(.*)/

      url = %x(bash -c 'source #{path} && echo $source').split("\n").first
      url.strip! if url
      return new(entry, pkg_name, pkg_ver, url)
    end

  end


  class Arch < GenericArch
    @cache_name = "arch"

    def self.generate_list
      arch_list = {}

      puts "Cloning / pulling repos."
      puts %x(git clone git://projects.archlinux.org/svntogit/packages.git)
      puts %x(cd packages && git pull --rebase)
      puts %x(git clone git://projects.archlinux.org/svntogit/community.git)
      puts %x(cd community && git pull --rebase)
      
      puts "Scanning Arch Core, Extra (packages.git) repositories..."
      Dir.entries("packages").each do |entry|
        next if entry == '.' or entry == '..'

        pkgbuild_name = File.join("packages", entry, "repos", "extra-i686", "PKGBUILD")
        pkgbuild_name = File.join("packages", entry, "repos", "core-i686", "PKGBUILD") unless File.exists? pkgbuild_name

        if File.exists? pkgbuild_name
          package = parse_pkgbuild(entry, pkgbuild_name)
          arch_list[package.name] = package if package
        end
      end

      puts "Scanning Arch Community repository..."
      Dir.entries("community").each do |entry|
        next if entry == '.' or entry == '..'

        pkgbuild_name = File.join("community", entry, "repos", "community-i686", "PKGBUILD")

        if File.exists? pkgbuild_name
          package = parse_pkgbuild(entry, pkgbuild_name)
          arch_list[package.name] = package if package
        end
      end

      serialize_list(arch_list)
      return arch_list
    end

  end


  class AUR < GenericArch
    @cache_name = "aur"

    def self.generate_list
      aur_list = {}

      puts "Cloning AUR repos"
      puts %x(curl http://aur3.org/all_pkgbuilds.tar.gz -O)
      puts %x(rm -rf aur/*)
      puts %x(mkdir aur)
      puts %x(tar -xvf all_pkgbuilds.tar.gz  --show-transformed --transform s,/PKGBUILD,, --strip-components=1 -C aur)

      puts "Scanning AUR"
      Dir.entries("aur").each do |entry|
        next if entry == '.' or entry == '..'

        pkgbuild_name = File.join("aur", entry)
        if File.exists? pkgbuild_name
          package = parse_pkgbuild(entry, pkgbuild_name)
          aur_list[package.name] = package if package
        end
      end

      serialize_list(aur_list)
      return aur_list
    end

  end

  class Gentoo < Package
    attr_accessor :version_overlay, :version_upstream
    @cache_name = "gentoo"

    def version
      return version_upstream if version_upstream
      return version_overlay if version_overlay and not(version_overlay.end_with?('9999'))
      return @version
    end


    def self.create_table(db)
      db.create_table!(table_name) do
        String :internal_name, :unique => true, :primary_key => true
        String :name
        String :version
        String :url
        String :version_overlay
        String :version_upstream
        String :revision
      end
    end


    def serialize
      return super.merge({:version_overlay => @version_overlay, :version_upstream => @version_upstream})
    end


    def self.deserialize(val)
      pkg = super(val)
      pkg.version_overlay = val[:version_overlay]
      pkg.version_upstream = val[:version_upstream]
      return pkg
    end


    def self.generate_list
      gentoo_list = {}

      categories_json = http_agent.get('http://euscan.iksaif.net/api/1.0/categories.json').body
      JSON.parse(categories_json)["categories"].each do |cat|
        puts cat["category"]
        packages_json = http_agent.get("http://euscan.iksaif.net/api/1.0/packages/by-category/#{cat["category"]}.json").body
        JSON.parse(packages_json)["packages"].each do |pkg|
          name = pkg["name"]
          gentoo_list[name] = Gentoo.new(cat["category"] + '/' + name, name) unless gentoo_list[name]
          if pkg["last_version_gentoo"]
            gentoo_list[name].version = pkg["last_version_gentoo"]["version"]
          end
          if pkg["last_version_overlay"]
            gentoo_list[name].version_overlay = pkg["last_version_overlay"]["version"]
          end
          if pkg["last_version_upstream"]
            gentoo_list[name].version_upstream = pkg["last_version_upstream"]["version"]
          end
        end
      end

      serialize_list(gentoo_list)
      return gentoo_list
    end


    def self.match_nixpkg(pkg)
      match = list[pkg.name]
      return match if match
      match = list[pkg.name.gsub(/^ruby-/,"")]
      return match if match
      match = list[pkg.name.gsub(/^python-/,"")]
      return match if match
      match = list[pkg.name.gsub(/^perl-/,"")]
      return match if match
      match = list[pkg.name.gsub(/^haskell-(.*)-ghc\d+\.\d+\.\d+$/,'\1')]
      return match if match
      return nil
    end

  end


  # FIXME: nixpkgs often override package versions with suffixes such as -gui
  # which break matching because nixpks keeps only 1 of the packages
  # with the same name
  class Nix < Package
    attr_accessor :homepage, :maintainers
    @cache_name = "nix"

    def version
      result = @version.gsub(/-profiling$/, "").gsub(/-gimp-2.6.\d+-plugin$/,"")
      result.gsub!(/-3\.9\.\d$/,"") if internal_name.include? 'linuxPackages'
      result = result.gsub(/-gui$/,"").gsub(/-single$/,"").gsub(/-with-X$/,"")
      result = result.gsub(/-with-svn$/,"").gsub(/-full$/,"").gsub(/-client$/,"")
      result = result.gsub(/-daemon$/,"").gsub(/-static$/,"").gsub(/-binary$/,"")
      result = result.gsub(/-with-perl$/,"")
      return result
    end

    def maintainer_count
      (maintainers and maintainers != "") ? maintainers.split(";").size : 0
    end

    def serialize
      return super.merge({:homepage => @homepage, :maintainers => @maintainers})
    end


    def self.deserialize(val)
      pkg = super(val)
      pkg.homepage = val[:homepage]
      pkg.maintainers = val[:maintainers]
      return pkg
    end

    def self.create_table(db)
      db.create_table!(table_name) do
        String :internal_name, :unique => true, :primary_key => true
        String :name
        String :version
        String :url
        String :revision
        String :homepage
        String :maintainers
      end
    end

    def self.nixpkgs_get_attr(attr)
      %x(nix-instantiate --eval-only --xml --strict -A #{attr} ./nixpkgs/)
    end

    def self.instantiate(attr, name)
      url = 'none'
      rev = nil
      unless /string value="(?<url>[^"]*)"/ =~ nixpkgs_get_attr("#{attr}.src.urls")
        puts "maybe #{attr} #{name} fetches sources from a VCS?"

        unless /string value="(?<rev>[^"]*)"/ =~ nixpkgs_get_attr("#{attr}.src.rev") and
               /string value="(?<url>[^"]*)"/ =~ nixpkgs_get_attr("#{attr}.src.url")
          puts "failed to find sources for #{attr} #{name}"
        end
      end

      if name =~ /(.*?)-([^A-Za-z].*)/
        result =  Nix.new(attr, $1, $2, url, rev)
      else
        puts "failed to parse name for #{attr} #{name}"
        result = Nix.new(attr, name, "", url, rev)
      end

      return result
    end


    def self.generate_list
      blacklist = []
      nix_list = {}

      puts %x(git clone https://github.com/NixOS/nixpkgs.git)
      puts %x(cd nixpkgs && git pull --rebase)

      pkgs_xml = Nokogiri.XML(%x(nix-env -qa '*' --attr-path --meta --xml --file ./nixpkgs/))
      pkgs_xml.xpath('items/item').each do|entry|
        next if blacklist.include? entry
        attr = entry[:attrPath]
        name = entry[:name]
        if name and attr
          package = Nix.instantiate(attr, name)
          if package
            homepage = entry.xpath('meta[@name="homepage"]').first
            package.homepage = homepage[:value] if homepage
            maintainers = entry.xpath('meta[@name="maintainers"]/string').map{|m| m[:value]}.join(";")
            package.maintainers = maintainers if maintainers
            puts package.serialize.inspect
            nix_list[package.name] = package 
          end
        else
          puts "failed to parse #{entry}"
        end
      end

      serialize_list(nix_list)
      return nix_list
    end

  end


  class Debian < Package
    @cache_name = "debian"

    def version
      result = @version.sub(/^\d:/,"").sub(/-\d$/,"").sub(/\+dfsg.*$/,"")
    end


    def self.generate_list
      deb_list = {}

      puts "Downloading repository metadata"
      %x(curl http://ftp.debian.org/debian/dists/sid/main/source/Sources.bz2 -o debian-main.bz2)
      %x(curl http://ftp.debian.org/debian/dists/sid/contrib/source/Sources.bz2 -o debian-contrib.bz2)
      %x(curl http://ftp.debian.org/debian/dists/sid/non-free/source/Sources.bz2 -o debian-non-free.bz2)
      %x(bzcat debian-main.bz2 debian-contrib.bz2 debian-non-free.bz2 >debian-sources)

      File.read('debian-sources').split("\n\n").each do |pkgmeta|
        pkg_name = $1 if pkgmeta =~ /Package:\s*(.*)/
        pkg_version = $1 if pkgmeta =~ /Version:\s*(.*)/
        if pkg_name and pkg_version
          package = Debian.new(pkg_name, pkg_name, pkg_version, 'none')
          deb_list[package.name] = package if package
        end
      end

      serialize_list(deb_list)
      return deb_list
    end


    def self.match_nixpkg(pkg)
      match = list[pkg.name]
      return match if match
#       match = list[pkg.name.gsub(/^ruby-/,"")]
#       return match if match
      match = list[pkg.name.gsub(/^python-/,"")]
      return match if match
      match = list[pkg.name.gsub(/^perl-(.*)$/,'lib\1-perl')]
      return match if match
      match = list[pkg.name.gsub(/^(haskell-.*)-ghc\d+\.\d+\.\d+$/,'\1')]
      return match if match
      match = list[pkg.name.gsub(/^xf86-(.*)$/,'xserver-xorg-\1')]
      return match if match
      match = list[pkg.name+"1"]
      return match if match
      match = list[pkg.name+"2"]
      return match if match
      match = list[pkg.name+"3"]
      return match if match
      match = list[pkg.name+"4"]
      return match if match
      match = list[pkg.name+"5"]
      return match if match
      match = list[pkg.name+"6"]
      return match if match
      return nil
    end

  end

end