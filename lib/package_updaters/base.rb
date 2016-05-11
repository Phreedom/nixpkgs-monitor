require 'mechanize'

module PackageUpdaters

  class Base

    def self.friendly_name
      name.gsub(/^PackageUpdaters::/,"").gsub("::","_").downcase.to_sym
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
      !tokenize_version(version).nil?
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


    # returns an array of major, minor and fix versions from the available_versions array
    def self.new_versions(version, available_versions, package_name)
      t_pv = tokenize_version(version)
      return nil unless t_pv

      max_version_major = version
      max_version_minor = version
      max_version_fix = version
      available_versions.each do |v|
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
          log.info "can't parse update version candidate of #{package_name} : #{v}. skipping" 
        end
      end

      return( (max_version_major != version ? [ max_version_major ] : []) +
              (max_version_minor != version ? [ max_version_minor ] : []) +
              (max_version_fix   != version ? [ max_version_fix   ] : []) )
    end


    def self.new_tarball_versions(pkg, tarballs)
      (package_name, file_version) = parse_tarball_from_url(pkg.url)
      return nil if file_version.to_s.empty? or package_name.to_s.empty?

      return nil unless versions_match?(pkg)

      vlist = tarballs[package_name.downcase]
      return nil unless vlist

      new_versions(pkg.version.downcase, vlist, package_name)
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
      (v ? [v] : nil)
    end


    def self.find_tarball(pkg, version)
      return nil if pkg.url.to_s.empty? or version.to_s.empty? or pkg.version.to_s.empty?
      new_url = (pkg.url.include?(pkg.version) ? pkg.url.gsub(pkg.version, version) : nil )
      return nil unless new_url
      bz_url = new_url.sub(/\.tar\.gz$/, ".tar.bz2")
      xz_url = bz_url.sub(/\.tar\.bz2$/, ".tar.xz")
      [ xz_url, bz_url, new_url ]
    end

  end

end
