require 'json'
require 'package_updaters/base'

module PackageUpdaters
  module Repository

    # handles Python packages hosted at http://pypi.python.org/
    class Pypi < PackageUpdaters::Base

      def self.releases
        @releases ||= Hash.new do |h, pkgname|
          h[pkgname] = JSON.parse(http_agent.get("http://pypi.python.org/pypi/#{pkgname}/json")
                                            .body)["releases"].keys
        end
      end

      def self.covers?(pkg)
        return( pkg.url =~ %r{^https?://pypi.python.org/packages/source/./([^/]*)/[^/]*$} and
                usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url and
                          %r{^https?://pypi.python.org/packages/source/./(?<pkgname>[^/]*)/[^/]*$} =~ pkg.url
        return new_versions(pkg.version.downcase, releases[pkgname], pkg.internal_name)
      end

    end

  end
end
