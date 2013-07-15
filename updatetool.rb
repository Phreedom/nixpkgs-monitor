#!/usr/bin/env ruby

require 'optparse'
require 'mechanize'
require 'logger'
require 'csv'
require 'distro-package.rb'
require 'package-updater.rb'
require 'security-advisory'

include PackageUpdater

log = Logger.new(STDOUT)
log.level = Logger::WARN
log.formatter = proc { |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
}
PackageUpdater::Log = log

csv_report_file = nil
action = nil
pkgs_to_check = []

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
             Repository::NPMJS,
             GentooDistfiles, # +
             Distro::Arch, # +
             Distro::Debian, # +
             Distro::AUR, # +
]

OptionParser.new do |o|
  o.on("-v", "Verbose output. Can be specified multiple times") do
    log.level -= 1
  end

  o.on("--list-arch", "List Arch packages") do
    log.debug DistroPackage::Arch.generate_list.inspect
  end

  o.on("--list-aur", "List AUR packages") do
    log.debug DistroPackage::AUR.generate_list.inspect
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

  o.on("--output-csv FILE", "Write report in CSV format to FILE") do |f|
    csv_report_file = f
  end

  o.on("--check-pkg-version-match", "List Nix packages for which either tarball can't be parsed or its version doesn't match the package version") do
    action = :check_pkg_version_match
  end

  o.on("--check-updates", "list NixPkgs packages which have updates available") do
    action = :check_updates
    pkgs_to_check += DistroPackage::Nix.list.values
  end

  o.on("--check-package PACKAGE", "Check what updates are available for PACKAGE") do |pkgname|
    action = :check_updates
    pkgs_to_check << DistroPackage::Nix.list[pkgname]
  end

  o.on("--find-unmatched-advisories", "Find security advisories which don't map to a Nix package(don't touch yet)") do
    action = :find_unmatched_advisories
  end

  o.on("--coverage", "list NixPkgs packages which have (no) update coverage") do
    action = :coverage
  end

  o.on("-h", "--help", "Show this message") do
    puts o
    exit
  end

  o.parse(ARGV)
end


if action == :coverage

  coverage = {}
  DistroPackage::Nix.list.each_value do |pkg|
    coverage[pkg] = updaters.map{ |updater| (updater.covers?(pkg) ? 1 : 0) }.reduce(0, :+)
  end

  csv_string = CSV.generate do |csv|
    csv << ['Attr', 'Name','Version', 'Coverage']
    coverage.each do |pkg, cvalue|
      csv << [ pkg.internal_name, pkg.name, pkg.version, cvalue ]
    end
  end
  File.write(csv_report_file, csv_string) if csv_report_file

  covered = coverage.keys.select { |pkg| coverage[pkg] > 0 }
  notcovered = coverage.keys.select { |pkg| coverage[pkg] <=0 }
  puts "Covered #{covered.count} packages: #{covered.map{|pkg| "#{pkg.name} #{coverage[pkg]}"}.inspect}"
  puts "Not covered #{notcovered.count} packages: #{notcovered.map{|pkg| "#{pkg.name}:#{pkg.version}"}.inspect}"

elsif action == :check_updates

  csv_string = CSV.generate do |csv|
    csv << ([ 'Attr', 'Name','Version', 'Coverage' ] + updaters.map(&:name))

    pkgs_to_check.each do |pkg|
      report_line = [ pkg.internal_name, pkg.name, pkg.version ]
      report_line << updaters.map{ |updater| (updater.covers?(pkg) ? 1 : 0) }.reduce(0, :+)

      updaters.each do |updater|
        new_ver = updater.newest_version_of pkg
        puts "#{pkg.internal_name}/#{pkg.name}:#{pkg.version} has new version #{new_ver} according to #{updater.name}" if new_ver
        report_line << new_ver
      end

      csv << report_line
    end

  end
  File.write(csv_report_file, csv_string) if csv_report_file

elsif action == :check_pkg_version_match

  DistroPackage::Nix.list.each_value do |pkg|
    puts pkg.serialize unless Updater.versions_match?(pkg)
  end

elsif action == :find_unmatched_advisories

  known_safe = [
    # these advisories don't apply because they have been checked to refer to packages that don't exist in nixpgs
    "GLSA-201210-02",
  ]
  SecurityAdvisory::GLSA.list.each do |glsa|
    nixpkgs = glsa.matching_nixpkgs
    if nixpkgs
      log.info "Matched #{glsa.id} to #{nixpkgs.internal_name}"
    elsif known_safe.include? glsa.id
      log.info "Skipping #{glsa.id} as known safe"
    else
      log.warn "Failed to match #{glsa.id} #{glsa.packages}"
    end
  end

end
