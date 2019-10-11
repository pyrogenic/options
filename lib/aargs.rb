# frozen_string_literal: true

require 'pathname'

# Basic aargs parser
class Aargs
  def self.kebab(sym)
    sym.to_s.gsub(/[^[:alnum:]]/, '-')
  end

  def self.underscore(src)
    src.gsub(/[^[:alnum:]]/, '_').to_sym
  end

  def self.flagify_arg(arg)
    case arg
    when Symbol
      "--#{kebab(arg)}"
    when Hash
      arg.map(&method(:flagify_kwarg)).flatten
    else
      arg
    end
  end

  def self.flagify_kwarg(arg, value)
    case value
    when TrueClass
      "--#{kebab(arg)}"
    when FalseClass
      "--no-#{kebab(arg)}"
    when Array
      value.map { |v| "--#{kebab(arg)}=#{v}" }
    else
      "--#{kebab(arg)}=#{value}"
    end
  end

  # Convert symbolic arguments and keyword-arguments into an equivalent `ARGV`.  Non-symbol argments remain unchanged.
  # Note that to generate a epilogue portion of an ARGV you need to pass keyword arguments as explicit hashes followed
  # by non-hash, non-symbol values.
  def self.to_argv(*args)
    args.map(&method(:flagify_arg)).flatten
  end

  def self.parse(args_or_argv, aliases: {}, flag_configs: {})
    argv = to_argv(*args_or_argv)

    literal_only = false
    prologue = []
    epilogue = []
    flags = {}
    last_sym = nil
    last_sym_pending = nil

    resolve = lambda do |src|
      raise "Missing value after '#{last_sym_pending}'" if last_sym_pending

      sym = underscore(src)
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
      when /^-([[:alnum:]])$/
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
        boolean = boolean?(sym, flag_configs: flag_configs)
        if no
          raise "Unexpected value specified with no- prefix: #{arg}" unless value.nil?

          flags[sym] = false
          last_sym = nil
        elsif value.nil?
          last_sym = boolean ? nil : sym
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
          raise "Unexpected value for #{inspect_flag(arg)}: #{value.inspect}" if boolean

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
  attr_reader :prologue_key
  attr_reader :flag_configs
  attr_reader :required_epilogue
  attr_reader :optional_epilogue
  attr_reader :epilogue_key

  DEFAULT = Object.new

  def initialize(
    prologue: DEFAULT,
    flag_config: DEFAULT,
    flag_configs: nil,
    epilogue: DEFAULT,
    aliases: {},
    program: nil)
    @program = program || begin
      %r{^(?:.*/)?(?<file>[^/]+):\d+:in} =~ caller.first
      file
    end
    @aliases = aliases.freeze
    prologue_set = prologue && prologue != DEFAULT
    flag_configs_set = flag_configs && flag_configs != DEFAULT
    epilogue_set = epilogue && epilogue != DEFAULT
    prologue = epilogue_set || flag_configs_set ? false : true if prologue == DEFAULT
    initialize_prologue(prologue)
    flag_config = flag_configs_set ? false : true if flag_config == DEFAULT
    @flag_configs = Hash.new(flag_config).merge(flag_configs || {}).freeze
    epilogue = prologue_set || flag_configs_set ? false : true if epilogue == DEFAULT
    initialize_epilogue(epilogue)
    @valid = false
  end

  private

  def initialize_prologue(prologue)
    @required_prologue = []
    @optional_prologue = []
    @prologue_key = :prologue if prologue == true
    @prologue_key = false if prologue == false
    return unless @prologue_key.nil?

    Array(prologue).each do |key|
      /^(?<key>[[:alnum:]-]*)(?<optional>\?)?$/ =~ key
      key = key.to_sym
      if optional
        @optional_prologue << key if optional
      else
        raise 'required prologue cannot follow optional prologue' unless @optional_prologue.empty?

        @required_prologue << key
      end
    end
    @required_prologue.freeze
    @optional_prologue.freeze
  end

  def initialize_epilogue(epilogue)
    @required_epilogue = []
    @optional_epilogue = []
    @epilogue_key = :epilogue if epilogue == true
    @epilogue_key = false if epilogue == false
    @epilogue_key = epilogue if epilogue.is_a?(Symbol)
    return unless @epilogue_key.nil?

    Array(epilogue).each do |key|
      /^(?<key>[[:alnum:]-]*)(?<optional>\?)?$/ =~ key
      key = key.to_sym
      if optional
        @optional_epilogue << key if optional
      else
        raise 'required epilogue cannot follow optional epilogue' unless @optional_epilogue.empty?

        @required_epilogue << key
      end
    end
    @required_epilogue = @required_epilogue.freeze
    @optional_epilogue = @optional_epilogue.freeze
  end

  public

  def self.flag_config(sym, flag_configs:)
    flag_config = flag_configs[sym]
    case flag_config
    when true
      { type: :anything }
    when Symbol
      { type: flag_config }
    when nil
      nil
    when String
      { help: flag_config }
    else
      flag_config
    end
  end

  def self.flag_type(sym, flag_configs:)
    config = flag_config(sym, flag_configs: flag_configs)
    config[:type] if config
  end

  def self.boolean?(sym, flag_configs:)
    flag_type(sym, flag_configs: flag_configs) == :boolean
  end

  def flag_config(sym)
    Aargs.flag_config(sym, flag_configs: flag_configs)
  end

  def flag_type(sym)
    Aargs.flag_type(sym, flag_configs: flag_configs)
  end

  def boolean?(sym)
    Aargs.boolean?(sym, flag_configs: flag_configs)
  end

  def required?(sym)
    [required_prologue, required_epilogue].map(&method(:Array)).flatten.member?(sym)
  end

  def optional?(sym)
    [optional_prologue, optional_epilogue].map(&method(:Array)).flatten.member?(sym)
  end

  def splat?(sym)
    [prologue_key, epilogue_key].member?(sym)
  end

  def inspect_flag(sym)
    arg = Aargs.kebab(sym)
    return "#{arg.upcase}" if required?(sym)
    return "[#{arg.upcase}]" if optional?(sym)
    return "[aargs]" if sym == :any_key
    return "[#{arg.to_s.upcase} ... [#{arg.to_s.upcase}]]" if splat?(sym)
    return "--[no-]#{arg}" if boolean?(sym)

    "--#{arg}=VALUE"
  end

  def help
    prologue_keys = [required_prologue, optional_prologue, prologue_key ? prologue_key : nil].map(&method(:Array)).flatten
    epilogue_keys = [required_epilogue, optional_epilogue, epilogue_key ? epilogue_key : nil].map(&method(:Array)).flatten
    flag_keys = flag_configs.keys
    flag_keys << :any_key if flag_configs[:any_key]
    all_flags = prologue_keys + (flag_keys - prologue_keys) + epilogue_keys
    usage = "Usage: #{@program} #{all_flags.map(&method(:inspect_flag)).join(' ')}"
    any_real_help = false
    lines = all_flags.map do |flag|
      config = flag_config(flag)
      next unless config

      real_help = config[:help]
      any_real_help ||= real_help
      flag_help = real_help || case config[:type]
                               when :boolean
                                 '(switch)'
                               else
                                 "(#{config[:type]})"
                               end
      [inspect_flag(flag), flag_help] if flag_help
    end.compact
    return [usage] if lines.empty? || !any_real_help

    width = lines.map(&:first).map(&:length).max
    lines.map! { |(flag, help)| format("  %<flag>-#{width}s : %<help>s", flag: flag, help: help) }
    [usage, nil] + lines
  end

  def valid?
    @valid
  end

  def parse(*args)
    raise 'Aargs are frozen once parsed' if @valid

    @parsed = Aargs.parse(args, aliases: aliases, flag_configs: flag_configs) || {}
    @values = @parsed[:flags] || {}
    parsed_prologue = @parsed[:prologue] || []

    validate_sufficient_prologue(parsed_prologue)
    consumed_prologue = apply_prologue(parsed_prologue)
    apply_epilogue(parsed_prologue, consumed_prologue)
    @valid = true
    self
  end

  # @return if the given key is a known flag that should appear as part of the object's API
  def api_key?(key)
    @values.member?(key) || @optional_prologue.member?(key) || @flag_configs.member?(key)
  end

  def respond_to_missing?(sym, *_)
    /^(?<key>.*?)(?:(?<_boolean>\?))?$/ =~ sym
    key = key.to_sym
    # puts(sym: sym, key: key, values: @values)
    return super unless api_key?(key)

    true
  end

  def method_missing(sym, *_)
    return super unless @parsed

    /^(?<key>.*?)(?:(?<boolean>\?))?$/ =~ sym
    key = key.to_sym
    return super unless api_key?(key)

    value = @values[key]
    return !(!value) if boolean

    value
  end

  private

  # Validate that we have enough arguments given to satisfy our required prologue, taking into account any that were
  # specified as flags.
  def validate_sufficient_prologue(parsed_prologue)
    return if prologue_key

    pp(required_prologue: required_prologue, values: @values)
    actual_required_prologue = required_prologue - @values.keys
    return if actual_required_prologue.length <= parsed_prologue.length

    missing_flags = actual_required_prologue.drop(parsed_prologue.length)
    raise "Missing positional arguments: #{missing_flags.map(&method(:inspect_flag)).join(', ')}"
  end

  # Validate that we have enough arguments given to satisfy our required prologue, taking into account any that were
  # specified as flags.
  def validate_sufficient_epilogue(parsed_epilogue)
    return if epilogue_key

    actual_required_epilogue = required_epilogue - @values.keys
    return if actual_required_epilogue.length <= parsed_epilogue.length

    missing_flags = actual_required_epilogue.drop(parsed_epilogue.length)
    raise "Missing positional arguments: #{missing_flags.map(&method(:inspect_flag)).join(', ')}"
  end

  # Reverse-merge prologue values into {@link @values}
  # @return [Hash] the recognized prologue flags
  def apply_prologue(parsed_prologue)
    return @values[prologue_key] = parsed_prologue if prologue_key

    # Remove any prologue keys whose values appeared as flags:
    expected_prologue = (required_prologue + optional_prologue) - @values.keys
    # Convert the prologue into a hash based on the prologue keys we're still waiting for:
    consumed_prologue = expected_prologue.zip(parsed_prologue).reject do |_, v|
      # Avoid nil values since they're never returned from {@link Aargs.parse}
      v.nil?
    end.to_h
    @values = consumed_prologue.merge(@values)
    consumed_prologue
  end

  # Any extra prologue values become the beginning of the epilogue.
  # Reverse-merge epilogue values into {@link @values}
  # @raise if there's an epilogue given but we don't expect one
  # @see epilogue_key
  def apply_epilogue(parsed_prologue, consumed_prologue)
    parsed_epilogue = parsed_prologue.drop(consumed_prologue.length).concat(Array(@parsed[:epilogue]))

    # TODO: allow ... after required/optional consumed

    # Remove any epilogue keys whose values appeared as flags:
    epilogue_keys = [required_epilogue, optional_epilogue].map(&method(:Array)).flatten
    expected_epilogue = epilogue_keys - @values.keys
    # Convert the epilogue into a hash based on the epilogue keys we're still waiting for:
    consumed_epilogue = expected_epilogue.zip(parsed_epilogue).reject do |_, v|
      # Avoid nil values since they're never returned from {@link Aargs.parse}
      v.nil?
    end.to_h
    @values = consumed_epilogue.merge(@values)

    epilogue = parsed_epilogue.drop(consumed_epilogue.length)
    return if epilogue.empty?
    raise "Unexpected epilogue: #{epilogue.inspect}" unless epilogue_key

    @values[epilogue_key] = epilogue
    nil
  end
end
