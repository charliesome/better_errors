module BetterErrors
  # @private
  class CodeFormatter::HTML < CodeFormatter
    def source_unavailable
      "<p class='unavailable'>Source is not available</p>"
    end

    def formatted_lines
      each_line_of(highlighted_lines) { |highlight, current_line, str|
        class_name = highlight ? "highlight" : ""
        sprintf '<pre class="%s">%s</pre>', class_name, str
      }
    end

    def formatted_nums
      each_line_of(highlighted_lines) { |highlight, current_line, str|
        class_name = highlight ? "highlight" : ""
        sprintf '<span class="%s">%5d</span>', class_name, current_line
      }
    end

    def expander_icon
      <<-HEREDOC
<svg aria-hidden="true" class="octicon octicon-unfold"
     height="16" version="1.1" viewBox="0 0 14 16" width="14">
  <path fill-rule="evenodd" d="M11.5 7.5L14 10c0 .55-.45 1-1
    1H9v-1h3.5l-2-2h-7l-2 2H5v1H1c-.55 0-1-.45-1-1l2.5-2.5L0
    5c0-.55.45-1 1-1h4v1H1.5l2 2h7l2-2H9V4h4c.55 0 1 .45 1
    1l-2.5 2.5zM6 6h2V3h2L7 0 4 3h2v3zm2 3H6v3H4l3 3 3-3H8V9z">
  </path>
</svg>
      HEREDOC
    end

    def formatted_code
      code = ''

      unless begin_of_file_reached?
        code << '<span class="expander">' \
                  "<a href='#' data-direction='up' title='Expand'>" \
                    "#{expander_icon}" \
                  "</a>" \
                '</span>'
      end

      code << "<div class='code_linenums'>#{formatted_nums.join}</div>"
      code << "<div class='code'>#{super}</div>"

      unless end_of_file_reached?
        code << '<span class="expander">' \
                  "<a href='#' data-direction='down' title='Expand'>" \
                    "#{expander_icon}" \
                  "</a>" \
                '</span>'
      end

      code
    end
  end
end
