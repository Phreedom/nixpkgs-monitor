require 'zlib'
require 'package_updaters/base'

module PackageUpdaters
  module Repository

    # handles Perl packages hosted at mirror://cpan/
    class CPAN < PackageUpdaters::Base

      def self.tarballs
        unless @tarballs
          @tarballs = Hash.new{|h,k| h[k] = Array.new }
          @locations = {}
          z = Zlib::GzipReader.new(StringIO.new(http_agent.get("http://www.cpan.org/indices/ls-lR.gz").body))
          unzipped = z.read
          dirs = unzipped.split("\n\n")
          dirs.each do |dir|
            lines = dir.split("\n")
            next unless lines[0].include? '/authors/'
            #remove dir and total
            dir = lines[0][2..-2]
            lines.delete_at(0) 
            lines.delete_at(0)
            lines.each do |line|
              next if line[0] == 'd' or line [0] == 'l'
              tarball = line.split(' ').last
              next if tarball.end_with?('.txt', "CHECKSUMS", '.readme', '.meta', '.sig', '.diff', '.patch')
              (package_name, file_version) = parse_tarball_name(tarball)
              if file_version and package_name
                package_name = package_name.downcase
                @tarballs[package_name] << file_version
                @locations[[package_name, file_version]] = "mirror://cpan/#{dir}/#{tarball}"
              else
                log.debug "weird #{line}"
              end
            end
          end
          log.debug @tarballs.inspect
        end
        @tarballs
      end

      def self.find_tarball(pkg, version)
        return nil if pkg.url.to_s.empty? or version.to_s.empty? or pkg.version.to_s.empty?
        (package_name, file_version) = parse_tarball_from_url(pkg.url)
        return nil unless package_name
        tarballs # workaround to fetch data
        @locations[[package_name.downcase, version]]
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

  end
end
