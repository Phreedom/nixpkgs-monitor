require 'nixpkgs_monitor/distro_packages/base'

module NixPkgsMonitor module DistroPackages

  class Debian < NixPkgsMonitor::DistroPackages::Base
    @cache_name = "debian"

    def version
      @version.sub(/^\d:/,"").sub(/-\d$/,"").sub(/\+dfsg.*$/,"")
    end

    def self.generate_list
      deb_list = {}

      puts "Downloading repository metadata"
      %x(curl http://ftp.debian.org/debian/dists/sid/main/source/Sources.xz -o debian-main.xz)
      %x(curl http://ftp.debian.org/debian/dists/sid/contrib/source/Sources.xz -o debian-contrib.xz)
      %x(curl http://ftp.debian.org/debian/dists/sid/non-free/source/Sources.xz -o debian-non-free.xz)

      %x(xzcat debian-main.xz debian-contrib.xz debian-non-free.xz)
          .split("\n\n").each do |pkgmeta|
            next unless (/Package:\s*(?<pkg_name>.+)/ =~ pkgmeta and
                         /Version:\s*(?<pkg_version>.+)/ =~ pkgmeta)
            deb_list[pkg_name] = Debian.new(pkg_name, pkg_name, pkg_version)
          end

      serialize_list(deb_list.values)
    end

  end

end end
