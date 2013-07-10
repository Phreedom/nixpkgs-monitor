require 'rubygems/package'
require 'zlib'
require 'json'

require './distro-package.rb'

module PackageUpdater

  # logger to be provided elsewhere
  Log = nil

  class Updater

    def self.log
      PackageUpdater::Log
    end


    def self.http_agent
      agent = Mechanize.new
      agent.user_agent = 'NixPkgs software update checker'
      return agent
    end


    def self.parse_tarball_name(tarball)
      package_name = file_version = nil

      if tarball =~ /^(.+?)[-_][vV]?([^A-Za-z].*)$/
        package_name = $1
        file_version = $2
      elsif tarball =~ /^([a-zA-Z]+?)\.?(\d[^A-Za-z].*)$/
        package_name = $1
        file_version = $2
      else
        log.info "failed to parse tarball #{tarball}"
        return nil
      end

      10.times do
        #_all was added for p7zip
        file_version.gsub!(/(\.gz|\.Z|\.bz2?|\.tbz|\.tbz2|\.lzma|\.lz|\.zip|\.xz|\.tar|\.tgz|\.iso|\.dfsg|\.7z|\.gem|\.full|[-_\.]?src|[-_\.]?[sS]ources?|[-\.]orig|\.rpm|\.jar|_all)$/, "")
      end

      return [ package_name, file_version ]
    end


    # FIXME: add support for X.Y.Z[-_]?(a|b|beta|c|r|rc|pre)?\d*

    # FIXME: add support for the previous case when followed by [-_]?p\d* ,
    # which usually mentions date, but may be a revision. the easiest way is to detect date by length and some  restricitons
    # find out what is the order of preference of such packages.

    # FIXME: support for abcd - > a.bc.d versioning scheme. compare package and tarball versions to detect
    # FIXME: support date-based versioning: seems to be automatic as long as previous case is handled correctly

    # Returns true if the version format can be parsed and compared against another
    def self.usable_version?(version)
      return (tokenize_version(version) != nil)
    end


    def self.tokenize_version(v)
      return nil if v.start_with?('.') or v.end_with?('.')
      result = []

      vcp = v.downcase.dup
      while vcp.length>0
        found = vcp.sub!(/\A(\d+|[a-zA-Z]+)\.?/) { result << $1; "" }
        return nil unless found
      end

      result.each do |token|
        return nil unless token =~ /^(\d+)$/ or ['alpha','beta','pre','rc'].include?(token) or ('a'..'z').include?(token)
      end

      result.map! do |token|
        token = 'a' if token == 'alpha'
        token = 'b' if token == 'beta'
        token = 'p' if token == 'pre'
        token = 'r' if token == 'rc'
        #puts "<#{token}>"
        if ('a'..'z').include? token
          -100 + token.ord - 'a'.ord
        elsif token =~ /^(\d+)$/
          (token ? token.to_i : -1)
        else
          return nil
        end
      end

      result.fill(-1,result.length, 10-result.length)
      return result
    end

    def self.is_newer?(v1, v2)
      t_v1 = tokenize_version(v1)
      t_v2 = tokenize_version(v2)

      return( (t_v1 <=> t_v2) >0 )
    end


    # TODO: refactor: put version cleanup and matching code somewhere else
    def self.new_tarball_version(pkg, tarballs)
      url = pkg.url;
      if url =~ %r{/([^/]*)$}
        file = $1
        (package_name, file_version) = parse_tarball_name(file)

        if file_version and package_name and true # test only
          v1 = file_version.downcase
          # removes haskell suffix, gimp plugin suffix and FIXME: linux version
          # FIXME: linux version removal breaks a couple of matches
          v2 = pkg.version.downcase.gsub(/-profiling$/,"").gsub(/-gimp-2.6.\d+-plugin$/,"").gsub(/-3\.9\.7$/,"")
          unless (v1 == v2) or (v1.gsub(/[-_]/,".") == v2) or (v1 == v2.gsub(".",""))
            log.warn "version mismatch: #{package_name} #{file_version} #{file} #{pkg.name} #{pkg.version}"
            return nil
          end

          package_name = package_name.downcase
          vlist = tarballs[package_name]
          return nil unless vlist
          return nil unless usable_version?(v2)
          max_version = v2
          vlist.each do |v|
            if usable_version?(v)
              if is_newer?(v, max_version)
                max_version = v
              end
            else
              log.info "found weird version of #{package_name} : #{v}. skipping" 
            end
          end

          return (max_version != v2 ? max_version : nil)
        end

      end
    end


    def self.tarballs_from_dir(dir, tarballs = {})
      begin

        http_agent.get(dir).links.each do |l|
          next if l.href.end_with?('.asc', '.exe', '.dmg', '.sig', '.sha1', '.patch', '.patch.gz', '.patch.bz2', '.diff', '.diff.bz2', '.xdelta')
          (name, version) = parse_tarball_name(l.href)
          if name and version
            tarballs[name] = [] unless tarballs[name]
            tarballs[name] = tarballs[name] << version 
          end
        end
        return tarballs

      rescue Mechanize::ResponseCodeError
        log.warn $!
        return {}
      end
    end


    def self.tarballs_from_dir_recursive(dir)
      tarballs = {}

      log.debug "#{dir}"
      http_agent.get(dir).links.each do |l|
        next if l.href == '..' or l.href == '../'
        if l.href =~ %r{^[^/]*/$}
          log.debug l.href
          tarballs = tarballs_from_dir(dir+l.href, tarballs)
        end
      end

      return tarballs
    end

  end


  class GentooDistfiles < Updater

    def self.distfiles
      unless @distfiles
        @distfiles = {}
        files = http_agent.get('http://distfiles.gentoo.org/distfiles/').links.map(&:href)
        files.each do |tarball|
          (name, version) = parse_tarball_name(tarball)
          if name
            name = name.downcase
            version = version.downcase
            unless version.include? 'patch' or version.include? 'diff'
              @distfiles[name] = [] unless @distfiles[name]
              @distfiles[name] =  @distfiles[name] << version
            end
          end
        end
        log.debug @distfiles.inspect
      end
      @distfiles
    end


    def self.newest_version_of(pkg)
        return new_tarball_version(pkg, distfiles)
    end

  end


  class DirTraversal < Updater
  end


  class HomePage < Updater
    # try homepage from metadata
    # try dirtraversal-like fetching or parent dirs to see if they contain something
    # follow links like source/download/development/contribute
  end


  class VersionGuess < Updater
  end


  module Repository

    # FIXME: nixpkgs has lots of urls which don't use mirror and instead have direct links :(
    # handles packages hosted at SourceForge
    class SF < Updater

      def self.covers?(pkg)
        return( pkg.url =~ %r{^mirror://sourceforge/(?:project/)?([^/]+).*?/([^/]+)$} and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        url = pkg.url;
        return nil unless url =~ %r{^mirror://sourceforge/(?:project/)?([^/]+).*?/([^/]+)$}
        sf_project = $1
        sf_file = $2
        tarballs = tarballs_from_dir("http://qa.debian.org/watch/sf.php/#{sf_project}")
        return new_tarball_version(pkg, tarballs)
      end

    end


    # handles Perl packages hosted at mirror://cpan/
    class CPAN < Updater

      def self.tarballs
        unless @tarballs
          @tarballs = {}
          z = Zlib::GzipReader.new(StringIO.new(http_agent.get("http://cpan.perl.org/indices/ls-lR.gz").body))
          unzipped = z.read
          dirs = unzipped.split("\n\n")
          dirs.each do |dir|
            lines = dir.split("\n")
            next unless lines[0].include? '/authors/'
            #remove dir and total
            lines.delete_at(0) 
            lines.delete_at(0)
            lines.each do |line|
              next if line[0] == 'd' or line [0] == 'l'
              tarball = line.split(' ').last
              next if tarball.end_with?('.txt', "CHECKSUMS", '.readme', '.meta', '.sig', '.diff', '.patch')
              (package_name, file_version) = parse_tarball_name(tarball)
              if file_version and package_name
                @tarballs[package_name] = [] unless @tarballs[package_name]
                @tarballs[package_name] = @tarballs[package_name] << file_version 
              else
                log.debug "weird #{line}"
              end
            end
          end
          log.debug @tarballs.inspect
        end
        @tarballs
      end

      def self.covers?(pkg)
        return( pkg.url.start_with? 'mirror://cpan/' and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        if pkg.url.start_with? 'mirror://cpan/'
          return new_tarball_version(pkg, tarballs)
        end
      end

    end


    # handles Ruby gems hosted at http://rubygems.org/
    class RubyGems < Updater

      def self.covers?(pkg)
        return( pkg.url.include? 'rubygems.org/downloads/' and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        return nil unless pkg.url.include? 'rubygems.org/downloads/'
        return nil unless pkg.url =~ %r{/([^/]*)$}
        file = $1
        (package_name, file_version) = parse_tarball_name(file)
        vdata =  http_agent.get("http://rubygems.org/api/v1/versions/#{package_name}.xml")
        @tarballs = {} unless @tarballs
        vdata.search('versions/version/number').each do |v|
          @tarballs[package_name] = [] unless @tarballs[package_name]
          @tarballs[package_name] = @tarballs[package_name] << v.inner_text 
        end
        return new_tarball_version(pkg, @tarballs)
      end

    end


    # handles Haskell packages hosted at http://hackage.haskell.org/
    class Hackage < Updater

      def self.tarballs
        unless @tarballs
          @tarballs = {}
          # Mechanize automatically unpacks gz, so we get tar
          tgz = http_agent.get('http://hackage.haskell.org/packages/archive/00-index.tar.gz').body
          tar = Gem::Package::TarReader.new(StringIO.new(tgz))
          tar.each do |entry|
            log.warn "failed to parse #{entry.full_name}" unless entry.full_name =~ %r{^([^/]+)/([^/]+)/}
            package_name = $1
            file_version = $2
            @tarballs[package_name] = [] unless @tarballs[package_name]
            @tarballs[package_name] = @tarballs[package_name] << file_version 
          end
          tar.close
        end
        @tarballs
      end

      def self.covers?(pkg)
        return( pkg.url.start_with? 'http://hackage.haskell.org/' and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        if pkg.url.start_with? 'http://hackage.haskell.org/'
          return new_tarball_version(pkg, tarballs)
        end
      end

    end


    # handles Python packages hosted at http://pypi.python.org/
    class Pypi < Updater

      def self.covers?(pkg)
        return( pkg.url =~ %r{^https?://pypi.python.org(/packages/source/./[^/]*/)[^/]*$} and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        return nil unless pkg.url =~ %r{^https?://pypi.python.org(/packages/source/./[^/]*/)[^/]*$}
        path = $1
        tarballs = tarballs_from_dir("http://pypi.python.org#{path}")
        return new_tarball_version(pkg, tarballs)
      end

    end


    # handles GNU packages hosted at mirror://gnu/
    class GNU < Updater

      def self.covers?(pkg)
        return( pkg.url =~ %r{^mirror://gnu(/[^/]*)/[^/]*$} and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        return nil unless pkg.url =~ %r{^mirror://gnu(/[^/]*)/[^/]*$}
        path = $1
        tarballs = tarballs_from_dir("http://ftpmirror.gnu.org#{path}")
        return new_tarball_version(pkg, tarballs)
      end

    end


    # handles X.org packages hosted at mirror://xorg/
    class Xorg < Updater

      def self.tarballs
        unless @tarballs
          @tarballs = tarballs_from_dir_recursive("http://xorg.freedesktop.org/releases/individual/")
          log.debug @tarballs.inspect
        end
        @tarballs
      end

      def self.covers?(pkg)
        return (pkg.url.start_with? "mirror://xorg/" and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        return nil unless pkg.url.start_with? "mirror://xorg/"
        return new_tarball_version(pkg, tarballs)
      end

    end


    # handles KDE stable packages hosted at mirror://kde/stable/
    class KDE < Updater

      def self.tarballs
        unless @tarballs
          @tarballs = {}
          dirs = http_agent.get("http://download.kde.org/ls-lR").body.split("\n\n")
          dirs.each do |dir|
            lines = dir.split("\n")
            next unless lines[0].include? '/stable'
            next if lines[0].include? '/win32:'
            lines.delete_at(0)
            lines.each do |line|
              next if line[0] == 'd' or line [0] == 'l'
              tarball = line.split(' ').last
              next if ['.xdelta', '.sha1', '.md5', '.CHANGELOG', '.sha256', '.patch', '.diff'].index{ |s|  tarball.include? s}
              (package_name, file_version) = parse_tarball_name(tarball)
              if file_version and package_name
                @tarballs[package_name] = [] unless @tarballs[package_name]
                @tarballs[package_name] = @tarballs[package_name] << file_version 
              end
            end
          end
        end
        log.debug @tarballs.inspect
        @tarballs
      end

      def self.covers?(pkg)
        return( pkg.url.start_with? 'mirror://kde/stable/' and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        if pkg.url.start_with? 'mirror://kde/stable/'
          return new_tarball_version(pkg, tarballs)
        end
      end

    end


    # handles GNOME packages hosted at mirror://gnome/
    class GNOME < Updater

      def self.covers?(pkg)
        return( pkg.url =~ %r{^mirror://gnome(/sources/[^/]*/)[^/]*/[^/]*$} and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        return nil unless pkg.url =~ %r{^mirror://gnome(/sources/[^/]*/)[^/]*/[^/]*$}
        path = $1
        tarballs =  JSON.parse(http_agent.get("http://download.gnome.org#{path}cache.json").body)[2]
        return new_tarball_version(pkg, tarballs)
      end

    end


    class XFCE < Updater
    end

  end


  module Distro

    # checks package versions against Arch Core, Community and Extra repositories
    class Arch < Updater

      def self.covers?(pkg)
        return ( DistroPackage::Arch.list[pkg.name] and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        arch_pkg = DistroPackage::Arch.list[pkg.name]
        return nil unless arch_pkg
        return nil unless usable_version?(arch_pkg.version) and usable_version?(pkg.version)
        return ( is_newer?(arch_pkg.version, pkg.version) ? arch_pkg.version : nil)
      end

    end


    # TODO: checks package versions against Debian Sid
    class Debian < Updater

    end


    # checks package versions agains those discovered by http://euscan.iksaif.net,
    # which include Gentoo portage, Gentoo developer repositories, euscan-discovered upstream.
    class Gentoo < Updater

      def self.covers?(pkg)
        return ( DistroPackage::Gentoo.list[pkg.name] and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        gentoo_pkg = DistroPackage::Gentoo.list[pkg.name]
        return nil unless gentoo_pkg
        return nil unless usable_version?(gentoo_pkg.version) and usable_version?(pkg.version)
        return ( is_newer?(gentoo_pkg.version, pkg.version) ? gentoo_pkg.version : nil)
      end

    end


  end


end