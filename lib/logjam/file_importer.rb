require 'fileutils'
require 'logjam/eventmachine'
require 'amqp'
require 'oj'

module Logjam

  class FileImporter

    def initialize(config_name, logfile_name)
      @stream = Logjam.streams[config_name]
      @app = @stream.app
      @env = @stream.env
      requests_collection = Logjam.db(Date.today, @app, @env)["requests"]
      requests_collection.drop
      @importer = RequestProcessor.new(@stream, requests_collection)
      @io = logfile_io(logfile_name)
    end

    def process
      # @line_count = 0
      # @start_time = Time.now
      # @io.each_line do |line|
      #   @line_count += 1
      #   entry = Oj.load(line)
      #   @importer.add entry
      # end
      # elapsed = Time.now - @start_time
      # speed = @line_count / elapsed
      # printf "\nprocessed %d requests (%d/second)\n", @line_count, speed.to_i
      EM.run do
        @connection = EM.watch @io, SimpleGrep
        @connection.importer = @importer
        @connection.notify_readable = true
        trap("INT") { stop }
        @timer = EM.add_periodic_timer(1) do
          @importer.reset_state
        end
      end
    end

    def stop
      @connection.detach
      @io.close
      EM.stop_event_loop
    end

    private

    def logfile_io(logfile_name)
      cmd = logfile_name =~ /\.gz$/ ? "gzcat" : "cat"
      IO.popen("#{cmd} #{logfile_name}", "rb")
    end

    module SimpleGrep
      attr_reader :line_count
      attr_writer :importer
      def post_init
        @line_count = 0
        @start_time = Time.now
      end
      def unbind
        elapsed = Time.now - @start_time
        speed = @line_count / elapsed
        printf "\nprocessed %d requests (%d/second)\n", @line_count, speed.to_i
      end
      def notify_readable
        @line_count += 1
        line = @io.readline
        entry = JSON.parse(line)
        @importer.add entry
      rescue EOFError
        detach
        @io.close
        EM.stop_event_loop
      end
    end

  end
end
