require 'json'
require 'package_updaters/base'

module PackageUpdaters
  module Repository

    # handles Ruby gems hosted at http://rubygems.org/
    class Rubygems < PackageUpdaters::Base

      def self.covers?(pkg)
        return( pkg.url and pkg.url.include? 'rubygems.org/downloads/' and usable_version?(pkg.version) )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        return nil unless pkg.url.include? 'rubygems.org/downloads/'
        (package_name, file_version) = parse_tarball_from_url(pkg.url)
        return nil unless package_name

        @tarballs ||= {}
        vdata =  http_agent.get("http://rubygems.org/api/v1/versions/#{package_name}.json")
        @tarballs[package_name] = JSON.parse(vdata.body).map{|v| v["number"]}

        return new_tarball_versions(pkg, @tarballs)
      end

    end

  end
end
