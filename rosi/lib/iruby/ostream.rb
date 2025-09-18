module IRuby
  class OStream
    def initialize
      @closed = false
    end

    def closed?
      @closed
    end

    def close
      @closed = true
    end

    def write(data)
      return 0 if @closed
      
      # Write to stdout which IRuby will capture
      $stdout.write(data)
      $stdout.flush
      data.length
    end

    def puts(*args)
      return if @closed
      
      if args.empty?
        $stdout.puts
      else
        args.each { |arg| $stdout.puts(arg) }
      end
      $stdout.flush
    end

    def print(*args)
      return if @closed
      
      args.each { |arg| $stdout.print(arg) }
      $stdout.flush
    end

    def flush
      $stdout.flush unless @closed
    end

    def <<(data)
      write(data)
      self
    end
  end
end
