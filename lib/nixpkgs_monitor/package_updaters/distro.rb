require 'nixpkgs_monitor/distro_packages'
require 'nixpkgs_monitor/package_updaters/base'

module NixPkgsMonitor module PackageUpdaters module Distro

  class Base < NixPkgsMonitor::PackageUpdaters::Base

    def self.covers?(pkg)
      match_nixpkg(pkg) and usable_version?(pkg.version)
    end

    def self.newest_version_of(pkg)
      return nil unless covers?(pkg)
      distro_pkg = match_nixpkg(pkg)
      return nil unless usable_version?(distro_pkg.version)
      ( is_newer?(distro_pkg.version, pkg.version) ? distro_pkg.version : nil )
    end

  end

  class ArchBase < Base

    def self.match_nixpkg(pkg)
      pkgname = pkg.name.downcase

      list[pkgname] or
      list['xorg-'+pkgname] or
      list['kdeedu-'+pkgname] or
      list['kdemultimedia-'+pkgname] or
      list['kdeutils-'+pkgname] or
      list['kdegames-'+pkgname] or
      list['kdebindings-'+pkgname] or
      list['kdegraphics-'+pkgname] or
      list['kdeaccessibility-'+pkgname] or
      list[pkgname.gsub(/^python[0-9\.]*-/, 'python-')] or
      list[pkgname.gsub(/^python[0-9\.]*-/, 'python2-')] or
      list[pkgname.gsub(/^aspell-dict-/, 'aspell-')] or
      list[pkgname.gsub(/^(haskell-.*)-ghc\d+\.\d+\.\d+$/, '\1')] or
      list[pkgname.gsub(/^ktp-/, 'telepathy-kde-')]
    end

  end

  # checks package versions against Arch Core, Community and Extra repositories
  class Arch < ArchBase

    def self.list
      NixPkgsMonitor::DistroPackages::Arch.list
    end

  end

  # checks package versions against Arch AUR
  class AUR < ArchBase

    def self.list
      NixPkgsMonitor::DistroPackages::AUR.list
    end

  end

  # TODO: checks package versions against Debian Sid
  class Debian < Base

    def self.match_nixpkg(pkg)
      pkgname = pkg.name.downcase
      list = NixPkgsMonitor::DistroPackages::Debian.list

      list[pkgname] or
      list[pkgname.gsub(/^python[0-9\.]*-/, '')] or
      list[pkgname.gsub(/^perl-(.*)$/, 'lib\1-perl')] or
      list[pkgname.gsub(/^(haskell-.*)-ghc\d+\.\d+\.\d+$/, '\1')] or
      list[pkgname.gsub(/^xf86-/, 'xserver-xorg-')] or
      list[pkgname+"1"] or
      list[pkgname+"2"] or
      list[pkgname+"3"] or
      list[pkgname+"4"] or
      list[pkgname+"5"] or
      list[pkgname+"6"]
    end

  end


  # checks package versions agains those discovered by http://euscan.iksaif.net,
  # which include Gentoo portage, Gentoo developer repositories, euscan-discovered upstream.
  class Gentoo < Base

    def self.covers?(pkg)
      match_nixpkg(pkg) and usable_version?(pkg.version) and
      not Repository::CPAN.covers?(pkg) and not Repository::Hackage.covers?(pkg)
    end

    def self.match_nixpkg(pkg)
      pkgname = pkg.name.downcase
      list = NixPkgsMonitor::DistroPackages::Gentoo.list

      list[pkgname] or
      list[pkgname.gsub(/^ruby-/, '')] or
      list[pkgname.gsub(/^python[0-9\.]*-/, '')] or
      list[pkgname.gsub(/^perl-/, '')] or
      list[pkgname.gsub(/^haskell-(.*)-ghc\d+\.\d+\.\d+$/,'\1')]
    end

  end

  Updaters = [ Gentoo, Arch, Debian, AUR ]

end end end
