require "database_cleaner/generic/truncation"
require 'database_cleaner/data_mapper/base'

module DataMapper
  module Adapters

    class DataObjectsAdapter

      def storage_names(repository = :default)
        raise NotImplementedError
      end

      def truncate_tables(table_names)
        table_names.each do |table_name|
          truncate_table table_name
        end
      end

    end

    class PostgresAdapter < DataObjectsAdapter

      # taken from http://github.com/godfat/dm-mapping/tree/master
      def storage_names(repository = :default)
        sql = <<-SQL
          SELECT table_name FROM "information_schema"."tables"
          WHERE table_schema = current_schema() and table_type = 'BASE TABLE'
        SQL
        query(sql)
      end

      def truncate_table(table_name)
        execute("TRUNCATE TABLE #{quote_table_name(table_name)} RESTART IDENTITY CASCADE;")
      end

      # override to use a single statement
      def truncate_tables(table_names)
        quoted_names = table_names.collect { |n| quote_table_name(n) }.join(', ')
        execute("TRUNCATE TABLE #{quoted_names} RESTART IDENTITY;")
      end

      def supports_disable_referential_integrity?
        version = select("SHOW server_version")[0][0].split('.')
        (version[0].to_i >= 8 && version[1].to_i >= 1) ? true : false
      rescue
        return false
      end

      def disable_referential_integrity(repository = :default)
        if supports_disable_referential_integrity? then
          execute(storage_names(repository).collect do |name|
            "ALTER TABLE #{quote_table_name(name)} DISABLE TRIGGER ALL"
          end.join(";"))
        end
        yield
      ensure
        if supports_disable_referential_integrity? then
          execute(storage_names(repository).collect do |name|
            "ALTER TABLE #{quote_table_name(name)} ENABLE TRIGGER ALL"
          end.join(";"))
        end
      end

    end

  end
end


module DatabaseCleaner
  module DataMapper
    class Truncation
      include ::DatabaseCleaner::DataMapper::Base
      include ::DatabaseCleaner::Generic::Truncation

      def clean(repository = self.db)
        adapter = ::DataMapper.repository(repository).adapter
        adapter.disable_referential_integrity do
          adapter.truncate_tables(tables_to_truncate(repository))
        end
      end

      private

      def tables_to_truncate(repository = self.db)
        (@only || ::DataMapper.repository(repository).adapter.storage_names(repository)) - @tables_to_exclude
      end

      # overwritten
      def migration_storage_names
        %w[migration_info]
      end

    end
  end
end
