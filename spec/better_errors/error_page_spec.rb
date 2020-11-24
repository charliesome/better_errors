require "spec_helper"

class ErrorPageTestIgnoredClass; end

module BetterErrors
  describe ErrorPage do
    # It's necessary to use HTML matchers here that are specific as possible.
    # This is because if there's an exception within this file, the lines of code will be reflected in the
    # generated HTML, so any strings being matched against the HTML content will be there if they're within 5
    # lines of code of the exception that was raised.
    
    let!(:exception) { raise ZeroDivisionError, "you divided by zero you silly goose!" rescue $! }

    let(:error_page) { ErrorPage.new exception, { "PATH_INFO" => "/some/path" } }

    let(:response) { error_page.render }

    let(:exception_binding) {
      local_a = :value_for_local_a
      local_b = :value_for_local_b

      @inst_c = :value_for_inst_c
      @inst_d = :value_for_inst_d

      binding
    }

    it "includes the error message" do
      expect(response).to have_tag('.exception p', text: /you divided by zero you silly goose!/)
    end

    it "includes the request path" do
      expect(response).to have_tag('.exception h2', %r{/some/path})
    end

    it "includes the exception class" do
      expect(response).to have_tag('.exception h2', /ZeroDivisionError/)
    end

    context 'when ActiveSupport::ActionableError is available' do
      before do
        skip "ActiveSupport missing on this platform" unless Object.constants.include?(:ActiveSupport)
        skip "ActionableError missing on this platform" unless ActiveSupport.constants.include?(:ActionableError)
      end

      context 'when ActiveSupport provides one or more actions for this error type' do
        let(:exception_class) {
          Class.new(StandardError) do
            include ActiveSupport::ActionableError

            action "Do a thing" do
              puts "Did a thing"
            end
          end
        }
        let(:exception) { exception_binding.eval("raise exception_class") rescue $! }

        it "includes a fix-action form for each action" do
          expect(response).to have_tag('.fix-actions') do
            with_tag('form.button_to')
            with_tag('form.button_to input[type=submit][value="Do a thing"]')
          end
        end
      end

      context 'when ActiveSupport does not provide any actions for this error type' do
        let(:exception_class) {
          Class.new(StandardError)
        }
        let(:exception) { exception_binding.eval("raise exception_class") rescue $! }

        it "does not include a fix-action form" do
          expect(response).not_to have_tag('.fix-actions')
        end
      end
    end

    context "variable inspection" do
      let(:html) { error_page.do_variables("index" => 0)[:html] }
      let(:exception) { exception_binding.eval("raise") rescue $! }

      it 'includes an editor link for the full path of the current frame' do
        expect(html).to have_tag('.location .filename') do
          with_tag('a[href*="better_errors"]')
        end
      end

      context 'when BETTER_ERRORS_INSIDE_FRAME is set in the environment' do
        before do
          ENV['BETTER_ERRORS_INSIDE_FRAME'] = '1'
        end
        after do
          ENV['BETTER_ERRORS_INSIDE_FRAME'] = nil
        end

        it 'includes an editor link with target=_blank' do
          expect(html).to have_tag('.location .filename') do
            with_tag('a[href*="better_errors"][target="_blank"]')
          end
        end
      end

      context 'when BETTER_ERRORS_INSIDE_FRAME is not set in the environment' do
        it 'includes an editor link without target=_blank' do
          expect(html).to have_tag('.location .filename') do
            with_tag('a[href*="better_errors"]:not([target="_blank"])')
          end
        end
      end

      context "when binding_of_caller is loaded" do
        before do
          skip "binding_of_caller is not loaded" unless BetterErrors.binding_of_caller_available?
        end

        it "shows local variables" do
          expect(html).to have_tag('div.variables tr') do
            with_tag('td.name', text: 'local_a')
            with_tag('pre', text: ':value_for_local_a')
          end
          expect(html).to have_tag('div.variables tr') do
            with_tag('td.name', text: 'local_b')
            with_tag('pre', text: ':value_for_local_b')
          end
        end

        it "shows instance variables" do
          expect(html).to have_tag('div.variables tr') do
            with_tag('td.name', text: '@inst_c')
            with_tag('pre', text: ':value_for_inst_c')
          end
          expect(html).to have_tag('div.variables tr') do
            with_tag('td.name', text: '@inst_d')
            with_tag('pre', text: ':value_for_inst_d')
          end
        end

        context 'when ignored_classes includes the class name of a local variable' do
          before do
            allow(BetterErrors).to receive(:ignored_classes).and_return(['ErrorPageTestIgnoredClass'])
          end

          let(:exception_binding) {
            local_a = :value_for_local_a
            local_b = ErrorPageTestIgnoredClass.new

            @inst_c = :value_for_inst_c
            @inst_d = ErrorPageTestIgnoredClass.new

            binding
          }

          it "does not include that value" do
            expect(html).to have_tag('div.variables tr') do
              with_tag('td.name', text: 'local_a')
              with_tag('pre', text: ':value_for_local_a')
            end
            expect(html).to have_tag('div.variables tr') do
              with_tag('td.name', text: 'local_b')
              with_tag('.unsupported', text: /Instance of ignored class/)
              with_tag('.unsupported', text: /BetterErrors\.ignored_classes/)
            end
            expect(html).to have_tag('div.variables tr') do
              with_tag('td.name', text: '@inst_c')
              with_tag('pre', text: ':value_for_inst_c')
            end
            expect(html).to have_tag('div.variables tr') do
              with_tag('td.name', text: '@inst_d')
              with_tag('.unsupported', text: /Instance of ignored class/)
              with_tag('.unsupported', text: /BetterErrors\.ignored_classes/)
            end
          end
        end

        it "does not show filtered variables" do
          allow(BetterErrors).to receive(:ignored_instance_variables).and_return([:@inst_d])
          expect(html).to have_tag('div.variables tr') do
            with_tag('td.name', text: '@inst_c')
            with_tag('pre', text: ':value_for_inst_c')
          end
          expect(html).not_to have_tag('div.variables td.name', text: '@inst_d')
        end

        context 'when maximum_variable_inspect_size is set' do
          before do
            BetterErrors.maximum_variable_inspect_size = 1010
          end

          context 'on a platform with ObjectSpace' do
            before do
              skip "Missing on this platform" unless Object.constants.include?(:ObjectSpace)
            end

            context 'with a variable that is smaller than maximum_variable_inspect_size' do
              let(:exception_binding) {
                @small = content

                binding
              }
              let(:content) { 'A' * 480 }

              it "shows the variable content" do
                expect(html).to have_tag('div.variables', text: %r{#{content}})
              end
            end

            context 'with a variable that is larger than maximum_variable_inspect_size' do
              context 'but has an #inspect that returns a smaller value' do
                let(:exception_binding) {
                  @big = content

                  binding
                }
                let(:content) {
                  class ExtremelyLargeInspectableTestValue
                    def initialize
                      @a = 'A' * 1101
                    end
                    def inspect
                      "shortval"
                    end
                  end
                  ExtremelyLargeInspectableTestValue.new
                }

                it "shows the variable content" do
                  expect(html).to have_tag('div.variables', text: /shortval/)
                end
              end
              context 'and does not implement #inspect' do
                let(:exception_binding) {
                  @big = content

                  binding
                }
                let(:content) { 'A' * 1101 }

                it "includes an indication that the variable was too large" do
                  expect(html).not_to have_tag('div.variables', text: %r{#{content}})
                  expect(html).to have_tag('div.variables', text: /Object too large/)
                end
              end

              context "when the variable's class is anonymous" do
                let(:exception_binding) {
                  @big_anonymous = Class.new do
                    def initialize
                      @content = 'A' * 1101
                    end
                  end.new

                  binding
                }

                it "does not attempt to show the class name" do
                  expect(html).to have_tag('div.variables tr') do
                    with_tag('td.name', text: '@big_anonymous')
                    with_tag('.unsupported', text: /Object too large/)
                    with_tag('.unsupported', text: /Adjust BetterErrors.maximum_variable_inspect_size/)
                  end
                end
              end
            end
          end

          context 'on a platform without ObjectSpace' do
            before do
              Object.send(:remove_const, :ObjectSpace) if Object.constants.include?(:ObjectSpace)
            end
            after do
              require "objspace" rescue nil
            end

            context 'with a variable that is smaller than maximum_variable_inspect_size' do
              let(:exception_binding) {
                @small = content

                binding
              }
              let(:content) { 'A' * 480 }

              it "shows the variable content" do
                expect(html).to have_tag('div.variables', text: %r{#{content}})
              end
            end

            context 'with a variable that is larger than maximum_variable_inspect_size' do
              context 'but has an #inspect that returns a smaller value' do
                let(:exception_binding) {
                  @big = content

                  binding
                }
                let(:content) {
                  class ExtremelyLargeInspectableTestValue
                    def initialize
                      @a = 'A' * 1101
                    end
                    def inspect
                      "shortval"
                    end
                  end
                  ExtremelyLargeInspectableTestValue.new
                }

                it "shows the variable content" do
                  expect(html).to have_tag('div.variables', text: /shortval/)
                end
              end
              context 'and does not implement #inspect' do
                let(:exception_binding) {
                  @big = content

                  binding
                }
                let(:content) { 'A' * 1101 }

                it "includes an indication that the variable was too large" do
                  
                  expect(html).not_to have_tag('div.variables', text: %r{#{content}})
                  expect(html).to have_tag('div.variables', text: /Object too large/)
                end
              end
            end

            context "when the variable's class is anonymous" do
              let(:exception_binding) {
                @big_anonymous = Class.new do
                  def initialize
                    @content = 'A' * 1101
                  end
                end.new

                binding
              }

              it "does not attempt to show the class name" do
                expect(html).to have_tag('div.variables tr') do
                  with_tag('td.name', text: '@big_anonymous')
                  with_tag('.unsupported', text: /Object too large/)
                  with_tag('.unsupported', text: /Adjust BetterErrors.maximum_variable_inspect_size/)
                end
              end
            end
          end
        end

        context 'when maximum_variable_inspect_size is disabled' do
          before do
            BetterErrors.maximum_variable_inspect_size = nil
          end

          let(:exception_binding) {
            @big = content

            binding
          }
          let(:content) { 'A' * 100_001 }

          it "includes the content of large variables" do
            expect(html).to have_tag('div.variables', text: %r{#{content}})
            expect(html).not_to have_tag('div.variables', text: /Object too large/)
          end
        end
      end

      context "when binding_of_caller is not loaded" do
        before do
          skip "binding_of_caller is loaded" if BetterErrors.binding_of_caller_available?
        end

        it "tells the user to add binding_of_caller to their gemfile to get fancy features" do
          expect(html).not_to have_tag('div.variables', text: /gem "binding_of_caller"/)
        end
      end
    end

    it "doesn't die if the source file is not a real filename" do
      allow(exception).to receive(:__better_errors_bindings_stack).and_return([])
      allow(exception).to receive(:backtrace).and_return([
        "<internal:prelude>:10:in `spawn_rack_application'"
      ])
      expect(response).to have_tag('.frames li .location .filename', text: '<internal:prelude>')
    end

    context 'with an exception with blank lines' do
      class SpacedError < StandardError
        def initialize(message = nil)
          message = "\n\n#{message}" if message
          super
        end
      end

      let!(:exception) { raise SpacedError, "Danger Warning!" rescue $! }

      it 'does not include leading blank lines in exception_message' do
        expect(exception.message).to match(/\A\n\n/)
        expect(error_page.exception_message).not_to match(/\A\n\n/)
      end
    end

    describe '#do_eval' do
      let(:exception) { exception_binding.eval("raise") rescue $! }
      subject(:do_eval) { error_page.do_eval("index" => 0, "source" => command) }
      let(:command) { 'EvalTester.stuff_was_done(:yep)' }
      before do
        stub_const('EvalTester', eval_tester)
      end
      let(:eval_tester) { double('EvalTester', stuff_was_done: 'response') }

      context 'without binding_of_caller' do
        before do
          skip("Disabled with binding_of_caller") if defined? ::BindingOfCaller
        end

        it "does not evaluate the code" do
          do_eval
          expect(eval_tester).to_not have_received(:stuff_was_done).with(:yep)
        end

        it 'returns an error indicating no REPL' do
          expect(do_eval).to include(
            error: "REPL unavailable in this stack frame",
          )
        end
      end

      context 'with binding_of_caller available' do
        before do
          skip("Disabled without binding_of_caller") unless defined? ::BindingOfCaller
        end

        context 'with Pry disabled or unavailable' do
          it "evaluates the code" do
            do_eval
            expect(eval_tester).to have_received(:stuff_was_done).with(:yep)
          end

          it 'returns a hash of the code and its result' do
            expect(do_eval).to include(
              highlighted_input: /stuff_was_done/,
              prefilled_input: '',
              prompt: '>>',
              result: "=> \"response\"\n",
            )
          end
        end

        context 'with Pry enabled' do
          before do
            skip("Disabled without pry") unless defined? ::Pry

            BetterErrors.use_pry!
            # Cause the provider to be unselected, so that it will be re-detected.
            BetterErrors::REPL.provider = nil
          end
          after do
            BetterErrors::REPL::PROVIDERS.shift
            BetterErrors::REPL.provider = nil

            # Ensure the Pry REPL file has not been included. If this is not done,
            # the constant leaks into other examples.
            BetterErrors::REPL.send(:remove_const, :Pry)
          end

          it "evaluates the code" do
            BetterErrors::REPL.provider
            do_eval
            expect(eval_tester).to have_received(:stuff_was_done).with(:yep)
          end

          it 'returns a hash of the code and its result' do
            expect(do_eval).to include(
              highlighted_input: /stuff_was_done/,
              prefilled_input: '',
              prompt: '>>',
              result: "=> \"response\"\n",
            )
          end
        end
      end
    end

    describe 'do_expand' do
      context 'requesting more lines of code in the upper direction' do
        subject(:do_expand) { error_page.do_expand('index' => 0, 'direction' => 'up') }
        it 'should' do
          html = do_expand[:html]
          expect(html).to include("<span class=\"\">    1</span>")
          expect(html).to include("<span class=\"\">   10</span>")
          expect(html).to_not include("<span class=\"\">   15</span>")
        end
      end
      context 'requesting one time more lines of code in the lower direction' do
        it 'should returns the codes from line 1 until line 15' do
          html = error_page.do_expand('index' => 0, 'direction' => 'down')[:html]
          expect(html).to include("<span class=\"\">    1</span>")
          expect(html).to include("<span class=\"\">   15</span>")
          expect(html).to_not include("<span class=\"\">   16</span>")
        end
      end
      context 'requesting two times more lines of code in the lower direction' do
        it 'should returns the codes from line 1 until line 20' do
          error_page.do_expand('index' => 0, 'direction' => 'down')
          html = error_page.do_expand('index' => 0, 'direction' => 'down')[:html]
          expect(html).to include("<span class=\"\">    1</span>")
          expect(html).to include("<span class=\"\">   20</span>")
          expect(html).to_not include("<span class=\"\">   21</span>")
        end
      end
    end
  end
end
