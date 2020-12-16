require "fiber"
require "pry"

module BetterErrors
  module REPL
    class Pry
      class Input
        def readline
          Fiber.yield
        end
      end

      class Output
        def initialize
          @buffer = ""
        end

        def puts(*args)
          args.each do |arg|
            @buffer << "#{arg.chomp}\n"
          end
        end

        def tty?
          false
        end

        def read_buffer
          @buffer
        ensure
          @buffer = ""
        end

        def print(*args)
          @buffer << args.join(' ')
        end
      end

      def initialize(binding, exception)
        @input_queue = Queue.new
        @output_queue = Queue.new
        @input = BetterErrors::REPL::Pry::Input.new
        @output = BetterErrors::REPL::Pry::Output.new
        @thread = Thread.new do
          Thread.current.abort_on_exception = true
          @fiber = Fiber.new do
            @pry.repl binding
          end
          @pry = ::Pry.new input: @input, output: @output
          @pry.hooks.clear_all if defined?(@pry.hooks.clear_all)
          store_last_exception exception
          @fiber.resume

          loop do
            command = @input_queue.shift
            break if command == :stop
            local ::Pry.config, color: false, pager: false do
              @fiber.resume "#{command}\n"
            end
            # NOTE: indent_level here is not what we seem to expect it to be ¯\_(ツ)_/¯
            indent_level = @pry.instance_variable_get(:@indent).indent_level
            @output_queue << [@output.read_buffer, *prompt(indent_level)]
          end
        end
      end

      def stop
        @input_queue << :stop
        @thread.join
      end

      def store_last_exception(exception)
        return unless defined? ::Pry::LastException
        @pry.instance_variable_set(:@last_exception, ::Pry::LastException.new(exception.exception))
      end

      def send_input(str)
        @input_queue << str
        @output_queue.shift
      end

    private

      def prompt(indent_level)
        if indent_level.empty?
          [">>", ""]
        else
          ["..", indent_level]
        end
      end

      def local(obj, attrs)
        old_attrs = {}
        attrs.each do |k, v|
          old_attrs[k] = obj.send k
          obj.send "#{k}=", v
        end
        yield
      ensure
        old_attrs.each do |k, v|
          obj.send "#{k}=", v
        end
      end
    end
  end
end
