require 'nokogiri'
require 'package_updaters/base'

module PackageUpdaters
  module Repository

    # FIXME: nixpkgs has lots of urls which don't use mirror and instead have direct links :(
    # handles packages hosted at SourceForge
    class SF < PackageUpdaters::Base

      def self.tarballs
        @tarballs ||= Hash.new do |h, sf_project|
          tarballs = Hash.new{|h,k| h[k] = Array.new }

          begin
            data = http_agent.get("http://sourceforge.net/projects/#{sf_project}/rss").body
            Nokogiri.XML(data).xpath('rss/channel/item/title').each do |v|
              next if v.inner_text.end_with?('.asc', '.exe', '.dmg', '.sig', '.sha1', '.patch', '.patch.gz', '.patch.bz2', '.diff', '.diff.bz2', '.xdelta')
              (name, version) = parse_tarball_from_url(v.inner_text)
              tarballs[name] << version if name and version
            end
          rescue Net::HTTPForbidden, Mechanize::ResponseCodeError
          end

          h[sf_project] = tarballs
        end
      end

      def self.covers?(pkg)
        pkg.url =~ %r{^mirror://sourceforge/(?:project/)?([^/]+).*?/([^/]+)$} and usable_version?(pkg.version)
      end

      def self.newest_versions_of(pkg)
        return nil unless pkg.url
        return nil unless %r{^mirror://sourceforge/(?:project/)?(?<sf_project>[^/]+).*?/([^/]+)$} =~ pkg.url
        return new_tarball_versions(pkg, tarballs[sf_project])
      end

    end

  end
end
