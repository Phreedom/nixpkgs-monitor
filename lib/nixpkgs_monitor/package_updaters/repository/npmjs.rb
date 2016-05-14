require 'json'
require 'nixpkgs_monitor/package_updaters/base'

module NixPkgsMonitor module PackageUpdaters module Repository

  # handles Node.JS packages hosted at npmjs.org
  class NPMJS < NixPkgsMonitor::PackageUpdaters::Base

    def self.metadata
      @metadata ||= Hash.new{|h, pkgname| h[pkgname] = JSON.parse(http_agent.get("http://registry.npmjs.org/#{pkgname}/").body) }
    end

    def self.covers?(pkg)
      pkg.url and pkg.url.start_with?("http://registry.npmjs.org/") and usable_version?(pkg.version)
    end

    def self.newest_version_of(pkg)
      return nil unless %r{http://registry.npmjs.org/(?<pkgname>[^\/]*)/} =~ pkg.url
      new_ver = metadata[pkgname]["dist-tags"]["latest"]
      return nil unless usable_version?(new_ver) and usable_version?(pkg.version)
      ( is_newer?(new_ver, pkg.version) ? new_ver : nil )
    end

  end

end end end
