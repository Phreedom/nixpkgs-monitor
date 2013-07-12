#!/usr/bin/env ruby

require 'optparse'
require 'mechanize'
require 'logger'
require 'distro-package.rb'
require 'package-updater.rb'
include PackageUpdater

log = Logger.new(STDOUT)
log.level = Logger::WARN
log.formatter = proc { |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
}
PackageUpdater::Log = log

OptionParser.new do |o|
  o.on("-v", "Verbose output. Can be specified multiple times") do
    log.level -= 1
  end

  o.on("--list-arch", "List arch packages") do
    log.debug DistroPackage::Arch.generate_list.inspect
  end

  o.on("--list-nix", "List nixpkgs packages") do
    log.debug DistroPackage::Nix.generate_list.inspect
  end

  o.on("--list-deb", "List Debian packages") do
    log.debug DistroPackage::Debian.generate_list.inspect
  end

  o.on("--list-gentoo", "List Gentoo packages") do
    log.debug DistroPackage::Gentoo.generate_list.inspect
  end

  o.on("--check-pkg-version-match", "List Nix packages for which either tarball can't be parsed or its version doesn't match the package version") do
    DistroPackage::Nix.list.each_value do |pkg|
      puts pkg.serialize unless Updater.versions_match?(pkg)
    end
  end

  o.on("--check-updates", "list NixPkgs packages which have updates available") do
    updaters = [ 
                 Repository::CPAN, # + not too horrible
                 Repository::RubyGems, # +
                 Repository::Xorg, # + 
                 Repository::GNOME, #+
                 Distro::Gentoo, #+
                 Repository::Hackage, # +
                 Repository::Pypi, # +
                 Repository::KDE, # +
                 Repository::GNU,# + produces lots of warning trash
                 Repository::SF, # + lots of trash I can't avoid 
                 GentooDistfiles, # +
                 Distro::Arch # +
               ]
    DistroPackage::Nix.list.each_value do |pkg|
      updaters.each do |updater|
        new_ver = updater.newest_version_of pkg
        puts "#{pkg.internal_name}/#{pkg.name}:#{pkg.version} has new version #{new_ver} according to #{updater.name}" if new_ver
      end
    end
  end

  o.on("--check-package PACKAGE", "Check what updates are available for PACKAGE") do |pkgname|
    updaters = [
                  Repository::CPAN,
                  Repository::RubyGems,
                  Repository::Xorg,
                  Repository::GNOME,
                  Distro::Gentoo,
                  Repository::Hackage,
                  Repository::Pypi,
                  Repository::KDE,
                  Repository::GNU,
                  Repository::SF,
                  #GentooDistfiles,
                  Distro::Arch,
               ]
    pkg = DistroPackage::Nix.list[pkgname]
    updaters.each do |updater|
      new_ver = updater.newest_version_of pkg
      puts "#{pkg.internal_name}/#{pkg.name}:#{pkg.version} has new version #{new_ver} according to #{updater.name}" if new_ver
    end
  end
  
  o.on("--coverage", "list NixPkgs packages which have (no) update coverage") do
    coverage = {}
    DistroPackage::Nix.list.each_value do |pkg|
      coverage[pkg] = 0
    end
    updaters = [
                  Repository::CPAN,
                  Repository::RubyGems,
                  Repository::Xorg,
                  Repository::GNOME,
                  Distro::Gentoo,
                  Repository::Hackage,
                  Repository::Pypi,
                  Repository::KDE,
                  Repository::GNU,
                  Repository::SF,
                  #GentooDistfiles, # coverage check not implemented
                  Distro::Arch,
               ];
    coverage.each_key do |pkg|
      updaters.each do |updater|
        coverage[pkg] +=1 if updater.covers? pkg
      end
    end
    covered = coverage.keys.select { |pkg| coverage[pkg] > 0 }
    notcovered = coverage.keys.select { |pkg| coverage[pkg] <=0 }
    puts "Covered #{covered.count} packages: #{covered.map{|pkg| "#{pkg.name} #{coverage[pkg]}"}.inspect}"
    puts "Not covered #{notcovered.count} packages: #{notcovered.map{|pkg| "#{pkg.name}:#{pkg.version}"}.inspect}"
  end

  o.on("-h", "--help", "Show this message") do
    puts o
    exit
  end

  o.parse(ARGV)
end
