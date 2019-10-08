# frozen_string_literal: true

require 'pathname'

# Basic options parser
class Options
  def self.to_arg(sym)
    sym.to_s.gsub('_', '-')
  end

  def self.to_argv(*args, **kwargs)
    args.map! do |arg|
      case arg
      when Symbol
        "--#{to_arg(arg)}"
      else
        arg
      end
    end
    kwargs.each do |arg, value|
      converted = case value
                  when TrueClass
                    "--#{to_arg(arg)}"
                  when FalseClass
                    "--no-#{to_arg(arg)}"
                  when Array
                    value.map do |v|
                      "--#{to_arg(arg)}=#{v}"
                    end
                  else
                    "--#{to_arg(arg)}=#{value}"
                  end
      args.concat(Array(converted))
    end
    args
  end

  def self.parse(*args_or_argv, aliases: {}, flag_configs: {}, **kwargs)
    argv = to_argv(*args_or_argv, **kwargs)

    literal_only = false
    prologue = []
    epilogue = []
    flags = {}
    last_sym = nil
    last_sym_pending = nil

    resolve = lambda do |src|
      raise "Missing value after '#{last_sym_pending}'" if last_sym_pending

      sym = src.gsub('-', '_').to_sym
      aliases[sym] || sym
    end

    argv.each do |arg|
      if literal_only
        epilogue << arg
        next
      end
      case arg
      when /^--$/
        literal_only = true
        last_sym = nil
      when /^-([[:alnum:]-])$/
        last_sym = sym = resolve.call(Regexp.last_match(1))
        case flags[sym]
        when true
          flags[sym] = 2
        when Integer
          flags[sym] += 1
        when nil
          flags[sym] = true
        else
          raise "Unexpected boolean '#{arg}' after set to value #{flags[sym].inspect}"
        end

      when /^--(?<no>no-)?(?<flag>[[:alnum:]-]+)(?:=(?<value>.*))?$/
        flag = Regexp.last_match[:flag]
        value = Regexp.last_match[:value]
        no = Regexp.last_match[:no]
        sym = resolve.call(flag)
        flag_config = case flag_configs[sym]
                      when true
                        :boolean
                      else
                        flag_configs[sym]
                      end
        if no
          raise "Unexpected value specified with no- prefix: #{arg}" unless value.nil?

          flags[sym] = false
          last_sym = nil
        elsif value.nil?
          last_sym = flag_config == :boolean ? nil : sym
          case flags[sym]
          when true
            flags[sym] = 2
          when Integer
            flags[sym] += 1
          when nil, false
            flags[sym] = true
          else
            last_sym_pending = arg
          end
        else
          raise "Unexpected value for #{inspect_flag(arg)}: #{value.inspect}" if flag_config == :boolean

          last_sym = nil
          case flags[sym]
          when nil
            flags[sym] = value
          when Array
            flags[sym] << value
          else
            flags[sym] = [flags[sym], value]
          end
        end

      else
        if last_sym
          case flags[last_sym]
          when true
            flags[last_sym] = arg
          when Array
            flags[last_sym] << arg
          else
            flags[last_sym] = [flags[last_sym], arg]
          end
          last_sym_pending = nil
        elsif flags.empty?
          prologue << arg
        else # first non-switch after switches + values
          literal_only = true
          epilogue << arg
        end
      end
      next if arg.nil?
    end
    raise "Missing value after '#{last_sym_pending}'" if last_sym_pending

    result = {}
    result[:prologue] = prologue unless prologue.empty?
    result[:flags] = flags unless flags.empty?
    result[:epilogue] = epilogue unless epilogue.empty?
    result unless result.empty?
  end

  # @return Hash
  attr_reader :aliases

  # @returns Array
  attr_reader :required_prologue
  attr_reader :optional_prologue
  attr_reader :flag_configs
  attr_reader :epilogue_key

  def initialize(prologue: [], flag_configs: {}, epilogue_key: false, aliases: {}, program: nil)
    @program = program || begin 
      %r{^(?:.*/)?(?<file>[^/]+):\d+:in} =~ caller.first
      file
    end
    @aliases = aliases.freeze
    initialize_prologue(prologue)
    @flag_configs = flag_configs.freeze
    @epilogue_key = epilogue_key == true ? :epilogue : epilogue_key
    @valid = false
  end

  private

  def initialize_prologue(prologue)
    required_prologue = []
    optional_prologue = []
    prologue.each do |key|
      /^(?<key>[[:alnum:]-]*)(?<optional>\?)?$/ =~ key
      key = key.to_sym
      if optional
        optional_prologue << key if optional
      else
        raise 'required prologue cannot follow optional prologue' unless optional_prologue.empty?

        required_prologue << key
      end
    end
    @required_prologue = required_prologue.freeze
    @optional_prologue = optional_prologue.freeze
  end

  public

  def flag_config(sym)
    flag_config = flag_configs[sym]
    case flag_config
    when true
      { type: :boolean }
    when Symbol
      { type: flag_config }
    when nil
    when String
      { help: flag_config }
    else
      flag_config
    end
  end
  
  def flag_type(sym)
    flag_config(sym)[:type]
  end

  def boolean?(sym)
    flag_type(sym) == :boolean
  end

  def inspect_flag(sym)
    return "#{sym.upcase}" if required_prologue.member?(sym)
    return "[#{sym.upcase}]" if optional_prologue.member?(sym)
    return "[#{sym.to_s.upcase} ... [#{sym.to_s.upcase}]]" if epilogue_key == sym
    return "--[no-]#{sym}" if boolean?(sym)

    "--#{sym}"
  end

  def help
    prologue_keys = required_prologue + optional_prologue
    all_flags = prologue_keys + (flag_configs.keys - prologue_keys) + Array(epilogue_key)
    usage = "Usage: #{@program} #{all_flags.map(&method(:inspect_flag)).join(' ')}"
    lines = all_flags.map do |flag|
      config = flag_config(flag)
      next if config.nil?
      flag_help = config[:help] || case config[:type]
                                   when :boolean
                                     'switch'
                                   else
                                   end
      [inspect_flag(flag), flag_help] if flag_help
    end.compact
    return [usage] if lines.empty?
    width = lines.map(&:first).tap { |r| puts(r.inspect)}.map(&:length).max
    lines.map! { |line| format("  %-#{width}s : %s", *line) }
    [usage, nil] + lines
  end

  def valid?
    @valid
  end

  def parse(*args, **kwargs)
    raise 'Options are frozen once parsed' if @valid

    @parsed = Options.parse(*args, aliases: aliases, flag_configs: flag_configs, **kwargs) || {}
    @values = @parsed[:flags] || {}
    parsed_prologue = @parsed[:prologue] || []
    actual_required_prologue = required_prologue - @values.keys
    if actual_required_prologue.length > parsed_prologue.length
      missing_flags = actual_required_prologue.drop(parsed_prologue.length)
      raise "Missing positional arguments: #{missing_flags.map(&method(:inspect_flag)).join(', ')}"
    end

    expected_prologue = (required_prologue + optional_prologue) - @values.keys
    actual_prologue = expected_prologue.zip(parsed_prologue).reject do |_, v|
      # Avoid nil values since they're never returned from {@link Options.parse}
      v.nil?
    end.to_h
    #puts(parsed_prologue: parsed_prologue, required_prologue: required_prologue, actual_required_prologue: actual_required_prologue, expected_prologue: expected_prologue, actual_prologue: actual_prologue)
    @values = actual_prologue.merge(@values)
    epilogue = parsed_prologue.drop(actual_prologue.length).concat(Array(@parsed[:epilogue]))
    if epilogue_key
      @values[epilogue_key] = epilogue
    else
      raise "Unexpected epilogue: #{epilogue.inspect}" unless epilogue.empty?
    end
    @valid = true
  end

  def respond_to_missing?(sym, *_)
    /^(?<key>.*?)(?:(?<_boolean>\?))?$/ =~ sym
    key = key.to_sym
    #puts(sym: sym, key: key, values: @values)
    return super unless @values.member?(key) || @optional_prologue.member?(key) || @flag_configs.member?(key)

    true
  end

  def method_missing(sym, *_)
    return super unless @parsed

    /^(?<key>.*?)(?:(?<boolean>\?))?$/ =~ sym
    key = key.to_sym
    return super unless @values.member?(key) || @optional_prologue.member?(key) || @flag_configs.member?(key)

    value = @values[key]
    return !(!value) if boolean

    value
  end
end
