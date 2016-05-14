require 'nixpkgs_monitor/distro_packages/base'
require 'json'

module NixPkgsMonitor module DistroPackages

  class Gentoo < NixPkgsMonitor::DistroPackages::Base

    attr_accessor :version_overlay, :version_upstream
    @cache_name = "gentoo"

    def version
      return version_upstream if version_upstream
      return version_overlay if version_overlay and not(version_overlay.end_with?('9999'))
      return @version
    end


    def serialize
      super.merge({:version_overlay => @version_overlay,
                   :version_upstream => @version_upstream})
    end


    def self.deserialize(val)
      pkg = super(val)
      pkg.version_overlay = val[:version_overlay]
      pkg.version_upstream = val[:version_upstream]
      return pkg
    end


    def self.generate_list
      gentoo_list = {}

      categories_json = http_agent.get('http://euscan.gentooexperimental.org/api/1.0/categories.json').body
      JSON.parse(categories_json)["categories"].each do |cat|
        puts cat["category"]
        packages_json = http_agent.get("http://euscan.gentooexperimental.org/api/1.0/packages/by-category/#{cat["category"]}.json").body
        JSON.parse(packages_json)["packages"].each do |pkg|
          name = pkg["name"]
          gentoo_list[name] = Gentoo.new(cat["category"] + '/' + name, name) unless gentoo_list[name]
          if pkg["last_version_gentoo"] and not(pkg["last_version_gentoo"]["version"].include? '9999')
            gentoo_list[name].version = pkg["last_version_gentoo"]["version"]
          end
          if pkg["last_version_overlay"] and not(pkg["last_version_overlay"]["version"].include? '9999')
            gentoo_list[name].version_overlay = pkg["last_version_overlay"]["version"]
          end
          if pkg["last_version_upstream"]
            gentoo_list[name].version_upstream = pkg["last_version_upstream"]["version"]
          end
        end
      end

      serialize_list(gentoo_list.values)
    end

  end

end end
