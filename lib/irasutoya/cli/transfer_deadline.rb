# frozen_string_literal: true

module Irasutoya
  module Cli
    class TransferDeadline
      def initialize
        @lock = Mutex.new
      end

      def run(seconds, error_class, message)
        worker = Thread.new do
          Thread.current.report_on_exception = false
          yield
        end
        return worker.value if worker.join(seconds)

        raise error_class, message
      ensure
        cancel(worker) if worker&.alive?
      end

      def with_connection(http)
        @lock.synchronize { @http = http }
        yield http
      ensure
        @lock.synchronize { @http = nil }
      end

      private

      def cancel(worker)
        @lock.synchronize do
          if @http
            worker.kill
            # Closing the socket unblocks Net::HTTP's chunk terminator read during unwinding.
            close_connection
          else
            # Net::HTTP closes the socket in its connection error handler.
            worker.raise(IOError, 'Transfer cancelled')
          end
        end
        worker.join
      rescue StandardError
        # Socket errors raised by the cancelled request must preserve the deadline error.
      end

      def close_connection
        @http.finish if @http&.started?
      rescue IOError
        # The request may have closed the connection as the deadline expired.
      end
    end
  end
end
