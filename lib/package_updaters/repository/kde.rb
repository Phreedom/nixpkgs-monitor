require 'package_updaters/base'

module PackageUpdaters
  module Repository

    # handles KDE stable packages hosted at mirror://kde/stable/
    class KDE < PackageUpdaters::Base

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

  end
end
