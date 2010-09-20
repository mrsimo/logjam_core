require 'amqp'
require 'mq'
require 'json'
require 'set'

module Logjam

  class MongoImportBuffer

    def initialize(dbname, app, env)
      @app = app
      @env = env

      database  = Logjam.mongo.db(dbname)
      @totals   = Totals.ensure_indexes(database["totals"])
      @minutes  = Minutes.ensure_indexes(database["minutes"])
      @quants   = Quants.ensure_indexes(database["quants"])
      @requests = Requests.ensure_indexes(database["requests"])

      #     @hours = db["hours"]
      #     @hours.create_index([ ["page", Mongo::ASCENDING], ["hour", Mongo::ASCENDING] ])

      @import_threshold  = Logjam.import_threshold
      @generic_fields    = Requests::GENERIC_FIELDS
      @quantified_fields = Requests::QUANTIFIED_FIELDS
      @squared_fields    = Requests::SQUARED_FIELDS

      setup_buffers
    end

    def add(entry)
      host = entry[:host]
      severity = entry[:severity]
      page = entry[:page]
      page << "#unknown_method" unless page =~ /#/
      minute = entry[:minute]
      response_code = entry[:response_code]
      user_id = entry[:user_id]
      total_time = entry[:total_time]
      lines = entry.delete(:lines)

      # puts entry.to_yaml
      raise "no response code" if response_code.blank?

      fields = entry.stringify_keys
      fields.delete_if{|k,v| v==0 || @generic_fields.include?(k) }
      fields.keys.each{|k| fields[squared_field(k)] = (v=fields[k].to_f)*v}

      pmodule = "::"
      if page =~ /^(.+?)::/ || page =~ /^([^:#]+)#/
        pmodule << $1
        @modules << pmodule
      end

      increments = {"count" => 1}.merge!(fields)
      [page, "all_pages", pmodule].each do |p|
        increments.each do |f,v|
          (@minutes_buffer[[p,minute]] ||= Hash.new(0.0))[f] += v
        end
      end

      user_experience =
        if total_time >= 2000 || response_code == 500 then {"apdex.frustrated" => 1}
        elsif total_time < 100 then {"apdex.happy" => 1, "apdex.satisfied" => 1}
        elsif total_time < 500 then {"apdex.satisfied" => 1}
        elsif total_time < 2000 then {"apdex.tolerating" => 1}
        else raise "oops: #{tt.inspect}"
        end

      increments.merge!(user_experience)
      increments["response.#{response_code}"] = 1

      [page, "all_pages", pmodule].each do |p|
        increments.each do |f,v|
          (@totals_buffer[p] ||= Hash.new(0.0))[f] += v
        end
      end

      #     hour = minute / 60
      #     [page, "all_pages", pmodule].each do |p|
      #       increments.each do |f,v|
      #         (@hours_buffer[[p,hour]] ||= Hash.new(0))[f] += v
      #       end
      #     end

      @quantified_fields.each do |f|
        next unless x=fields[f]
        if f == "allocated_objects"
          kind = "m"
          d = 10000
        elsif f == "allocated_bytes"
          kind = "m"
          d = 100000
        else
          kind = "t"
          d = 100
        end
        x = ((x.floor/d).ceil+1)*d
        [page, "all_pages"].each do |p|
          (@quants_buffer[[p,kind,x]] ||= Hash.new(0.0))[f] += 1
        end
      end

      request = {
        "severity" => severity, "page" => page, "minute" => minute, "response_code" => response_code,
        "host" => host, "user_id" => user_id, "lines" => lines
      }.merge!(fields)

      @requests.insert(request) if interesting?(request)
    end

    def flush
      publish_totals
      flush_totals_buffer
      flush_minutes_buffer
      # flush_hours_buffer
      flush_quants_buffer
    end

    private

    def squared_field(f)
      @squared_fields[f] || raise("unknown field #{f}")
    end

    def interesting?(request)
      request["total_time"].to_i > @import_threshold ||
        request["heap_growth"].to_i > 0 ||
        request["response_code"].to_i == 500 ||
        request["severity"] > 1
    end

    def setup_buffers
      @quants_buffer = {}
      @totals_buffer = {}
      @minutes_buffer = {}
      # @hours_buffer = {}
      @modules = Set.new(%w(all_pages))
    end

    UPSERT_ONE = {:upsert => true, :multi => false}

    def flush_quants_buffer
      @quants_buffer.each do |(p,k,q),inc|
        @quants.update({"page" => p, "kind" => k, "quant" => q}, { '$inc' => inc }, UPSERT_ONE)
      end
      @quants_buffer.clear
    end

    def flush_minutes_buffer
      @minutes_buffer.each do |(p,m),inc|
        @minutes.update({"page" => p, "minute" => m}, { '$inc' => inc }, UPSERT_ONE)
      end
      @minutes_buffer.clear
    end

    #   def flush_hours_buffer
    #     @hours_buffer.each do |(p,h),inc|
    #       @hours.update({"page" => p, "hour" => h}, { '$inc' => inc }, UPSERT_ONE)
    #     end
    #     @hours_buffer.clear
    #   end

    def flush_totals_buffer
      @totals_buffer.each do |(p,inc)|
        @totals.update({"page" => p}, { '$inc' => inc }, UPSERT_ONE)
      end
      @totals_buffer.clear
    end

    def self.exchange(app, env)
      (@exchange||={})["#{app}-#{env}"] ||=
        begin
          channel = MQ.new(AMQP::connect(:host => "127.0.0.1"))
          channel.topic("logjam-performance-data-#{app}-#{env}")
        end
    end

    def exchange
      @exchange ||= self.class.exchange(@app, @env)
    end

    NO_REQUEST = {"count" => 0}

    def publish_totals
      # always publish something every second to the perf data exchange
      @modules.each { |p| publish(p, @totals_buffer[p] || NO_REQUEST) }
    end

    def publish(p, inc)
      exchange.publish(inc.to_json, :key => p.sub(/^::/,'').downcase)
    rescue
      $stderr.puts "could not publish performance data: #{$!}"
    end
  end
end
