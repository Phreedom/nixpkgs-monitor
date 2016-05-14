require 'nixpkgs_monitor/distro_packages/base'

module NixPkgsMonitor module DistroPackages

  class GenericArch < NixPkgsMonitor::DistroPackages::Base

    # FIXME: support multi-output PKGBUILDs
    def self.parse_pkgbuild(entry, path)
      dont_expand = [ 'pidgin' ]

      pkgbuild = File.read(path, :encoding => 'ISO-8859-1') 
      pkg_name = (pkgbuild =~ /pkgname=(.*)/ ? $1.strip : nil)
      pkg_ver = (pkgbuild =~ /pkgver=(.*)/ ? $1.strip : nil)

      pkg_name = entry if dont_expand.include? entry
      unless pkg_name and pkg_ver
        puts "skipping #{entry}: no package name or version"
        return nil
      end
      if pkg_name.include? "("
        puts "skipping #{entry}: unsupported multi-package PKGBUILD"
        return nil
      end

      url = %x(bash -c 'source #{path} && echo $source').split("\n").first
      url.strip! if url
      return new(entry, pkg_name, pkg_ver, url)
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

      puts "Scanning Arch Core, Extra (packages.git) repositories..."
      Dir.entries("packages").each do |entry|
        next if entry == '.' or entry == '..'

        pkgbuild_name = File.join("packages", entry, "repos", "extra-i686", "PKGBUILD")
        pkgbuild_name = File.join("packages", entry, "repos", "core-i686", "PKGBUILD") unless File.exists? pkgbuild_name

        if File.exists? pkgbuild_name
          package = parse_pkgbuild(entry, pkgbuild_name)
          arch_list[package.name] = package if package
        end
      end

      puts "Scanning Arch Community repository..."
      Dir.entries("community").each do |entry|
        next if entry == '.' or entry == '..'

        pkgbuild_name = File.join("community", entry, "repos", "community-i686", "PKGBUILD")

        if File.exists? pkgbuild_name
          package = parse_pkgbuild(entry, pkgbuild_name)
          arch_list[package.name] = package if package
        end
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

        pkgbuild_name = File.join("aur", entry)
        if File.exists? pkgbuild_name
          package = parse_pkgbuild(entry, pkgbuild_name)
          aur_list[package.name] = package if package
        end
      end

      serialize_list(aur_list.values)
    end

  end

end end
