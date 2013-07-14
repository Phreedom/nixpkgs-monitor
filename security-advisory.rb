require 'nokogiri'
require 'distro-package'

module SecurityAdvisory

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