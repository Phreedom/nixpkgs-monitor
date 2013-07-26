#!/usr/bin/env ruby

require 'optparse'
require 'mechanize'
require 'logger'
require 'csv'
require 'distro-package.rb'
require 'package-updater.rb'
require 'security-advisory'
require 'sequel'
require 'set'

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

db_path = './db.sqlite'
DB = Sequel.sqlite(db_path)
DistroPackage::DB = DB

distros_to_update = []

OptionParser.new do |o|
  o.on("-v", "Verbose output. Can be specified multiple times") do
    log.level -= 1
  end

  o.on("--list-arch", "List Arch packages") do
    distros_to_update << DistroPackage::Arch
  end

  o.on("--list-aur", "List AUR packages") do
    distros_to_update << DistroPackage::AUR
  end

  o.on("--list-nix", "List nixpkgs packages") do
    distros_to_update << DistroPackage::Nix
  end

  o.on("--list-deb", "List Debian packages") do
    distros_to_update << DistroPackage::Debian
  end

  o.on("--list-gentoo", "List Gentoo packages") do
    distros_to_update << DistroPackage::Gentoo
  end

  o.on("--output-csv FILE", "Write report in CSV format to FILE") do |f|
    csv_report_file = f
  end

  o.on("--check-pkg-version-match", "List Nix packages for which either tarball can't be parsed or its version doesn't match the package version") do
    action = :check_pkg_version_match
  end

  o.on("--check-updates", "list NixPkgs packages which have updates available") do
    action = :check_updates
    pkgs_to_check += DistroPackage::Nix.packages
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

distros_to_update.each do |distro|
  log.debug distro.generate_list.inspect
end

if action == :coverage

  coverage = {}
  DistroPackage::Nix.packages.each do |pkg|
    coverage[pkg] = Updaters.map{ |updater| (updater.covers?(pkg) ? 1 : 0) }.reduce(0, :+)
  end

  DB.transaction do
    DB.create_table!(:estimated_coverage) do
      String :pkg_attr, :unique => true, :primary_key => true
      Integer :coverage
    end

    csv_string = CSV.generate do |csv|
      csv << ['Attr', 'Name','Version', 'Coverage']
      coverage.each do |pkg, cvalue|
        csv << [ pkg.internal_name, pkg.name, pkg.version, cvalue ]
        DB[:estimated_coverage] << { :pkg_attr => pkg.internal_name, :coverage => cvalue }
      end
    end
  end
  File.write(csv_report_file, csv_string) if csv_report_file

  covered = coverage.keys.select { |pkg| coverage[pkg] > 0 }
  notcovered = coverage.keys.select { |pkg| coverage[pkg] <=0 }
  puts "Covered #{covered.count} packages: #{covered.map{|pkg| "#{pkg.name} #{coverage[pkg]}"}.inspect}"
  puts "Not covered #{notcovered.count} packages: #{notcovered.map{|pkg| "#{pkg.name}:#{pkg.version}"}.inspect}"
  hard_to_cover = notcovered.select{ |pkg| pkg.url == nil or pkg.url == "" or pkg.url == "none" }
  puts "Hard to cover #{hard_to_cover.count} packages: #{hard_to_cover.map{|pkg| "#{pkg.name}:#{pkg.version}"}.inspect}"


elsif action == :check_updates

  Updaters.each do |updater|
    DB.transaction do

      DB.create_table!(updater.friendly_name) do
        String :pkg_attr, :unique => true, :primary_key => true
        String :version
      end

      pkgs_to_check.each do |pkg|
        new_ver = updater.newest_version_of pkg
        if new_ver
          puts "#{pkg.internal_name}/#{pkg.name}:#{pkg.version} " +
               "has new version #{new_ver} according to #{updater.friendly_name}"
          DB[updater.friendly_name] << { :pkg_attr => pkg.internal_name, :version => new_ver }
        end
      end

    end
  end

  # generate CSV report
  csv_string = CSV.generate do |csv|
    csv << ([ 'Attr', 'Name','Version', 'Coverage' ] + Updaters.map(&:name))

    pkgs_to_check.each do |pkg|
      report_line = [ pkg.internal_name, pkg.name, pkg.version ]
      report_line << Updaters.map{ |updater| (updater.covers?(pkg) ? 1 : 0) }.reduce(0, :+)

      Updaters.each do |updater|
        record = DB[updater.friendly_name][:pkg_attr => pkg.internal_name]
        report_line << ( record ? record[:version] : nil )
      end

      csv << report_line
    end
  end
  File.write(csv_report_file, csv_string) if csv_report_file

elsif action == :check_pkg_version_match

  DB.transaction do
    DB.create_table!(:version_mismatch) do
      String :pkg_attr, :unique => true, :primary_key => true
    end

    DistroPackage::Nix.packages.each do |pkg|
      unless Updater.versions_match?(pkg)
        puts pkg.serialize 
        DB[:version_mismatch] << pkg.internal_name
      end
    end
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
