require 'date'
require 'oj'

module Logjam

  class ZMQImporter

    include LogjamAgent::Util
    include Helpers
    include ReparentingTimer

    def initialize(stream)
      @stream       = stream
      @application  = @stream.app
      @environment  = @stream.env
      @port         = @stream.importer.port
      @context      = EM::ZeroMQ::Context.new(1)
      @request_processor = RequestProcessorServer.new(@stream, @context)
      @event_processor = EventProcessor.new(@stream)
      @capture_file = File.open("#{Rails.root}/capture-#{$$}.log", "w") if ENV['LOGJAM_CAPTURE']
    end

    def process
      setup_connection
      trap_signals
      shutdown_if_reparented_to_root_process_or_heap_insanity_detected
    end

    private

    def trap_signals
      trap("CHLD", "DEFAULT")
      trap("EXIT", "DEFAULT")
      trap("INT")  { }
      trap("TERM") { shutdown }
    end

    def setup_connection
      @socket = @context.socket(ZMQ::PULL)
      @socket.setsockopt(ZMQ::LINGER, 500)
      @socket.setsockopt(ZMQ::RCVHWM, 5000)
      rc = @socket.bind("tcp://#{Logjam.bind_ip}:#{@port}")
      unless ZMQ::Util.resultcode_ok? rc
        log_error("Could not bind to socket %s:%d: %s (%d)" % [Logjam.bind_ip, @port, ZMQ::Util.error_string, ZMQ::Util.errno])
      end
      @socket.on(:message) do |*parts|
        stream, key, msg, _info = parts.map(&:copy_out_string)
        parts.each(&:close)
        # if _info
        #   sent, sequence = unpack_info(_info)
        # end
        # log_info "#{stream}:#{key}:#{msg}:#{sent.iso8601(3)}:#{sequence}"
        begin
          case key
          when /^logs/
            process_request(msg)
          when /^events/
            process_event(msg)
          else
            log_error "unkwown message key:#{key} for stream:#{stream}"
          end
        rescue => e
          log_error "error during request processing: #{e.class}(#{e})"
        end
      end
    end

    def shutdown
      stop_reparenting_timer
      log_info "shutting down zmq importer"
      @socket.unbind
      log_info "stopping processor"
      @request_processor.stop
      EM.stop
      # exit immediately to avoid: Assertion failed: ok (mailbox.cpp:79)
      log_info "exiting zmq_worker"
      exit!(0)
    end

    def requests_subscription_key
      # TODO: should env really be part of the subscription key?
      ["logs", @application, @environment].compact.join('.')
    end

    def events_subscription_key
      # TODO: should env really be part of the subscription key?
      ["events", @application, @environment].compact.join('.')
    end

    def process_request(msg)
      # log_info "processing request: #{msg}"
      (c = @capture_file) && (c.puts msg)
      request = Oj.load(msg, :mode => :compat)
      @request_processor.process(request)
    end

    def process_event(msg)
      event = Oj.load(msg, :mode => :compat)
      @event_processor.process(event)
    end
  end
end
