module Logjam

  class Quants < MongoModel

    def self.ensure_indexes(collection)
      ms = Benchmark.ms do
        fields = [ ["page", Mongo::ASCENDING], ["kind", Mongo::ASCENDING], ["quant", Mongo::ASCENDING] ]
        collection.create_index(fields, :background => true)
      end
      logger.debug "MONGO Quants Indexes Creation: #{"%.1f" % (ms)} ms"
      collection
    end

    def initialize(db, resources, pattern, kind)
      super(db, "quants")
      @pattern = pattern
      @pattern = "all_pages" if @pattern.blank? || @pattern == '::'
      @pattern = Regexp.new(/#{@pattern}/) unless @pattern == "all_pages"
      @kind = kind
      @resources = resources
      compute
    end

    def quants(resource)
      @quants[resource]
    end

    def compute
      selector = {:page => @pattern, :kind => @kind}
      fields = {:fields => ["quant"].concat(@resources)}
      query = "Quants.find(#{selector.inspect},#{fields.inspect})"
      rows = with_conditional_caching(query) do |payload|
        rs = []
        @collection.find(selector, fields.clone).each do |row|
          row.delete("_id")
          rs << row
        end
        payload[:rows] = rs.size
        rs
      end

      quants = @quants = {}
      while row = rows.shift
        quant = row["quant"]
        @resources.each do |f|
          if (v = row[f].to_i) > 0
            (quants[f] ||= Hash.new(0))[quant] += v
          end
        end
      end

      # logger.debug("QUANTS(#{@pattern.inspect}): #{@quants.inspect}")
    end

  end

end
