require "cgi"
require "json"
require "securerandom"

module BetterErrors
  # @private
  class ErrorPage
    def self.template_path(template_name)
      File.expand_path("../templates/#{template_name}.erb", __FILE__)
    end

    def self.template(template_name)
      Erubi::Engine.new(File.read(template_path(template_name)), escape: true)
    end

    attr_reader :exception, :env, :repls

    def initialize(exception, env)
      @exception = RaisedException.new(exception)
      @env = env
      @start_time = Time.now.to_f
      @repls = []
    end

    def id
      @id ||= SecureRandom.hex(8)
    end

    def render(template_name = "main", csrf_token = nil)
      binding.eval(self.class.template(template_name).src)
    rescue => e
      # Fix the backtrace, which doesn't identify the template that failed (within Better Errors).
      # We don't know the line number, so just injecting the template path has to be enough.
      e.backtrace.unshift "#{self.class.template_path(template_name)}:0"
      raise
    end

    def do_variables(opts)
      load_frame_from(opts)
      @var_start_time = Time.now.to_f
      { html: render("variable_info") }
    end

    def do_eval(opts)
      index = opts["index"].to_i
      code = opts["source"]

      unless (binding = backtrace_frames[index].frame_binding)
        return { error: "REPL unavailable in this stack frame" }
      end

      @repls[index] ||= REPL.provider.new(binding, exception)

      eval_and_respond(index, code)
    end

    def do_expand(opts)
      load_frame_from(opts)

      @frame.upperlines -= 5 if opts['direction'] == 'up'
      @frame.lowerlines += 5 if opts['direction'] == 'down'

      @var_start_time = Time.now.to_f
      { html: render("trace_info") }
    end

    def backtrace_frames
      exception.backtrace
    end

    def exception_type
      exception.type
    end

    def exception_message
      exception.message.strip.gsub(/(\r?\n\s*\r?\n)+/, "\n")
    end

    def exception_hint
      exception.hint
    end

    def active_support_actions
      return [] unless defined?(ActiveSupport::ActionableError)

      ActiveSupport::ActionableError.actions(exception.type)
    end

    def action_dispatch_action_endpoint
      return unless defined?(ActionDispatch::ActionableExceptions)

      ActionDispatch::ActionableExceptions.endpoint
    end

    def application_frames
      backtrace_frames.select(&:application?)
    end

    def first_frame
      application_frames.first || backtrace_frames.first
    end

    private

    def editor_url(frame)
      BetterErrors.editor.url(frame.filename, frame.line)
    end

    def rack_session
      env['rack.session']
    end

    def rails_params
      env['action_dispatch.request.parameters']
    end

    def uri_prefix
      env["SCRIPT_NAME"] || ""
    end

    def request_path
      env["PATH_INFO"]
    end

    def html_formatted_code_block(frame)
      CodeFormatter::HTML.new(frame.filename, frame.line, frame.upperlines,
                              frame.lowerlines).output
    end

    def text_formatted_code_block(frame)
      CodeFormatter::Text.new(frame.filename, frame.line).output
    end

    def text_heading(char, str)
      str + "\n" + char*str.size
    end

    def inspect_value(obj)
      if BetterErrors.ignored_classes.include? obj.class.name
        "<span class='unsupported'>(Instance of ignored class. "\
        "#{obj.class.name ? "Remove #{CGI.escapeHTML(obj.class.name)} from" : "Modify"}"\
        " BetterErrors.ignored_classes if you need to see it.)</span>"
      else
        InspectableValue.new(obj).to_html
      end
    rescue BetterErrors::ValueLargerThanConfiguredMaximum
      "<span class='unsupported'>(Object too large. "\
        "#{obj.class.name ? "Modify #{CGI.escapeHTML(obj.class.name)}#inspect or a" : "A"}"\
        "djust BetterErrors.maximum_variable_inspect_size if you need to see it.)</span>"
    rescue Exception => e
      "<span class='unsupported'>(exception #{CGI.escapeHTML(e.class.to_s)} was raised in inspect)</span>"
    end

    def eval_and_respond(index, code)
      result, prompt, prefilled_input = @repls[index].send_input(code)

      {
        highlighted_input: CodeRay.scan(code, :ruby).div(wrap: nil),
        prefilled_input:   prefilled_input,
        prompt:            prompt,
        result:            result
      }
    end

    def load_frame_from(opts)
      index = opts["index"].to_i
      @frame = backtrace_frames[index]
    end
  end
end
