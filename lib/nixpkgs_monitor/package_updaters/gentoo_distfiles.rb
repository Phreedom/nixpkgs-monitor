require 'nixpkgs_monitor/package_updaters/base'

require 'nixpkgs_monitor/package_updaters/repository/cpan'
require 'nixpkgs_monitor/package_updaters/repository/hackage'
require 'nixpkgs_monitor/package_updaters/repository/pypi'
require 'nixpkgs_monitor/package_updaters/repository/rubygems'

module NixPkgsMonitor module PackageUpdaters

  class GentooDistfiles < NixPkgsMonitor::PackageUpdaters::Base

    def self.covers?(pkg)
      return false if Repository::CPAN.covers?(pkg) or Repository::Pypi.covers?(pkg) or
                      Repository::Rubygems.covers?(pkg) or Repository::Hackage.covers?(pkg)
      (package_name, file_version) = parse_tarball_from_url(pkg.url)

      package_name and file_version and distfiles[package_name] and
      usable_version?(pkg.version) and usable_version?(file_version)
    end

    def self.distfiles
      unless @distfiles
        @distfiles = Hash.new{|h,k| h[k] = Array.new }
        files = http_agent.get('http://distfiles.gentoo.org/distfiles/').links.map(&:href)
        files.each do |tarball|
          (name, version) = parse_tarball_name(tarball)
          if name and name != "v"
            name = name.downcase
            version = version.downcase
            unless version.include? 'patch' or version.include? 'diff'
              @distfiles[name] << version
            end
          end
        end
      end
      @distfiles
    end


    def self.newest_versions_of(pkg)
      return nil unless covers?(pkg)
      new_tarball_versions(pkg, distfiles)
    end

  end

end end
