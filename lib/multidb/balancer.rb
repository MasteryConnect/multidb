module Multidb

  class Candidate
    def initialize(name, target)
      @name = name

      if target.is_a?(Hash)
        adapter = target[:adapter]
        begin
          require "active_record/connection_adapters/#{adapter}_adapter"
        rescue LoadError
          raise "Please install the #{adapter} adapter: `gem install activerecord-#{adapter}-adapter` (#{$!})"
        end
        if defined?(ActiveRecord::ConnectionAdapters::ConnectionSpecification)
          spec_class = ActiveRecord::ConnectionAdapters::ConnectionSpecification
        else
          spec_class = ActiveRecord::Base::ConnectionSpecification
        end

        spec =
          if ActiveRecord::VERSION::MAJOR >= 5
            # ActiveRecord 5.0.1 introduced `name` to initialize
            spec_class.new(name, target, "#{adapter}_connection")
          else
            spec_class.new(target, "#{adapter}_connection")
          end

          @connection_pool = ActiveRecord::ConnectionAdapters::ConnectionPool.new(spec)
          # Should we use query caching for this target?
          # Only applies to Multidb.use with a block
          @query_cache_enabled = target[:query_cache].present? ? target[:query_cache] : false
      else
        @connection_pool = target
      end
    end

    def connection(&block)
      if block_given?
        @connection_pool.with_connection(&block)
      else
        @connection_pool.connection
      end
    end

    attr_reader :connection_pool, :name, :query_cache_enabled
  end

  class Balancer

    def initialize(configuration)
      @candidates = {}.with_indifferent_access
      @default_configuration = configuration

      if @default_configuration

        append(@default_configuration.raw_configuration[:databases] || {})

        if @default_configuration.raw_configuration.include?(:fallback)
          @fallback = @default_configuration.raw_configuration[:fallback]
        elsif defined?(Rails)
          @fallback = %w(development test).include?(Rails.env)
        else
          @fallback = false
        end
        @default_candidate = Candidate.new('default', @default_configuration.default_pool)
        unless @candidates.include?(:default)
          @candidates[:default] = [@default_candidate]
        end
      end
    end

    def append(databases)
      databases.each_pair do |name, config|
        configs = config.is_a?(Array) ? config : [config]
        configs.each do |cfg|
          candidate = Candidate.new(name, @default_configuration.default_adapter.merge(cfg))
          @candidates[name] ||= []
          @candidates[name].push(candidate)
        end
      end
    end

    def disconnect!
      @candidates.values.flatten.each do |candidate|
        candidate.connection_pool.disconnect!
      end
    end

    def get(name, &block)
      candidates = @candidates[name]
      candidates ||= @fallback ? @candidates[:default] : []
      raise ArgumentError, "No such database connection '#{name}'" if candidates.empty?
      candidate = candidates.respond_to?(:sample) ?
        candidates.sample : candidates[rand(candidates.length)]
      block_given? ? yield(candidate) : candidate
    end

    def use(name, &block)
      result = nil
      get(name) do |candidate|
        if block_given?
          candidate.connection_pool.enable_query_cache! if candidate.query_cache_enabled
          candidate.connection do |connection|
            previous_configuration = Thread.current[:multidb]
            Thread.current[:multidb] = {
              connection: connection,
              connection_name: name
            }
            begin
              result = yield
              result = result.to_a if result.is_a?(ActiveRecord::Relation)
            ensure
              candidate.connection_pool.enable_query_cache! if candidate.query_cache_enabled
              Thread.current[:multidb] = previous_configuration
            end
            result
          end
        else
          Thread.current[:multidb] = {
            connection: candidate.connection,
            connection_name: name
          }
          result = candidate.connection
        end
      end
      result
    end

    def current_connection
      if Thread.current[:multidb]
        Thread.current[:multidb][:connection]
      else
        @default_candidate.connection
      end
    end

    def current_connection_name
      if Thread.current[:multidb]
        Thread.current[:multidb][:connection_name]
      else
        :default
      end
    end

    class << self
      delegate :use, :current_connection, :current_connection_name, :disconnect!, to: :balancer

      def use(name, &block)
        Multidb.balancer.use(name, &block)
      end

      def current_connection
        Multidb.balancer.current_connection
      end

      def current_connection_name
        Multidb.balancer.current_connection_name
      end

      def disconnect!
        Multidb.balancer.disconnect!
      end
    end

  end

end
