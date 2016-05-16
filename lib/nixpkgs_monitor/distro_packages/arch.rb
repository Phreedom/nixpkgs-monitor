require 'nixpkgs_monitor/distro_packages/base'
require 'set'

module NixPkgsMonitor module DistroPackages

  class GenericArch < NixPkgsMonitor::DistroPackages::Base

    def self.parse_pkgbuild(entry, path)
      pkg_data = %x(bash -c 'source #{path} && echo -e $source\\\\n$pkgver\\\\n${pkgname[*]}').split("\n")
      url = pkg_data[0].strip
      pkg_ver = pkg_data[1].strip
      pkg_names = [entry] + pkg_data[2].split(' ')

      if pkg_ver.to_s.empty?
        puts "skipping #{entry}: no package version"
        return {}
      end
      if url.to_s.empty?
        puts "skipping #{entry}: no url found"
        return {}
      end

      puts "warning #{entry}: failed to parse package name list" if pkg_names.length <= 1

      Set.new(pkg_names).each_with_object(Hash.new) do |name, pkgs|
        pkgs[name] = new(name, name, pkg_ver, url.strip)
      end
    end

  end


  class Arch < GenericArch
    @cache_name = "arch"

    def self.generate_list
      arch_list = {}

      puts "Cloning / pulling repos."
      puts %x(git clone git://projects.archlinux.org/svntogit/packages.git)
      puts %x(cd packages && git pull --rebase)
      puts %x(git clone git://projects.archlinux.org/svntogit/community.git)
      puts %x(cd community && git pull --rebase)

      (Dir.entries("packages") + Dir.entries("community")).reject{ |entry| ['.', '..'].include? entry }
                                                          .each do |entry|
        [ File.join("packages", entry, "repos", "extra-i686", "PKGBUILD"),
          File.join("packages", entry, "repos", "core-i686", "PKGBUILD"),
          File.join("community", entry, "repos", "community-i686", "PKGBUILD")
        ].select { |f| File.exists? f }
         .each { |pkgbuild_file| arch_list.merge!(parse_pkgbuild(entry, pkgbuild_file)) }
      end
      serialize_list(arch_list.values)
    end

  end


  class AUR < GenericArch
    @cache_name = "aur"

    def self.generate_list
      aur_list = {}

      puts "Cloning AUR repos"
      puts %x(curl http://aur3.org/all_pkgbuilds.tar.gz -O)
      puts %x(rm -rf aur/*)
      puts %x(mkdir aur)
      puts %x(tar -xvf all_pkgbuilds.tar.gz  --show-transformed --transform s,/PKGBUILD,, --strip-components=1 -C aur)

      puts "Scanning AUR"
      Dir.entries("aur").each do |entry|
        next if entry == '.' or entry == '..'

        pkgbuild_file = File.join("aur", entry)
        aur_list.merge!(parse_pkgbuild(entry, pkgbuild_file)) if File.exists? pkgbuild_file
      end

      serialize_list(aur_list.values)
    end

  end

end end
