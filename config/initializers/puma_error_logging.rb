require "puma/log_writer"

# Puma writes the errors it catches itself (malformed request, exception escaping the Rails middleware)
# straight to stderr, past Rails.logger and its scrubbing. Its request title carries the path, the query
# string and the client IP; its debug dump every header; an exception message may quote request data.
# Only the time, Puma's label and the exception class are written.
module PumaErrorLogging
  # Overrides public methods of Puma 8: re-check them when upgrading Puma.
  module ErrorLogger
    def title(options = {})
      [ Time.now, options[:text] ].compact.join(" ") + (options[:error] ? ": #{options[:error].class}" : "")
    end

    def debug(options = {})
      super(options.except(:req))
    end
  end

  # Its label names the peer address.
  module LogWriter
    def ssl_error(error, _ssl_socket)
      unknown_error(error, nil, "SSL error")
    end
  end
end

Puma::ErrorLogger.prepend(PumaErrorLogging::ErrorLogger)
Puma::LogWriter.prepend(PumaErrorLogging::LogWriter)
