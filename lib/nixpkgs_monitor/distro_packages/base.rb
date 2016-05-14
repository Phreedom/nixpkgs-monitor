require 'mechanize'

module NixPkgsMonitor module DistroPackages

  # Generic distro package
  class Base

    attr_accessor :internal_name, :name, :version, :url, :revision

    def initialize(internal_name, name = internal_name, version = '0', url = nil, revision = nil )
      @internal_name = internal_name
      @name = name
      @version = version
      @url = url
      @revision = revision
    end


    def serialize
      {
        :internal_name =>@internal_name,
        :name => @name,
        :version => @version,
        :url => @url,
        :revision => @revision
      }
    end


    def self.deserialize(val)
      new(val[:internal_name], val[:name], val[:version], val[:url], val[:revision])
    end


    def self.table_name
      "packages_#{@cache_name}".to_sym
    end


    def self.load_from_db(db)
      if DB.table_exists?(table_name)
        DB[table_name].each do |record|
          package = deserialize(record)
          @packages << package
          @list[package.name.downcase] = package
          @by_internal_name[package.internal_name] = package
        end
      else
        STDERR.puts "#{table_name} doesn't exist"
      end
    end


    def self.list
      unless @list
        @list = {}
        @by_internal_name = {}
        @packages = []

        load_from_db(DB)
      end

      return @list
    end


    def self.refresh
      @list = nil
      @by_internal_name = nil
      @packages = nil
    end


    def self.packages
      list unless @packages
      @packages
    end


    def self.by_internal_name
      list unless @by_internal_name
      @by_internal_name
    end


    def self.serialize_to_db(db, list)
      db[table_name].delete
      list.each do |package|
        db[table_name] << package.serialize
      end
    end


    def self.serialize_list(list)
      DB.transaction do
        serialize_to_db(DB, list)
      end
    end


    def self.http_agent
      agent = Mechanize.new
      agent.user_agent = 'NixPkgs software update checker'
      return agent
    end

  end

end end