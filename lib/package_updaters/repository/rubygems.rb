require 'json'
require 'package_updaters/base'

module PackageUpdaters
  module Repository

    # handles Ruby gems hosted at http://rubygems.org/
    class Rubygems < PackageUpdaters::Base

      def self.tarballs
        @tarballs ||= Hash.new do |h, pkgname|
          h[pkgname] = JSON.parse(http_agent.get("http://rubygems.org/api/v1/versions/#{pkgname}.json").body)
                           .map{|v| v["number"]}
        end
      end

      def self.covers?(pkg)
        pkg.url and pkg.url.include? 'rubygems.org/downloads/' and usable_version?(pkg.version)
      end

      def self.newest_versions_of(pkg)
        return nil unless covers?(pkg)
        (package_name, file_version) = parse_tarball_from_url(pkg.url)
        return nil unless package_name
        new_tarball_versions(pkg, tarballs[package_name])
      end

    end

  end
end
