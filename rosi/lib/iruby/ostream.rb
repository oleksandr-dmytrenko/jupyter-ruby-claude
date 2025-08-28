module IRuby
  class OStream
    # Provide IO-like behavior that some libraries probe on Ruby 3.3.x.
    # Keep implementations as no-ops to avoid interfering with IRuby's output pipeline.

    def closed?
      false
    end

    # No-op close; IRuby manages lifecycle separately.
    def close
      self
    end

    # No-op flush to satisfy IO API expectations.
    def flush
      self
    end

    # Streams are not TTYs in IRuby/Jupyter.
    def tty?
      false
    end
    alias isatty? tty?

    # Sync flag accessors (no effect, but avoids NoMethodError when probed).
    def sync
      @sync ||= false
    end

    def sync=(val)
      @sync = !!val
    end
  end
end
