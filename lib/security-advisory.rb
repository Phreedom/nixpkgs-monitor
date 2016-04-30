require 'nokogiri'
require 'distro-package'
require 'uri'

module SecurityAdvisory

  class CVE
    attr_reader :id, :packages

    def self.load_from(file)
      result = []
      xml = Nokogiri::XML(File.read(file))

      xml.xpath('xmlns:nvd/xmlns:entry').each do |entry|
        #puts "loading #{entry[:id]}"
        packages = []
        entry.xpath('vuln:vulnerable-software-list').each do |list|

          list.xpath('vuln:product').each do |product|
            pname = product.inner_text
            unless parse_package(pname)
              puts "failed to parse #{pname} @ #{entry[:id]}"
            else
              packages << pname
            end
          end

        end
        result << new(entry[:id], packages)
      end

      return result
    end


    def self.update_names
      (-4..0).map { |offs| (Time.now.utc.year + offs).to_s } + ["Modified", "Recent"]
    end

    def self.fetch_updates
      update_names.each do |name|
          puts %x(curl -O https://nvd.nist.gov/feeds/xml/cve/nvdcve-2.0-#{name}.xml.gz)
          puts %x(zcat nvdcve-2.0-#{name}.xml.gz > nvdcve-2.0-#{name}.xml)
      end
    end

    def self.list
      @list ||= update_names.map {|n| load_from("nvdcve-2.0-#{n}.xml")}.reduce(:+)
    end


    def initialize(id, packages)
      @id = id
      @packages = packages
    end

    def self.parse_package(package)
      return nil unless %r{^cpe:/.:(?<supplier>[^:]*):(?<product>[^:]*):(?<version>[^:]*)} =~ package
      return [ URI.unescape(supplier), URI.unescape(product), URI.unescape(version) ]
    end

  end


  class GLSA
    attr_reader :id, :packages

    def self.update_list
    end

    def self.parse(file)
      glsa = Nokogiri::XML(File.read(file)).xpath('//glsa').first
      packages = []
      glsa.xpath('affected/package').each do |package|
        packages << package[:name].downcase
      end
      self.new('GLSA-' + glsa[:id], packages)
    end

    def initialize(id, packages)
      @id = id
      @packages = packages
    end


    def self.list
      unless @glsa_list
        @glsa_list = []
        Dir.entries('portage/metadata/glsa').each do |entry|
          glsa_name = 'portage/metadata/glsa/' + entry
          next unless File.file? glsa_name and entry.end_with? ".xml" and entry != 'index.xml' and entry =~ /201[01234]/
          @glsa_list << self.parse(glsa_name)
        end
      end

      return @glsa_list
    end


    def matching_nixpkgs
      return nil unless %r{(?<cat>[^/]+)/(?<name>[^/]+)} =~ packages[0]
      result  = DistroPackage::Nix.list[name]
      result  = DistroPackage::Nix.list['ruby-' + name] unless result
      result  = DistroPackage::Nix.list['python-' + name] unless result
      result  = DistroPackage::Nix.list['perl-' + name] unless result
      return result
    end

    def affected_nixpkgs
    end

  end


end