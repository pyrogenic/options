# frozen_string_literal: true

require 'spec_helper'
require 'options'

RSpec.describe Options do
  let(:aliases) { { f: :flag } }
  context 'parser' do
    it 'empty' do
      expect(described_class.parse).to be_nil
    end
    it 'literal' do
      expect(described_class.parse('f')).to match(prologue: ['f'])
    end
    it 'literals' do
      expect(described_class.parse('f', '--', '-f')).to match(
        prologue: ['f'],
        epilogue: ['-f']
      )
    end
    it 'flag' do
      expect(described_class.parse('-f')).to match(flags: { f: true })
      expect(described_class.parse('-f', '-f')).to match(flags: { f: 2 })
      expect(described_class.parse('-f', '-f', '-f')).to match(flags: { f: 3 })
    end
    it 'long-flag' do
      expect(described_class.parse('--flag')).to match(flags: { flag: true })
      expect(described_class.parse('--flag', '--flag')).to match(flags: { flag: 2 })
      expect(described_class.parse('--flag', '--flag', '--flag')).to match(flags: { flag: 3 })
    end
    context 'long-flag' do
      it 'alone' do
        expect(described_class.parse('--flag=example')).to match(flags: { flag: 'example' })
        expect(described_class.parse('--flag', 'example')).to match(flags: { flag: 'example' })
        expect(described_class.parse('--flag', 'example', '--flag', 'another')).to match(flags: { flag: %w[example another] })
        expect(described_class.parse('--flag', 'example', 'another')).to match(flags: { flag: %w[example another] })
        expect(described_class.parse('--flag', 'example', '--flag', 'another', '--flag', 'example')).to match(flags: { flag: %w[example another example] })
        expect(described_class.parse('--flag', 'example', 'another', '--flag', 'example')).to match(flags: { flag: %w[example another example] })
        expect(described_class.parse('--flag', 'example', '--flag', 'another', 'example')).to match(flags: { flag: %w[example another example] })
        expect(described_class.parse('--flag', 'example', 'another', 'example')).to match(flags: { flag: %w[example another example] })
      end
      it 'with prologue' do
        expect(described_class.parse('fun', '--flag=example')).to match(prologue: ['fun'], flags: { flag: 'example' })
      end
      it 'with epilog' do
        expect(described_class.parse('--flag=example', 'another', 'example')).to match(flags: { flag: 'example' }, epilogue: %w[another example])
        expect(described_class.parse('--flag', 'example', '--', 'another', 'example')).to match(flags: { flag: 'example' }, epilogue: %w[another example])
      end
      it 'with both' do
        expect(described_class.parse('fun', '--flag=example', 'another', 'example')).to match(prologue: ['fun'], flags: { flag: 'example' }, epilogue: %w[another example])
        expect(described_class.parse('fun', '--flag', 'example', '--', 'another', 'example')).to match(prologue: ['fun'], flags: { flag: 'example' }, epilogue: %w[another example])
      end
    end
    it 'inversion' do
      expect(described_class.parse('--no-flag')).to match(flags: { flag: false })
      expect(described_class.parse(:no_flag)).to match(flags: { flag: false })
      expect(described_class.parse('--flag', '--no-flag')).to match(flags: { flag: false })
      expect(described_class.parse(:flag, :no_flag)).to match(flags: { flag: false })
      expect(described_class.parse('--flag', '--no-flag', '--no-flag')).to match(flags: { flag: false })
      expect(described_class.parse(:flag, :no_flag, :no_flag)).to match(flags: { flag: false })
      expect(described_class.parse('--no-flag', '--flag', '--no-flag')).to match(flags: { flag: false })
      expect(described_class.parse(:no_flag, :flag, :no_flag)).to match(flags: { flag: false })
    end
    it 'alias' do
      expect(described_class.parse('-f', aliases: aliases)).to match(flags: { flag: true })
      expect(described_class.parse('-f', '-f', aliases: aliases)).to match(flags: { flag: 2 })
      expect(described_class.parse('--flag', '-f', aliases: aliases)).to match(flags: { flag: 2 })
    end
    shared_examples_for 'IRB' do |args, kwargs, argv, parse_result|
      it 'to_argv' do
        expect(described_class.to_argv(*args, **kwargs)).to eq(argv)
      end
      it 'parse' do
        expect(described_class.parse(*args, **kwargs)).to match(parse_result)
      end
    end
    context 'args' do
      it_behaves_like('IRB', [:flag], {}, ['--flag'], flags: { flag: true })
      it_behaves_like('IRB', %i[flag flag], {}, ['--flag', '--flag'], flags: { flag: 2 })
    end
    context 'kwargs' do
      it_behaves_like('IRB', [], { flag: true }, ['--flag'], flags: { flag: true })
      it_behaves_like('IRB', [], { flag: 'example' }, ['--flag=example'], flags: { flag: 'example' })
      it_behaves_like('IRB', [], { flag: ['example'] }, ['--flag=example'], flags: { flag: 'example' })
      it_behaves_like('IRB', [], { flag: %w[example another] }, ['--flag=example', '--flag=another'], flags: { flag: %w[example another] })
      it_behaves_like('IRB', [], { flag: ['example', 'another', 'yet another'] }, ['--flag=example', '--flag=another', '--flag=yet another'], flags: { flag: ['example', 'another', 'yet another'] })
    end
    context 'both' do
      it_behaves_like('IRB', [:flag], { flag: true }, ['--flag', '--flag'], flags: { flag: 2 })
      it_behaves_like('IRB', %i[flag flag], { flag: false }, ['--flag', '--flag', '--no-flag'], flags: { flag: false })
    end
    context 'error conditions' do
      it 'flag after value' do
        expect { described_class.parse('--flag=x', '--flag', '--no-flag') }.to raise_error(/missing value.*'--flag'/i)
        expect { described_class.parse('--flag=example-value', '-f', aliases: aliases) }.to raise_error(/boolean.*'-f'.*"example-value"/i)
        expect { described_class.parse('--flag=example-value', '--flag') }.to raise_error(/missing value.*'--flag'/i)
      end
    end
  end

  context 'config' do
    let(:prologue) { nil }
    let(:flag_configs) { nil }
    let(:epilogue_key) { nil }
    let(:options) do
      args = {}
      args[:prologue] = prologue unless prologue.nil?
      args[:flag_configs] = flag_configs unless flag_configs.nil?
      args[:epilogue_key] = epilogue_key unless epilogue_key.nil?
      described_class.new(**args)
    end

    it 'constructs' do
      expect(options).not_to be_valid
    end

    context 'no configuration' do
      it 'empty' do
        expect { options.parse }.to change(options, :valid?).from(false).to(true)
        expect { options.parse }.to raise_error(/frozen/i)
      end

      it 'unexpected epilogue' do
        expect { options.parse('anything') }.to raise_error(/unexpected/i)
      end
    end

    context 'optional prologue' do
      let(:prologue) { [:mode?] }

      it 'empty' do
        expect { options.parse }.to change(options, :valid?).from(false).to(true)
        expect(options.mode).to be_nil
        expect { options.parse }.to raise_error(/frozen/i)
      end

      it 'valid' do
        expect { options.parse('anything') }.to change(options, :valid?).from(false).to(true)
        expect(options.mode).to eq('anything')
      end
    end

    context 'required prologue' do
      let(:prologue) { [:mode] }

      it 'empty' do
        expect { options.parse }.to raise_error(/positional.*mode/i)
      end

      it 'valid' do
        expect { options.parse('anything') }.to change(options, :valid?).from(false).to(true)
        expect { options.parse }.to raise_error(/frozen/i)

        expect(options.mode).to eq('anything')
      end

      it 'as flag =' do
        expect { options.parse('--mode=anything') }.to change(options, :valid?).from(false).to(true)
        expect { options.parse }.to raise_error(/frozen/i)

        expect(options.mode).to eq('anything')
      end

      it 'as flag value' do
        expect { options.parse('--mode', 'anything') }.to change(options, :valid?).from(false).to(true)
        expect { options.parse }.to raise_error(/frozen/i)

        expect(options.mode).to eq('anything')
      end

      context 'without epilogue' do
        it 'unexpected epilogue' do
          expect { options.parse('anything', 'extra') }.to raise_error(/unexpected/i)
        end
      end

      context 'with epilogue' do
        let(:epilogue_key) { :etc }

        it 'simple' do
          expect { options.parse('anything', 'extra') }.to change(options, :valid?).from(false).to(true)
          expect(options.etc).to eq(['extra'])
        end

        it 'double' do
          expect { options.parse('anything', 'extra', 'extra') }.to change(options, :valid?).from(false).to(true)
          expect(options.etc).to eq(%w[extra extra])
        end

        it 'flag-hardcore' do
          expect { options.parse('anything', '--read-all-about-it', '--', 'extra', 'extra') }.to change(options, :valid?).from(false).to(true)
          expect(options).to be_read_all_about_it
          expect(options.etc).to eq(%w[extra extra])
        end

        it 'flag-value' do
          expect { options.parse('anything', '--read-all-about-it=something', 'extra', 'extra') }.to change(options, :valid?).from(false).to(true)
          expect(options).to be_read_all_about_it
          expect(options.etc).to eq(%w[extra extra])
        end

        context 'with configured flags' do
          let(:flag_configs) { { read_all_about_it: true } }

          it 'flag-config' do
            expect { options.parse('anything', '--read-all-about-it', 'extra', 'extra') }.to change(options, :valid?).from(false).to(true)
            expect(options).to be_read_all_about_it
            expect(options.etc).to eq(%w[extra extra])
          end

          def expect_usage
            help = options.help
            puts help
            usage_line = help.shift
            expect(usage_line).to match(/^Usage: #{Pathname(__FILE__).basename}/)
            expect(usage_line).to match(/MODE/)
            expect(usage_line).to match(/\[ETC/)
            
            expect(help.shift).to be_nil.or(match(/^$/))
            help
          end
          
          it :help do
            expect_usage
          end

          context 'with documentation' do
            let(:flag_configs) do
              {
                read_all_about_it: true,
                mode: 'operation mode',
              }
            end

            it 'help' do
              help = expect_usage
              expect(help).to include(/MODE/)
              expect(help).to include(/--\[no-\]read-all-about-it/)
            end

            context 'better help' do
              let(:flag_configs) do
                {
                  read_all_about_it: {
                    type: :boolean,
                    help: 'actually read stuff',
                  },
                  mode: 'operation mode',
                }
              end  

              it 'help' do
                help = expect_usage
                expect(help).to include(/MODE/)
                expect(help).to include(/--\[no-\]read-all-about-it.*actually read stuff/)
              end
            end
          end
        end
      end
    end
  end
end
