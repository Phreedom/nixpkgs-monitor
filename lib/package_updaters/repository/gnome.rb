require 'json'
require 'package_updaters/base'

module PackageUpdaters
  module Repository

    # handles GNOME packages hosted at mirror://gnome/
    class GNOME < PackageUpdaters::Base

      def self.tarballs
        @tarballs ||= Hash.new{|h, path| h[path] = JSON.parse(http_agent.get("http://download.gnome.org#{path}cache.json").body) }
      end

      def self.covers?(pkg)
        return( pkg.url and pkg.url =~ %r{^mirror://gnome(/sources/[^/]*/)[^/]*/[^/]*$} and usable_version?(pkg.version) )
      end

      def self.find_tarball(pkg, version)
        return nil if pkg.url.to_s.empty? or version.to_s.empty? or pkg.version.to_s.empty?
        (package_name, file_version) = parse_tarball_from_url(pkg.url)
        return nil unless package_name
        repo = tarballs["/sources/#{package_name}/"][1][package_name][version]
        return nil unless repo
        file ||= repo["tar.xz"] || repo["tar.bz2"] || repo["tar.gz"]
        return (file ? "mirror://gnome/sources/#{package_name}/#{file}" : nil )
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        return nil unless pkg.url =~ %r{^mirror://gnome(/sources/[^/]*/)[^/]*/[^/]*$}
        path = $1
        return new_tarball_versions(pkg, tarballs[path][2])
      end

    end

  end
end
