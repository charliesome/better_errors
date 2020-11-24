module BetterErrors
  # @private
  class CodeFormatter
    require "better_errors/code_formatter/html"
    require "better_errors/code_formatter/text"

    FILE_TYPES = {
      ".rb"   => :ruby,
      ""      => :ruby,
      ".html" => :html,
      ".erb"  => :erb,
      ".haml" => :haml
    }

    attr_reader :filename, :line, :upperlines, :lowerlines

    def initialize(filename, line, upperlines = nil, lowerlines = nil)
      @filename   = filename
      @line       = line
      @upperlines = upperlines || line - 5
      @lowerlines = lowerlines || line + 5

      @upperlines = 1 if begin_of_file_reached?
      @lowerlines = source_lines_count if end_of_file_reached?
    end

    def output
      formatted_code
    rescue Errno::ENOENT, Errno::EINVAL
      source_unavailable
    end

    def formatted_code
      formatted_lines.join
    end

    def coderay_scanner
      ext = File.extname(filename)
      FILE_TYPES[ext] || :text
    end

    def each_line_of(lines, &blk)
      line_range.zip(lines).map { |current_line, str|
        yield (current_line == line), current_line, str
      }
    end

    def highlighted_lines
      CodeRay.scan(context_lines.join, coderay_scanner).div(wrap: nil).lines
    end

    def context_lines
      range = line_range
      source_lines[(range.begin - 1)..(range.end - 1)] or raise Errno::EINVAL
    end

    def source_lines
      @source_lines ||= File.readlines(filename)
    end

    def line_range
      upperlines..lowerlines
    end

    def begin_of_file_reached?
      upperlines <= 1
    end

    def source_lines_count
      @source_lines_count ||= source_lines.count
    rescue Errno::ENOENT
      0
    end

    def end_of_file_reached?
      lowerlines >= source_lines_count
    end
  end
end
