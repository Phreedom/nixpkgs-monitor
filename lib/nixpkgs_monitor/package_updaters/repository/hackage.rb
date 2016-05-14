require 'rubygems/package'
require 'zlib'
require 'nixpkgs_monitor/package_updaters/base'

module NixPkgsMonitor module PackageUpdaters module Repository

  # handles Haskell packages hosted at http://hackage.haskell.org/
  class Hackage < NixPkgsMonitor::PackageUpdaters::Base

    def self.tarballs
      unless @tarballs
        @tarballs = Hash.new{|h,k| h[k] = Array.new }
        index_gz = http_agent.get('https://hackage.haskell.org/packages/index.tar.gz').body
        tgz = Zlib::GzipReader.new(StringIO.new(index_gz)).read
        tar = Gem::Package::TarReader.new(StringIO.new(tgz))
        tar.each do |entry|
          log.warn "failed to parse #{entry.full_name}" unless %r{^(?<pkg>[^/]+)/(?<ver>[^/]+)/} =~  entry.full_name
          @tarballs[pkg] << ver
        end
        tar.close
      end
      @tarballs
    end

    def self.covers?(pkg)
      pkg.url and pkg.url.start_with? 'mirror://hackage/' and usable_version?(pkg.version)
    end

    def self.newest_versions_of(pkg)
      return nil unless covers?(pkg)
      new_tarball_versions(pkg, tarballs)
    end

  end

end end end
