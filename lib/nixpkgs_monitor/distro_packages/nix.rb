require 'nixpkgs_monitor/distro_packages/base'
require 'nixpkgs_monitor/reports'
require 'nokogiri'

module NixPkgsMonitor module DistroPackages

  # FIXME: nixpkgs often override package versions with suffixes such as -gui
  # which break matching because nixpks keeps only 1 of the packages
  # with the same name
  class Nix < NixPkgsMonitor::DistroPackages::Base

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
      super.merge({ :homepage => @homepage,
                    :repository_git => @repository_git,
                    :branch => @branch,
                    :sha256 => @sha256,
                    :position => @position,
                    :outpath => @outpath,
                    :drvpath => @drvpath })
    end

    def instantiate
      d_path = %x(nix-instantiate -A '#{internal_name}' ./nixpkgs/).strip
      raise "Failed to instantiate #{internal_name} #{drvpath}: [#{d_path}]" unless $? == 0 and d_path.split('!').first == drvpath
    end

    def self.deserialize(val)
      pkg = super(val)
      pkg.homepage = val[:homepage]
      pkg.repository_git = val[:repository_git]
      pkg.branch = val[:branch]
      pkg.sha256 = val[:sha256]
      pkg.position = val[:position]
      pkg.drvpath = val[:drvpath]
      pkg.outpath = val[:outpath]
      pkg.maintainers = []
      return pkg
    end


    def self.serialize_to_db(db, list)
      super
      db[:nix_maintainers].delete
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
      @log_name_parse ||= NixPkgsMonitor::Reports::Logs.new(:nixpkgs_failed_name_parse)
    end

    def self.log_no_sources
      @log_no_sources ||= NixPkgsMonitor::Reports::Logs.new(:nixpkgs_no_sources)
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
      pkgs_xml = Nokogiri.XML(%x(nix-env -qaA '#{pkg}' --attr-path --meta --xml --out-path --drv-path --file ./nixpkgs/))
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

      pkgs_xml = Nokogiri.XML(%x(nix-env -qa '*' --attr-path --meta --xml --out-path --drv-path --file ./nixpkgs/))
      raise "nixpkgs evaluation failed" unless $? == 0
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

end end
