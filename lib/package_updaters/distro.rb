require 'distro-package.rb'
require 'package_updaters/base'

module PackageUpdaters
  module Distro

    # checks package versions against Arch Core, Community and Extra repositories
    class Arch < PackageUpdaters::Base

      def self.covers?(pkg)
        DistroPackage::Arch.list[pkg.name.downcase] and usable_version?(pkg.version)
      end

      def self.newest_version_of(pkg)
        return nil unless covers?(pkg)
        arch_pkg = DistroPackage::Arch.list[pkg.name.downcase]
        return nil unless usable_version?(arch_pkg.version)
        ( is_newer?(arch_pkg.version, pkg.version) ? arch_pkg.version : nil )
      end

    end


    # checks package versions against Arch AUR
    class AUR < PackageUpdaters::Base

      def self.covers?(pkg)
        DistroPackage::AUR.list[pkg.name.downcase] and usable_version?(pkg.version)
      end

      def self.newest_version_of(pkg)
        return nil unless covers?(pkg)
        arch_pkg = DistroPackage::AUR.list[pkg.name.downcase]
        return nil unless usable_version?(arch_pkg.version)
        ( is_newer?(arch_pkg.version, pkg.version) ? arch_pkg.version : nil )
      end

    end


    # TODO: checks package versions against Debian Sid
    class Debian < PackageUpdaters::Base

      def self.covers?(pkg)
        DistroPackage::Debian.match_nixpkg(pkg) and usable_version?(pkg.version)
      end

      def self.newest_version_of(pkg)
        return nil unless covers?(pkg)
        deb_pkg = DistroPackage::Debian.match_nixpkg(pkg)
        return nil unless usable_version?(deb_pkg.version)
        ( is_newer?(deb_pkg.version, pkg.version) ? deb_pkg.version : nil )
      end

    end


    # checks package versions agains those discovered by http://euscan.iksaif.net,
    # which include Gentoo portage, Gentoo developer repositories, euscan-discovered upstream.
    class Gentoo < PackageUpdaters::Base

      def self.covers?(pkg)
        DistroPackage::Gentoo.match_nixpkg(pkg) and usable_version?(pkg.version) and
        not Repository::CPAN.covers?(pkg) and not Repository::Hackage.covers?(pkg)
      end

      def self.newest_version_of(pkg)
        return nil unless covers?(pkg)
        gentoo_pkg = DistroPackage::Gentoo.match_nixpkg(pkg)
        return nil unless usable_version?(gentoo_pkg.version)
        ( is_newer?(gentoo_pkg.version, pkg.version) ? gentoo_pkg.version : nil )
      end

    end

    Updaters = [ Gentoo, Arch, Debian, AUR ]

  end
end
