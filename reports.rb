module Reports

  # set
  class Timestamps

    def self.done(action, message = nil)
      DB.transaction do
        DB.create_table?(:timestamps) do
          String :action, :unique => true, :primary_key => true
          Time :timestamp
          String :message
        end

        if 1 != DB[:timestamps].where(:action => action.to_s).update(:timestamp => Time.now, :message => message)
          DB[:timestamps] << { :action => action.to_s, :timestamp => Time.now, :message => message }
        end
      end
    end

    def self.all
      DB[:timestamps].all
    end
  end


  class Logs

    def initialize(logtype, clear_log = true)
      @logtype = logtype
      clear! if clear_log
      DB.create_table?(@logtype) do
        String :pkg_attr, :unique => true, :primary_key => true
      end
    end

    def pkg(pkg_attr)
      DB.transaction do
        unless DB[@logtype][:pkg_attr => pkg_attr]
          DB[@logtype] << { :pkg_attr => pkg_attr }
        end
      end
    end

    def clear!
      DB.transaction do
        DB[@logtype].delete if DB.table_exists?(@logtype)
      end
    end

  end

end