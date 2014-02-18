require 'nokogiri'

module DistroPackage

  # Generic distro package
  class Package
    attr_accessor :internal_name, :name, :version, :url, :revision


    def initialize(internal_name, name = internal_name, version = '0', url = nil, revision = nil )
      @internal_name = internal_name
      @name = name
      @version = version
      @url = url
      @revision = revision
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


    def self.load_from_db(db)
      if DB.table_exists?(table_name)
        DB[table_name].each do |record|
          package = deserialize(record)
          @packages << package
          @list[package.name.downcase] = package
          @by_internal_name[package.internal_name] = package
        end
      else
        STDERR.puts "#{table_name} doesn't exist"
      end
    end


    def self.list
      unless @list
        @list = {}
        @by_internal_name = {}
        @packages = []

        load_from_db(DB)
      end

      return @list
    end


    def self.refresh
      @list = nil
      @by_internal_name = nil
      @packages = nil
    end


    def self.packages
      list unless @packages
      @packages
    end


    def self.by_internal_name
      list unless @by_internal_name
      @by_internal_name
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


    def self.serialize_to_db(db, list)
      list.each do |package|
        db[table_name] << package.serialize
      end
    end


    def self.serialize_list(list)
      DB.transaction do
        create_table(DB)
        serialize_to_db(DB, list)
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

      serialize_list(arch_list.values)
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

      serialize_list(aur_list.values)
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
          if pkg["last_version_gentoo"] and not(pkg["last_version_gentoo"]["version"].include? '9999')
            gentoo_list[name].version = pkg["last_version_gentoo"]["version"]
          end
          if pkg["last_version_overlay"] and not(pkg["last_version_overlay"]["version"].include? '9999')
            gentoo_list[name].version_overlay = pkg["last_version_overlay"]["version"]
          end
          if pkg["last_version_upstream"]
            gentoo_list[name].version_upstream = pkg["last_version_upstream"]["version"]
          end
        end
      end

      serialize_list(gentoo_list.values)
    end


    def self.match_nixpkg(pkg)
      pkgname = pkg.name.downcase
      match = list[pkgname]
      return match if match
      match = list[pkgname.gsub(/^ruby-/,"")]
      return match if match
      match = list[pkgname.gsub(/^python-/,"")]
      return match if match
      match = list[pkgname.gsub(/^perl-/,"")]
      return match if match
      match = list[pkgname.gsub(/^haskell-(.*)-ghc\d+\.\d+\.\d+$/,'\1')]
      return match if match
      return nil
    end

  end


  # FIXME: nixpkgs often override package versions with suffixes such as -gui
  # which break matching because nixpks keeps only 1 of the packages
  # with the same name
  class Nix < Package
    attr_accessor :homepage, :repository_git, :branch, :sha256, :maintainers, :position, :outpath, :drvpath
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


    def serialize
      return super.merge({ :homepage => @homepage,
                           :repository_git => @repository_git,
                           :branch => @branch,
                           :sha256 => @sha256,
                           :position => @position })
    end

    def instantiate
      d_path = %x(nix-instantiate -A '#{internal_name}' ./nixpkgs/).strip
      raise "Failed to instantiate #{internal_name} #{drvpath}: [#{d_path}]" unless $? == 0 and d_path == drvpath
    end

    def self.deserialize(val)
      pkg = super(val)
      pkg.homepage = val[:homepage]
      pkg.repository_git = val[:repository_git]
      pkg.branch = val[:branch]
      pkg.sha256 = val[:sha256]
      pkg.position = val[:position]
      pkg.maintainers = []
      return pkg
    end


    def self.create_table(db)
      db.create_table!(table_name) do
        String :internal_name, :unique => true, :primary_key => true
        String :name
        String :version
        String :repository_git
        String :branch
        String :url
        String :revision
        String :sha256
        String :position
        String :homepage
      end

      db.create_table!(:nix_maintainers) do
        String :internal_name
        String :maintainer
      end
    end


    def self.serialize_to_db(db, list)
      super
      list.each do |package|
        package.maintainers.each do |maintainer|
          db[:nix_maintainers] << { :internal_name => package.internal_name, :maintainer =>maintainer }
        end
      end
    end


    def self.load_from_db(db)
      super
      if DB.table_exists?(:nix_maintainers)
        DB[:nix_maintainers].each do |record|
          @by_internal_name[record[:internal_name]].maintainers << record[:maintainer]
        end
      else
        STDERR.puts "#{:nix_maintainers} doesn't exist"
      end
    end


    def self.repository_path
      "nixpkgs"
    end

    def self.log_name_parse
      @log_name_parse ||= Reports::Logs.new(:nixpkgs_failed_name_parse)
    end

    def self.log_no_sources
      @log_no_sources ||= Reports::Logs.new(:nixpkgs_no_sources)
    end

    def self.package_from_xml(pkg_xml)
      attr = pkg_xml[:attrPath]
      name = pkg_xml[:name]
      if name and attr
        package = ( name =~ /(.*?)-([^A-Za-z].*)/ ? Nix.new(attr, $1, $2) : Nix.new(attr, name, "") )
        log_name_parse.pkg(attr) if package.version.to_s.empty?

        package.drvpath = pkg_xml[:drvPath]

        outpath = pkg_xml.xpath('output[@name="out"]').first
        package.outpath = outpath[:path] if outpath

        repository_git = pkg_xml.xpath('meta[@name="repositories.git"]').first
        package.repository_git = repository_git[:value] if repository_git

        url = pkg_xml.xpath('meta[@name="src.repo"]').first
        package.url = url[:value] if url

        url = pkg_xml.xpath('meta[@name="src.url"]').first
        package.url = url[:value] if url

        log_no_sources.pkg(attr) if package.url.to_s.empty?

        rev = pkg_xml.xpath('meta[@name="src.rev"]').first
        package.revision = rev[:value] if rev

        sha256 = pkg_xml.xpath('meta[@name="src.sha256"]').first
        package.sha256 = sha256[:value] if sha256

        position = pkg_xml.xpath('meta[@name="position"]').first
        package.position = position[:value].rpartition('/nixpkgs/')[2] if position

        # if the package file name looks like a version, it is probably a branch, at least for haskell
        if package.position and package.internal_name.start_with? 'haskellPackages'
          file_name = File.basename(package.position).split('.')
          version = (file_name.last.start_with?('nix') ? file_name[0..-2] : file_name)
          package.branch = version.join('.') if version.reject{|s| s.to_i.to_s == s }.empty?
        end

        homepage = pkg_xml.xpath('meta[@name="homepage"]').first
        package.homepage = homepage[:value] if homepage

        branch = pkg_xml.xpath('meta[@name="branch"]').first
        package.branch = branch[:value] if branch

        maintainers = pkg_xml.xpath('meta[@name="maintainers"]/string').map{|m| m[:value]}
        package.maintainers = ( maintainers ? maintainers : [] )
        return package
      end
      return nil
    end


    def self.load_package(pkg)
      pkgs_xml = Nokogiri.XML(%x(nix-env-patched -qaA '#{pkg}' --attr-path --meta --xml --out-path --drv-path --file ./nixpkgs/))
      entry = pkgs_xml.xpath('items/item').first
      return nil unless entry and entry[:attrPath] == pkg
      package = package_from_xml(entry)
      return package if package and package.internal_name == pkg
    end


    def self.generate_list
      nix_list = {}

      puts %x(git clone https://github.com/NixOS/nixpkgs.git)
      puts %x(cd #{repository_path} && git checkout master --force && git pull --rebase)

      log_name_parse.clear!
      log_no_sources.clear!

      pkgs_xml = Nokogiri.XML(%x(nix-env-patched -qa '*' --attr-path --meta --xml --file ./nixpkgs/))
      pkgs_xml.xpath('items/item').each do|entry|
        package = package_from_xml(entry)
        if package
          pkg_hash = package.sha256 ? package.sha256 : package.internal_name
          nix_list[pkg_hash] = ( nix_list.has_key?(pkg_hash) ?
                                 (nix_list[pkg_hash].internal_name > package.internal_name ? nix_list[pkg_hash] : package) :
                                 package )
        else
          puts "failed to parse #{entry}"
        end
      end

      serialize_list(nix_list.values)
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
          package = Debian.new(pkg_name, pkg_name, pkg_version)
          deb_list[package.name] = package if package
        end
      end

      serialize_list(deb_list.values)
    end


    def self.match_nixpkg(pkg)
      pkgname = pkg.name.downcase
      match = list[pkgname]
      return match if match
#       match = list[pkg.name.gsub(/^ruby-/,"")]
#       return match if match
      match = list[pkgname.gsub(/^python-/,"")]
      return match if match
      match = list[pkgname.gsub(/^perl-(.*)$/,'lib\1-perl')]
      return match if match
      match = list[pkgname.gsub(/^(haskell-.*)-ghc\d+\.\d+\.\d+$/,'\1')]
      return match if match
      match = list[pkgname.gsub(/^xf86-(.*)$/,'xserver-xorg-\1')]
      return match if match
      match = list[pkgname+"1"]
      return match if match
      match = list[pkgname+"2"]
      return match if match
      match = list[pkgname+"3"]
      return match if match
      match = list[pkgname+"4"]
      return match if match
      match = list[pkgname+"5"]
      return match if match
      match = list[pkgname+"6"]
      return match if match
      return nil
    end

  end

end