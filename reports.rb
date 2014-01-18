module Reports

  # set
  class Timestamps

    def self.done(action)
      DB.transaction do
        DB.create_table?(:timestamps) do
          String :action, :unique => true, :primary_key => true
          Time :timestamp
        end

        if 1 != DB[:timestamps].where(:action => action.to_s).update(:timestamp => Time.now)
          DB[:timestamps] << { :action => action.to_s, :timestamp => Time.now }
        end
      end
    end

    def self.all
      DB[:timestamps].select_hash(:action, :timestamp)
    end
  end

end