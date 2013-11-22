require 'rubygems/package'
require 'zlib'
require 'json'

require 'distro-package.rb'

module PackageUpdater

  class Updater

    def self.friendly_name
      name.gsub(/^PackageUpdater::/,"").gsub("::","_").downcase.to_sym
    end


    def self.log
      Log
    end


    def self.http_agent
      agent = Mechanize.new
      agent.user_agent = 'NixPkgs software update checker'
      return agent
    end


    def self.version_cleanup!(version)
      10.times do
        # _all was added for p7zip
        # add -stable?
        version.gsub!(/\.gz|\.Z|\.bz2?|\.tbz|\.tbz2|\.lzma|\.lz|\.zip|\.xz|[-\.]tar$/, "")
        version.gsub!(/\.tgz|\.iso|\.dfsg|\.7z|\.gem|\.full|[-_\.]?src|[-_\.]?[sS]ources?$/, "")
        version.gsub!(/\.run|\.otf|-dist|\.deb|\.rpm|[-_]linux|-release|-bin|\.el$/, "")
        version.gsub!(/[-_\.]i386|-i686|[-\.]orig|\.rpm|\.jar|_all$/, "")
      end
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

      version_cleanup!(file_version)

      return [ package_name, file_version ]
    end

    def self.parse_tarball_from_url(url)
      return parse_tarball_name($1) if url =~ %r{/([^/]*)$}
      log.info "Failed to parse url #{url}"
      return [nil, nil]
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


    # check that package and tarball versions match
    def self.versions_match?(pkg)
      (package_name, file_version) = parse_tarball_from_url(pkg.url)

      if file_version and package_name and true # test only
        v1 = file_version.downcase
        # removes haskell suffix, gimp plugin suffix and FIXME: linux version
        # FIXME: linux version removal breaks a couple of matches
        v2 = pkg.version.downcase
        unless (v1 == v2) or (v1.gsub(/[-_]/,".") == v2) or (v1 == v2.gsub(".",""))
          log.info "version mismatch: #{package_name} #{file_version} #{pkg.url} #{pkg.name} #{pkg.version}"
          return false
        end
        return true
      else
        log.info "failed to parse tarball #{pkg.url} #{pkg.internal_name}"
      end
      return false
    end


    def self.new_tarball_versions(pkg, tarballs)
      (package_name, file_version) = parse_tarball_from_url(pkg.url)

      if file_version and package_name and true # test only
        v1 = file_version.downcase
        v2 = pkg.version.downcase
        return nil unless versions_match?(pkg)

        package_name = package_name.downcase
        vlist = tarballs[package_name]
        return nil unless vlist
        t_pv = tokenize_version(v2)
        return nil unless t_pv
        max_version_major = v2
        max_version_minor = v2
        max_version_fix = v2
        vlist.each do |v|
          t_v = tokenize_version(v)
          if t_v
            #check for and skip 345.gz == v3.4.5 versions for now
            if t_v[0]>9 and t_v[1] = -1 and t_pv[1] != -1 and t_v[0]>5*t_pv[0]
              log.info "found weird(too high) version of #{package_name} : #{v}. skipping"
            else
              max_version_major = v if (t_v[0] != t_pv[0])  and is_newer?(v, max_version_major)
              max_version_minor = v if (t_v[0] == t_pv[0]) and (t_v[1] != t_pv[1])  and is_newer?(v, max_version_minor)
              max_version_fix = v if (t_v[0] == t_pv[0]) and (t_v[1] == t_pv[1]) and (t_v[2] != t_pv[2])  and is_newer?(v, max_version_fix)
            end
          else
            log.info "found weird version of #{package_name} : #{v}. skipping" 
          end
        end

        return(
            ((max_version_major == v2) and (max_version_minor == v2) and (max_version_fix == v2)) ? nil
            : [
                (max_version_major != v2 ? max_version_major : nil),
                (max_version_minor != v2 ? max_version_minor : nil),
                (max_version_fix   != v2 ? max_version_fix   : nil)
              ]
        )
      end
      return nil
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


    def self.newest_versions_of(pkg)
      v = newest_version_of(pkg)
      return nil unless v
      v_t = tokenize_version(v)
      v_orig_t = tokenize_version(pkg.version)
      # assume it may be something major if one of the versions is not available or parsable
      return [ v, nil, nil] unless v_t and v_orig_t

      return [ nil, nil, v] if (v_t[0] == v_orig_t[0]) and (v_t[1] == v_orig_t[1])
      return [ nil, v, nil] if (v_t[0] == v_orig_t[0])
      return [ v, nil, nil ]
    end


    def self.find_tarball(pkg, version)
      return nil unless pkg.url and version and pkg.url != "" and version != ""
      (pkg.url.include?(pkg.version) ? pkg.url.gsub(pkg.version, version) : nil )
    end

  end


  class GentooDistfiles < Updater

    def self.covers?(pkg)
      return false if Repository::CPAN.covers?(pkg) or Repository::Pypi.covers?(pkg) or
                      Repository::RubyGems.covers?(pkg) or Repository::Hackage.covers?(pkg)
      (package_name, file_version) = parse_tarball_from_url(pkg.url)

      return( package_name and file_version  and distfiles[package_name] and
              usable_version?(pkg.version) and usable_version?(file_version) )
    end

    def self.distfiles
      unless @distfiles
        @distfiles = {}
        files = http_agent.get('http://distfiles.gentoo.org/distfiles/').links.map(&:href)
        files.each do |tarball|
          (name, version) = parse_tarball_name(tarball)
          if name and name != "v"
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


    def self.newest_versions_of(pkg)
      return nil unless covers?(pkg)
      return new_tarball_versions(pkg, distfiles)
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

      def self.tarballs
        unless @tarballs
          @tarballs = Hash.new{|h, sf_project| h[sf_project] = tarballs_from_dir("http://qa.debian.org/watch/sf.php/#{sf_project}") }
        end
        @tarballs
      end

      def self.covers?(pkg)
        return( pkg.url =~ %r{^mirror://sourceforge/(?:project/)?([^/]+).*?/([^/]+)$} and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        url = pkg.url;
        return nil unless url =~ %r{^mirror://sourceforge/(?:project/)?([^/]+).*?/([^/]+)$}
        sf_project = $1
        return new_tarball_versions(pkg, tarballs[sf_project])
      end

    end


    # handles Node.JS packages hosted at npmjs.org
    class NPMJS < Updater

      def self.metadata
        unless @metadata
          @metadata = Hash.new{|h, pkgname| h[pkgname] = JSON.parse(http_agent.get("http://registry.npmjs.org/#{pkgname}/").body) }
        end
        @metadata
      end

      def self.covers?(pkg)
        return( pkg.url and pkg.url.start_with?("http://registry.npmjs.org/") and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        return nil unless pkg.url
        return nil unless %r{http://registry.npmjs.org/(?<pkgname>[^\/]*)/} =~ pkg.url
        new_ver = metadata[pkgname]["dist-tags"]["latest"]
        return nil unless usable_version?(new_ver) and usable_version?(pkg.version)
        return( is_newer?(new_ver, pkg.version) ? new_ver : nil ) 
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
                package_name = package_name.downcase
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
        return( pkg.url and pkg.url.start_with? 'mirror://cpan/' and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        if pkg.url.start_with? 'mirror://cpan/'
          return new_tarball_versions(pkg, tarballs)
        end
      end

    end


    # handles Ruby gems hosted at http://rubygems.org/
    class RubyGems < Updater

      def self.covers?(pkg)
        return( pkg.url and pkg.url.include? 'rubygems.org/downloads/' and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        return nil unless pkg.url.include? 'rubygems.org/downloads/'
        (package_name, file_version) = parse_tarball_from_url(pkg.url)
        return nil unless package_name
        vdata =  http_agent.get("http://rubygems.org/api/v1/versions/#{package_name}.xml")
        @tarballs = {} unless @tarballs
        vdata.search('versions/version/number').each do |v|
          @tarballs[package_name] = [] unless @tarballs[package_name]
          @tarballs[package_name] = @tarballs[package_name] << v.inner_text 
        end
        return new_tarball_versions(pkg, @tarballs)
      end

    end


    # handles Haskell packages hosted at http://hackage.haskell.org/
    class Hackage < Updater

      def self.tarballs
        unless @tarballs
          @tarballs = {}
          index_gz = http_agent.get('http://hackage.haskell.org/packages/archive/00-index.tar.gz').body
          tgz = Zlib::GzipReader.new(StringIO.new(index_gz)).read
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
        return( pkg.url and pkg.url.start_with? 'http://hackage.haskell.org/' and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        if pkg.url.start_with? 'http://hackage.haskell.org/'
          return new_tarball_versions(pkg, tarballs)
        end
      end

    end


    # handles Python packages hosted at http://pypi.python.org/
    class Pypi < Updater

      def self.tarballs
        unless @tarballs
          @tarballs = Hash.new{|h,path| h[path] = tarballs_from_dir("http://pypi.python.org#{path}") }
        end
        @tarballs
      end

      def self.covers?(pkg)
        return( pkg.url =~ %r{^https?://pypi.python.org(/packages/source/./[^/]*/)[^/]*$} and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        return nil unless pkg.url =~ %r{^https?://pypi.python.org(/packages/source/./[^/]*/)[^/]*$}
        path = $1
        return new_tarball_versions(pkg, tarballs[path])
      end

    end


    # handles GNU packages hosted at mirror://gnu/
    class GNU < Updater

      def self.tarballs
        unless @tarballs
          @tarballs = Hash.new{|h,path| h[path] = tarballs_from_dir("http://ftpmirror.gnu.org#{path}") }
        end
        @tarballs
      end

      def self.covers?(pkg)
        return( pkg.url and pkg.url =~ %r{^mirror://gnu(/[^/]*)/[^/]*$} and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        return nil unless pkg.url =~ %r{^mirror://gnu(/[^/]*)/[^/]*$}
        path = $1
        return new_tarball_versions(pkg, tarballs[path])
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
        return( pkg.url and pkg.url.start_with? "mirror://xorg/" and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        return nil unless pkg.url.start_with? "mirror://xorg/"
        return new_tarball_versions(pkg, tarballs)
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
        return( pkg.url and pkg.url.start_with? 'mirror://kde/stable/' and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        if pkg.url.start_with? 'mirror://kde/stable/'
          return new_tarball_versions(pkg, tarballs)
        end
      end

    end


    # handles GNOME packages hosted at mirror://gnome/
    class GNOME < Updater

      def self.tarballs
        unless @tarballs
          @tarballs = Hash.new{|h, path| h[path] = JSON.parse(http_agent.get("http://download.gnome.org#{path}cache.json").body)[2] }
        end
        @tarballs
      end

      def self.covers?(pkg)
        return( pkg.url and pkg.url =~ %r{^mirror://gnome(/sources/[^/]*/)[^/]*/[^/]*$} and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        return nil unless pkg.url =~ %r{^mirror://gnome(/sources/[^/]*/)[^/]*/[^/]*$}
        path = $1
        return new_tarball_versions(pkg, tarballs[path])
      end

    end


    # Generic git-based updater. Discovers new versions using git repository tags.
    class GitUpdater < Updater

      def self.ls_remote(repo)
        @repo_cache = {} unless @repo_cache
        unless @repo_cache[repo]
          @repo_cache[repo] = %x(GIT_ASKPASS="echo" SSH_ASKPASS= git ls-remote #{repo}).split("\n")
        end
        @repo_cache[repo]
      end

      # Tries to handle the tag as a tarball name.
      # if parsing it as a tarball fails, treats it as a version.
      def self.tag_to_version(tag_line)
        if %r{refs/tags.*/[vr]?(?<tag>\S*?)(\^\{\})?$} =~ tag_line
          if tag =~ /^[vr]?\d/
            return tag
          else
            (name, version) = parse_tarball_name(tag)
            return (version ? version : tag)
          end
        else
          return nil
        end
      end

      def self.repo_contents_to_tags(repo_contents)
        tags = repo_contents.select{ |s| s.include? "refs/tags/" }
        return tags.map{ |tag| tag_to_version(tag) }
      end

    end


    # Handles fetchgit-based packages.
    # Tries to detect which tag the current revision corresponds to.
    # Otherwise assumes the package is tracking master because
    # there's no easy way to be smarter without checking out the repository.
    # Tries to find a newer tag or if tracking master, newest commit.
    class FetchGit < GitUpdater

      def self.covers?(pkg)
        return( pkg.url and pkg.revision != "" and pkg.url.include? "git" )
      end


      def self.newest_version_of(pkg)
        return nil unless covers?(pkg)

        repo_contents = ls_remote(pkg.url).select{|s| s.include?("refs/tags") or s.include?("refs/heads/master") }
        tag_line = repo_contents.index{|line| line.include? pkg.revision }
        
        log.debug "for #{pkg.revision} found #{tag_line}"
        if tag_line # revision refers to a tag?
          return nil if repo_contents[tag_line].include?("refs/heads/master")

          current_version = tag_to_version(repo_contents[tag_line])
          
          if current_version and usable_version?(current_version)

            versions = repo_contents_to_tags(repo_contents)
            max_version = versions.reduce(current_version) do |v1, v2|
              ( usable_version?(v2) and is_newer?(v2, v1) ) ? v2 : v1
            end
            return (max_version != current_version ? max_version : nil)

          else
            log.warn "failed to parse tag #{repo_contents[tag_line]} for #{pkg.name}. Assuming tracking master"
          end
        end

        # assuming tracking master
        master_line = repo_contents.index{|line| line.include? "refs/heads/master" }
        if master_line
          /^(?<master_commit>\S*)/ =~ repo_contents[master_line]
          log.info "new master commit #{master_commit} for #{pkg.name}:#{pkg.revision}"
          return( master_commit.start_with?(pkg.revision) ? nil : master_commit )
        else
          log.warn "failed to find master for #{pkg.name}"
          return nil
        end

      end

    end


    # Handles GitHub-provided tarballs.
    class GitHub < GitUpdater

      def self.covers?(pkg)
        return( pkg.url and not(pkg.revision) and pkg.url  =~ %r{^https?://github.com/} and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        return nil unless pkg.url
        return nil if pkg.revision
        return nil unless %r{^https?://github.com/(?:downloads/)?(?<owner>[^/]*)/(?<repo>[^/]*)/} =~ pkg.url
        return nil unless usable_version?(pkg.version)

        versions = repo_contents_to_tags( ls_remote( "https://github.com/#{owner}/#{repo}.git" ) )
        max_version = versions.reduce(pkg.version) do |v1, v2|
          ( usable_version?(v2) and is_newer?(v2, v1) ) ? v2 : v1
        end
        return (max_version != pkg.version ? max_version : nil)
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


    # checks package versions against Arch AUR
    class AUR < Updater

      def self.covers?(pkg)
        return ( DistroPackage::AUR.list[pkg.name] and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        arch_pkg = DistroPackage::AUR.list[pkg.name]
        return nil unless arch_pkg
        return nil unless usable_version?(arch_pkg.version) and usable_version?(pkg.version)
        return ( is_newer?(arch_pkg.version, pkg.version) ? arch_pkg.version : nil)
      end

    end


    # TODO: checks package versions against Debian Sid
    class Debian < Updater

      def self.covers?(pkg)
        return ( DistroPackage::Debian.match_nixpkg(pkg) and usable_version?(pkg.version) )
      end

      def self.newest_version_of(pkg)
        deb_pkg = DistroPackage::Debian.match_nixpkg(pkg)
        return nil unless deb_pkg
        return nil unless usable_version?(deb_pkg.version) and usable_version?(pkg.version)
        return ( is_newer?(deb_pkg.version, pkg.version) ? deb_pkg.version : nil)
      end

    end


    # checks package versions agains those discovered by http://euscan.iksaif.net,
    # which include Gentoo portage, Gentoo developer repositories, euscan-discovered upstream.
    class Gentoo < Updater

      def self.covers?(pkg)
        return ( DistroPackage::Gentoo.match_nixpkg(pkg) and usable_version?(pkg.version) and not Repository::CPAN.covers?(pkg) )
      end

      def self.newest_version_of(pkg)
        return nil unless covers?(pkg)
        gentoo_pkg = DistroPackage::Gentoo.match_nixpkg(pkg)
        return nil unless gentoo_pkg
        return nil unless usable_version?(gentoo_pkg.version) and usable_version?(pkg.version)
        return ( is_newer?(gentoo_pkg.version, pkg.version) ? gentoo_pkg.version : nil)
      end

    end


  end


  Updaters = [ 
             Repository::CPAN,
             Repository::RubyGems,
             Repository::Xorg, 
             Repository::GNOME,
             Distro::Gentoo,
             Repository::Hackage,
             Repository::Pypi,
             Repository::KDE,
             Repository::GNU,
             Repository::SF,
             Repository::NPMJS,
             Repository::FetchGit,
             Repository::GitHub,
             GentooDistfiles,
             Distro::Arch,
             Distro::Debian,
             Distro::AUR,
  ]

end