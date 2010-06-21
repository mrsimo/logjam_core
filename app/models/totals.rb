class Totals
  attr_reader :resources, :pattern, :pages
  def initialize(resources, pattern='')
    @database = MONGODB.db("logjam")
    @collection = @database["totals"]
    @resources = resources
    @pattern = pattern
    @sum = {}
    @avg = {}
    @sum_sq = {}
    @stddev = {}
  end

  def the_pages
    @pages ||= compute
  end

  def page_names
    @page_names ||=
      @collection.find({},:fields =>["page"]).map{|p| p["page"]}.delete_if{|p| p == "all_pages"}
  end

  def pages(options)
    order = options[:order] || :sum
    limit = options[:limit]
    if limit
      the_pages.sort_by{|r| -r[order]}[0..limit-1]
    else
      the_pages.sort_by{|r| -r[order]}
    end
  end

  def count
    @count ||= the_pages.inject(0){|n,p| n += p[:number_of_requests]}
  end

  def sum(resource)
    field = "#{resource}_sum"
    @sum[resource] ||= the_pages.inject(0.0){|n,p| n += p[field]}
  end

  def sum_sq(resource)
    field = "#{resource}_sum_sq"
    @sum_sq[resource] ||= the_pages.inject(0.0){|n,p| n += p[field]}
  end

  def avg(resource)
    @avg[resource] ||= sum(resource)/count rescue 0.0
  end

  def stddev(resource)
    (count == 1) ? 0.0 : Math.sqrt((sum_sq(resource) - count*avg(resource)*avg(resource))/(count-1).to_f)
  end

  def selector
    case
    when pattern == '' then {:page => {'$ne' => "all_pages"}}
    when page_names.include?(pattern) then {:page => pattern}
    when page_names.grep(/^#{pattern}/).size > 0 then {:page => /^#{pattern}/}
    else {:page => /#{pattern}/}
    end
  end

  protected

  def compute
    result = []
    n = 0
    sq_fields = @resources.map{|r| "#{r}_sq"}
    all_fields = ["page", "count"] + resources + sq_fields
    access_time = Benchmark.realtime do
      @collection.find(selector, {:fields => all_fields}).each do |row|
        n += 1
        count = row["count"]
        result_row = {"page" => row["page"], "number_of_requests" => count}
        @resources.each do |r|
          sum = row[r] || 0
          sum_sq = row["#{r}_sq"] || 0
          avg = sum.to_f/count
          std_dev = (count == 1) ? 0.0 : Math.sqrt((sum_sq - count*avg*avg)/(count-1).to_f)
          result_row["#{r}_sum"] = sum
          result_row["#{r}_sum_sq"] = sum_sq
          result_row["#{r}_avg"] = avg
          result_row["#{r}_stddev"] = std_dev
        end
        result << result_row.with_indifferent_access
      end
    end
    # logger.debug result.inspect
    logger.debug "MONGO totals #{n} records, size #{result.size}, #{"%.5f" % (access_time)} seconds}"
    result
  end

  def logger
    self.class.logger
  end

  def self.logger
    Rails.logger
  end
end