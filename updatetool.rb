#!/usr/bin/env ruby

require 'optparse'
require 'mechanize'
require 'logger'
require 'distro-package'
require 'package-updater'
require 'security-advisory'
require 'reports'
require 'sequel'
require 'set'

include PackageUpdater


STDOUT.sync = true;
STDERR.sync = true;


log = Logger.new(STDOUT)
log.level = Logger::WARN
log.formatter = proc { |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
}

Log = log

actions = Set.new
pkg_names_to_check = []
builds_ignore_negative = false
builder_count = 1

db_path = './db.sqlite'
DB = Sequel.sqlite(db_path)

distros_to_update = Set.new

updaters = Updaters

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

  o.on("--check-pkg-version-match", "List Nix packages for which either tarball can't be parsed or its version doesn't match the package version") do
    actions << :check_pkg_version_match
  end

  o.on("--updater UPDATER", "Check for updates using only UPDATER. Accepts partial names.") do |uname|
    updaters = Updaters.select { |u| u.friendly_name.to_s.downcase.include? uname.downcase }
  end

  o.on("--check-updates", "list NixPkgs packages which have updates available") do
    actions << :check_updates
  end

  o.on("--check-package PACKAGE", "Check what updates are available for PACKAGE") do |pkgname|
    actions << :check_updates
    pkg_names_to_check << pkgname
  end

  o.on("--tarballs", "Try downloading all the candidate tarballs to the nix store") do
    actions << :tarballs
  end

  o.on("--redownload", "Try downloading missing tarballs again on the next --tarballs run") do
    actions << :drop_negative_tarball_cache
  end

  o.on("--patches", "Generate patches for packages updates") do
    actions << :patches
  end

  o.on("--build", "Try building patches") do
    actions << :build
  end

  o.on("--rebuild", "Try building patches marked as failed again on the next --build run") do
    actions << :drop_negative_build_cache
  end

  o.on("--builder-count NUMBER", Integer, "Number of packages to build in parallel") do |bc|
    builder_count = bc
    abort "builder count must be in 1..100 range" unless (1..100).include? bc
  end

  o.on("--find-unmatched-advisories", "Find security advisories which don't map to a Nix package(don't touch yet)") do
    actions << :find_unmatched_advisories
  end

  o.on("--cve-update", "Fetch CVE updates") do
    actions << :cve_update
  end

  o.on("--cve-check", "Check NixPkgs against CVE database") do
    actions << :cve_check
  end

  o.on("--coverage", "list NixPkgs packages which have (no) update coverage") do
    actions << :coverage
  end

  o.on("--all", "Update package definitions, check for updates, vulnerabilities, tarballs and write patches") do
    actions.merge([ :coverage, :check_updates, :cve_check, :cve_update, :tarballs, :patches ])
    distros_to_update.merge([ DistroPackage::Arch, DistroPackage::Nix, DistroPackage::Debian, DistroPackage::Gentoo ])
  end

  o.on("-h", "--help", "Show this message") do
    puts o
    exit
  end

  begin
    o.parse(ARGV)
  rescue
    abort "Wrong parameters: #{$!}. See --help for more information."
  end
end

abort "No action requested. See --help for more information." unless distros_to_update.count > 0 or actions.count > 0

distros_to_update.each do |distro|
  log.debug distro.generate_list.inspect
  Reports::Timestamps.done("fetch_#{distro.name.split('::').last.downcase}")
end


if actions.include? :coverage

  coverage = {}
  DistroPackage::Nix.packages.each do |pkg|
    coverage[pkg] = Updaters.map{ |updater| (updater.covers?(pkg) ? 1 : 0) }.reduce(:+)
  end

  DB.transaction do
    DB.create_table!(:estimated_coverage) do
      String :pkg_attr, :unique => true, :primary_key => true
      Integer :coverage
    end

    coverage.each do |pkg, cvalue|
      DB[:estimated_coverage] << { :pkg_attr => pkg.internal_name, :coverage => cvalue }
    end

    Reports::Timestamps.done(:coverage)
  end

end
if actions.include? :check_updates

  pkgs_to_check = ( pkg_names_to_check.empty? ?
                    DistroPackage::Nix.packages :
                    pkg_names_to_check.map{ |pkgname| DistroPackage::Nix.list[pkgname] }
                  )

  updaters.each do |updater|
    DB.transaction do

      DB.create_table!(updater.friendly_name) do
        String :pkg_attr
        String :version
        primary_key [ :pkg_attr, :version ]
      end

      pkgs_to_check.each do |pkg|
        new_ver = updater.newest_versions_of pkg
        if new_ver
          puts "#{pkg.internal_name}/#{pkg.name}:#{pkg.version} " +
               "has new version(s) #{new_ver} according to #{updater.friendly_name}"
          new_ver.reject(&:nil?).each do |version|
            DB[updater.friendly_name] << {
              :pkg_attr => pkg.internal_name,
              :version => version,
            }
          end
        end
      end

      Reports::Timestamps.done("updater_#{updater.friendly_name}")
    end
  end

  Reports::Timestamps.done(:updaters)

  DB.transaction do
    DB.create_table!(:tarballs) do
      String :pkg_attr
      String :version
      String :tarball
    end

    updaters.each do |updater|
      DB[updater.friendly_name].all.each do |row|
        pkg = DistroPackage::Nix.by_internal_name[row[:pkg_attr]]

        tarball = updater.find_tarball(pkg, row[:version])

        DB[:tarballs] << {
          :pkg_attr => row[:pkg_attr],
          :version => row[:version],
          :tarball => tarball
        } if tarball
      end
    end
  end

end
if actions.include? :drop_negative_tarball_cache

  DB[:tarball_sha256].where(:sha256 => "404").delete

end
if actions.include? :tarballs

  DB.create_table?(:tarball_sha256) do
    String :tarball, :unique => true, :primary_key => true
    String :sha256
  end

  DB[:tarballs].distinct.all.each do |row|
    tarball = row[:tarball]
    hash = DB[:tarball_sha256][:tarball => tarball]
    unless hash
      sha256 = %x(nix-prefetch-url #{tarball}).strip
      if $? == 0 and sha256 != ""
        puts "found #{sha256} hash"
      else
        puts "tarball #{tarball} not found"
        sha256 = "404"
      end
      DB.transaction do
        if 1 != DB[:tarball_sha256].where(:tarball => tarball).update(:sha256 => sha256)
          DB[:tarball_sha256] << { :tarball => tarball, :sha256 => sha256 }
        end
      end
    end
  end

  Reports::Timestamps.done(:tarballs)

end
if actions.include? :patches

  puts %x(cd #{DistroPackage::Nix.repository_path} && git checkout master --force)

  DB.transaction do

  # this is the biggest and ugliest collection of hacks
  DB.create_table!(:patches) do
    String :pkg_attr
    String :version
    String :tarball
    primary_key [ :pkg_attr, :version, :tarball ]
    Text :patch
    String :drvpath
    String :outpath
  end

  DB[:tarballs].join(:tarball_sha256,:tarball => :tarball).exclude(:sha256 => "404").distinct.all.each  do |row|
    nixpkg = DistroPackage::Nix.by_internal_name[row[:pkg_attr]]
    next unless nixpkg

    file_name =  File.join(DistroPackage::Nix.repository_path, nixpkg.position.rpartition(':')[0])
    original_content = File.readlines(file_name)
    sha256_location =  original_content.index{ |l| l.include? nixpkg.sha256 }
    unless sha256_location
      #puts "failed to find the original hash value in the file reported to contain the derivation for #{row[:pkg_attr]}. Grepping for it instead"
      file_name =  %x(grep -ir '#{nixpkg.sha256}' -rl #{File.join(DistroPackage::Nix.repository_path, 'pkgs')}).split("\n")[0]
      original_content = File.readlines(file_name)

      sha256_location =  original_content.index{ |l| l.include? nixpkg.sha256 }
      unless sha256_location
        puts "failed to find the original hash value to replace for #{row[:pkg_attr]}"
        next
      end
    end
    patched = original_content.map(&:dup) # deep copy
    patched[sha256_location].sub!(nixpkg.sha256, row[:sha256])
    # upgrade hash to sha256 if necessary
    patched[sha256_location].sub!(/md5\s*=/, "sha256 =")
    patched[sha256_location].sub!(/sha1\s*=/, "sha256 =")

    src_url_location = patched.index{ |l| l =~ /url\s*=.*;/ and l.include? nixpkg.url }
    patched[src_url_location].sub!(nixpkg.url, row[:tarball]) if src_url_location

    # a stupid heuristic targetting name = "..."; version = "..."; and such
    version_locations = patched.map.
        with_index{ |l, i| (l =~ /[nv].*=.*".*".*;/ and l.include? nixpkg.version) ? i : nil }.
        reject(&:nil?).
        sort_by{|l| (l-sha256_location).abs }

    unless version_locations.size>0
      puts "failed to find the original version value to replace for #{row[:pkg_attr]}"
      next
    end

    patch_index = version_locations.index do |version_location|
      patched_v = patched.map(&:dup) # deep copy
      patched_v[version_location].sub!(nixpkg.version, row[:version])

      File.write(file_name, patched_v.join)
      patch = %x(cd #{DistroPackage::Nix.repository_path} && git diff)
      new_pkg = DistroPackage::Nix.load_package(row[:pkg_attr])

      success = (new_pkg and new_pkg.url == row[:tarball] and
                 new_pkg.sha256 == row[:sha256] and new_pkg.version == row[:version])
      if success
        new_pkg.instantiate
        DB[:patches] << {
            :pkg_attr => row[:pkg_attr],
            :version => row[:version],
            :tarball => row[:tarball],
            :patch => patch,
            :drvpath => new_pkg.drvpath,
            :outpath => new_pkg.outpath
        }
      end
      success
    end

    puts "patch failed to change version, url or hash for #{row[:pkg_attr]}" unless patch_index

    File.write(file_name, original_content.join)
  end

  Reports::Timestamps.done(:patches)
  end

end
if actions.include? :drop_negative_build_cache

  DB[:builds].where(:status => "failed").delete

end
if actions.include? :build

  DB.create_table?(:builds) do
    String :outpath, :unique => true, :primary_key => true
    String :status
    String :log
  end

  queue = Queue.new

  DB[:patches].distinct.all.each do |row|
    outpath = row[:outpath]
    build = DB[:builds][:outpath => outpath]
    queue << row unless build
  end
  builder_count.times{ queue << nil } # add end of queue "job" x builder count

  (1..builder_count).map do |n|
    Thread.new(n) do |builder_id|

      while (row = queue.pop)
        if File.exist? row[:drvpath]

          log.warn "Builder #{builder_id} building: #{row[:drvpath]}"
          %x(nix-store --realise #{row[:drvpath]} 2>&1)
          status = ($? == 0 ? "ok" : "failed")

          log_path = row[:drvpath].sub(%r{^/nix/store/}, "")
          log_path = "/nix/var/log/nix/drvs/#{log_path[0,2]}/#{log_path[2,100]}.bz2"
          status = "dep failed" if not(File.exist?(log_path)) and status == "failed"
          build_log = ( status == "dep failed" ?
                        "" :
                        %x(bzcat #{log_path}).encode("us-ascii", :invalid=>:replace, :undef => :replace)
                      )

          log.warn "Builder #{builder_id} finished building: #{row[:drvpath]}"

          DB.transaction do
            if 1 != DB[:builds].where(:outpath => row[:outpath]).update(:status => status, :log => build_log)
              DB[:builds] << { :outpath => row[:outpath], :status => status, :log => build_log }
            end
          end

        else
          puts "derivation #{row[:drvpath]} seems to have been garbage-collected"
        end
      end

    end
  end.
  each(&:join) # wait for threads to finish

  Reports::Timestamps.done(:builds)

end
if actions.include? :check_pkg_version_match

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

end
if actions.include? :find_unmatched_advisories

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


SecurityAdvisory::CVE.fetch_updates if actions.include? :cve_update


if actions.include? :cve_check

  def sorted_hash_to_s(tokens)
    tokens.keys.sort{|x,y| tokens[x] <=> tokens[y] }.map{|t| "#{t}: #{tokens[t]}"}.join("\n")
  end

  list = SecurityAdvisory::CVE.list

  products = {}
  product_to_cve = {}
  list.each do |entry|
    entry.packages.each do |pkg|
      (supplier, product, version) = SecurityAdvisory::CVE.parse_package(pkg)
      pname = "#{product}"
      products[pname] = Set.new unless products[pname]
      products[pname] << version

      fullname = "#{product}:#{version}"
      product_to_cve[fullname] = Set.new unless product_to_cve[fullname]
      product_to_cve[fullname] << entry.id
    end
  end
  log.debug "products #{products.count}: #{products.keys.join("\n")}"

  products.each_pair do |product, versions|
    versions.each do |version|
      log.warn "can't parse version #{product} : #{version}" unless version =~ /^\d+\.\d+\.\d+\.\d+/ or version =~ /^\d+\.\d+\.\d+/ or version =~ /^\d+\.\d+/ or version =~ /^\d+/ 
    end
  end

  tokens = {}
  products.keys.each do |product|
    product.scan(/(?:[a-zA-Z]+)|(?:\d+)/).each do |token|
      tokens[token] = ( tokens[token] ? (tokens[token] + 1) : 1 )
    end
  end
  log.debug "token counts \n #{sorted_hash_to_s(tokens)} \n\n"

  selectivity = {}
  tokens.keys.each do |token|
    selectivity[token] = DistroPackage::Nix.packages.count do |pkg|
      pkg.internal_name.include? token or pkg.name.include? token
    end
  end
  log.debug "token selectivity \n #{sorted_hash_to_s(selectivity)} \n\n"

  false_positive_impact = {}
  tokens.keys.each{ |t| false_positive_impact[t] = tokens[t] * selectivity[t] }
  log.debug "false positive impact \n #{sorted_hash_to_s(false_positive_impact)} \n\n"

  product_blacklist = Set.new [ '.net_framework', 'iphone_os', 'nx-os',
    'unified_computing_system_infrastructure_and_unified_computing_system_software',
    'bouncycastle:legion-of-the-bouncy-castle-c%23-crytography-api', # should be renamed instead of blocked
  ]

  DB.transaction do

  DB.create_table!(:cve_match) do
    String :pkg_attr#, :primary_key => true
    String :product
    String :version
    String :CVE
  end

  products.each_pair do |product, versions|
    next if product_blacklist.include? product
    tk = product.scan(/(?:[a-zA-Z]+)|(?:\d+)/).select do |token|
      token.size != 1 and not(['the','and','in','on','of','for'].include? token)
    end

    pkgs =
      DistroPackage::Nix.packages.select do |pkg|
        score = tk.reduce(0) do |score, token|
          res = ((pkg.internal_name.include? token or pkg.name.include? token) ? 1 : 0)
          res *= ( selectivity[token]>20 ? 0.51 : 1 )
          score + res
        end
        ( score >= 1 or ( tk.size == 1 and score >= 0.3 ) )
      end.to_set

    versions.each do |version|
      if version =~ /^\d+\.\d+\.\d+\.\d+/ or version =~ /^\d+\.\d+\.\d+/ or version =~ /^\d+\.\d+/ or version =~ /^\d+/ 
        v = $&
        pkgs.each do |pkg|
          next if product == 'ack' and pkg.name != 'ack' and pkg.internal_name.start_with?( 'perlPackages.', 'python', 'emacs')
          next if product == 'perl' and pkg.internal_name.start_with? 'perlPackages.'
          next if product == 'python' and (pkg.internal_name =~ /^python\d\dPackages\./ or pkg.internal_name.start_with? 'pythonDocs.')
          if pkg.version =~ /^\d+\.\d+\.\d+\.\d+/ or pkg.version =~ /^\d+\.\d+\.\d+/ or pkg.version =~ /^\d+\.\d+/ or pkg.version =~ /^\d+/ 
            v2 = $&

          #if (pkg.version == v) or (pkg.version.start_with? v and not( ('0'..'9').include? pkg.version[v.size]))
            if v == v2
              fullname = "#{product}:#{version}"
              product_to_cve[fullname].each do |cve|
                DB[:cve_match] << {
                  :pkg_attr => pkg.internal_name,
                  :product => product,
                  :version => version,
                  :CVE => cve
                }
              end
              log.warn "match #{product_to_cve[fullname].inspect}: #{product}:#{version} = #{pkg.internal_name}/#{pkg.name}:#{pkg.version}"
            end
          end
        end
      end
    end
  end

  Reports::Timestamps.done(:cve_check)
  end

end
