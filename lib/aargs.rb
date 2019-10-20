# frozen_string_literal: true

require 'pathname'

# Basic aargs parser
class Aargs
  # Auto-invoke Container#main if it's the executed source file
  # `main` is invoked as soon as it is defined, so make sure to do it last!
  module Main
    def self.const_missing(name)
      super unless identified_main && name == :AARGS
      warn("Missing #{identified_main.name}::AARGS")
      const_set('AARGS', Aargs.new)
    end

    def self.extended(main_class)
      return unless caller.detect { |e| e.include?($PROGRAM_NAME) }

      @main = main_class
    end

    def self.identified_main
      @main
    end

    def singleton_method_added(name)
      return unless name == :main

      return unless Main.identified_main == self

      send(name, AARGS.parse(ARGV))
    end
  end

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

  # Parser for Args
  class ParseState
    attr_accessor :aliases, :flag_configs, :literal_only, :prologue, :epilogue, :flags, :last_sym, :last_sym_pending
    def initialize(aliases, flag_configs)
      @literal_only = false
      @prologue = []
      @epilogue = []
      @flags = {}
      @last_sym = nil
      @last_sym_pending = nil

      @aliases = aliases
      @flag_configs = flag_configs
    end

    def resolve(src)
      raise "Missing value after '#{last_sym_pending}'" if last_sym_pending

      sym = Aargs.underscore(src)
      aliases[sym] || sym
    end

    def parse(argv)
      argv.each(&method(:parse_arg))
      raise "Missing value after '#{last_sym_pending}'" if last_sym_pending

      result
    end

    def result
      result = {}
      result[:prologue] = prologue unless prologue.empty?
      result[:flags] = flags unless flags.empty?
      result[:epilogue] = epilogue unless epilogue.empty?
      result unless result.empty?
    end

    private

    def to_hash(match)
      match.names.map(&:to_sym).zip(match.captures).to_h
    end

    def parse_arg(arg)
      @arg = arg
      return epilogue << @arg if literal_only

      case @arg
      when /^--$/
        parse_dash_dash
      when /^-([[:alnum:]])$/
        parse_single_char_flag(Regexp.last_match(1))
      when /^--(?<no>no-)?(?<flag>[[:alnum:]-]+)(?:=(?<value>.*))?$/
        parse_value_flag(to_hash(Regexp.last_match))
      else
        parse_literal
      end
    end

    def parse_dash_dash
      self.literal_only = true
      self.last_sym = nil
    end

    def parse_single_char_flag(single_char_flag)
      self.last_sym = sym = resolve(single_char_flag)
      case flags[sym]
      when true
        flags[sym] = 2
      when Integer
        flags[sym] += 1
      when nil
        flags[sym] = true
      else
        raise "Unexpected boolean '#{@arg}' after set to value #{flags[sym].inspect}"
      end
    end

    def parse_value_flag(flag:, value:, no:)
      sym = resolve(flag)
      boolean = Aargs.boolean?(sym, flag_configs: flag_configs)
      if no
        parse_negative_boolean(sym: sym, value: value)
      elsif value.nil?
        parse_boolean(sym: sym, known_boolean: boolean)
      else
        parse_flag_with_value(sym: sym, boolean: boolean, value: value)
      end
    end

    def parse_negative_boolean(sym:, value:)
      raise "Unexpected value specified with no- prefix: #{@arg}" unless value.nil?

      flags[sym] = false
      self.last_sym = nil
    end

    def parse_flag_with_value(sym:, boolean:, value:)
      raise "Unexpected value for #{inspect_flag(@arg)}: #{value.inspect}" if boolean

      self.last_sym = nil
      case flags[sym]
      when nil
        flags[sym] = value
      when Array
        flags[sym] << value
      else
        flags[sym] = [flags[sym], value]
      end
    end

    def parse_boolean(sym:, known_boolean:)
      self.last_sym = known_boolean ? nil : sym
      case flags[sym]
      when true
        flags[sym] = 2
      when Integer
        flags[sym] += 1
      when nil, false
        flags[sym] = true
      else
        self.last_sym_pending = @arg
      end
    end

    def parse_literal
      if last_sym
        parse_literal_as_value
      elsif flags.empty?
        prologue << @arg
      else # first non-switch after switches + values
        self.literal_only = true
        epilogue << @arg
      end
    end

    def parse_literal_as_value
      case flags[last_sym]
      when true
        flags[last_sym] = @arg
      when Array
        flags[last_sym] << @arg
      else
        flags[last_sym] = [flags[last_sym], @arg]
      end
      self.last_sym_pending = nil
    end
  end

  def self.parse(args_or_argv, aliases: {}, flag_configs: {})
    argv = to_argv(*args_or_argv)
    ParseState.new(aliases, flag_configs).parse(argv)
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

  def explicit?(prologue)
    prologue && prologue != DEFAULT
  end

  def if_default(prologue, value)
    return value if prologue == DEFAULT

    prologue
  end

  def if_default_not(prologue, value)
    return !value if prologue == DEFAULT

    prologue
  end

  def initialize(prologue: DEFAULT, default_flag_config: DEFAULT, flag_configs: nil, epilogue: DEFAULT, aliases: {}, program: nil)
    @program = program || begin
      %r{^(?:.*/)?(?<file>[^/]+):\d+:in} =~ caller.first
      file
    end
    @aliases = aliases.freeze
    prologue_set = explicit?(prologue)
    flag_configs_set = explicit?(flag_configs)
    epilogue_set = explicit?(epilogue)
    prologue = if_default_not(prologue, epilogue_set || flag_configs_set)
    initialize_epiprologue(:pro, prologue)
    initialize_flag_configs(default_flag_config: default_flag_config, flag_configs: flag_configs)
    epilogue = if_default_not(epilogue, prologue_set || flag_configs_set)
    initialize_epiprologue(:epi, epilogue)
    @valid = false
  end

  private

  def initialize_epiprologue(prefix, value)
    required = []
    optional = []
    instance_variable_set("@required_#{prefix}logue", required)
    instance_variable_set("@optional_#{prefix}logue", optional)
    return unless set_default_key(prefix, value).nil?

    populate_required_and_optional(prefix, value, required, optional)
    required.freeze
    optional.freeze
  end

  def set_default_key(prefix, value)
    default_key = case value
                  when true
                    "#{prefix}logue".to_sym
                  when false, Symbol
                    value
                  end
    instance_variable_set("@#{prefix}logue_key", default_key)
  end

  def populate_required_and_optional(prefix, value, required, optional)
    Array(value).each do |key|
      /^(?<key>[[:alnum:]-]*)(?<explicit_optional>\?)?$/ =~ key
      key = key.to_sym
      if explicit_optional
        optional << key
      else
        raise "required #{prefix}logue cannot follow optional #{prefix}logue" unless optional.empty?

        required << key
      end
    end
  end

  def initialize_flag_configs(default_flag_config:, flag_configs:)
    flag_configs_set = explicit?(flag_configs)
    default_flag_config = if_default_not(default_flag_config, flag_configs_set)
    @flag_configs = Hash.new(default_flag_config).merge(flag_configs || {}).freeze
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
    return arg.upcase if required?(sym)
    return "[#{arg.upcase}]" if optional?(sym)
    return '[aargs]' if sym == :any_key
    return "[#{arg.upcase} ... [#{arg.upcase}]]" if splat?(sym)
    return "--[no-]#{arg}" if boolean?(sym)

    "--#{arg}=VALUE"
  end

  def help
    lines = help_all_flags.map(&method(:flag_help)).compact
    return [basic_usage(help_all_flags)] unless any_real_help?(lines)

    [basic_usage(help_all_flags)] + help_format_lines(lines)
  end

  def help_all_flags
    @help_all_flags ||= begin
      flag_keys = flag_configs.keys
      flag_keys << :any_key if flag_configs[:any_key]
      help_prologue_keys + (flag_keys - help_prologue_keys) + help_epilogue_keys
    end
  end

  def any_real_help?(help_lines)
    return if help_lines.empty?

    help_lines.any? { |e| e[:real_help] }
  end

  def help_prologue_keys
    [required_prologue, optional_prologue, prologue_key || nil].map(&method(:Array)).flatten
  end

  def help_epilogue_keys
    [required_epilogue, optional_epilogue, epilogue_key || nil].map(&method(:Array)).flatten
  end

  def help_format_lines(lines)
    width = lines.map { |e| e[:flag] }.map(&:length).max
    lines.map do |flag:, help:, **_|
      format("  %<flag>-#{width}s : %<help>s", flag: flag, help: help)
    end
  end

  def basic_usage(all_flags)
    "Usage: #{@program} #{all_flags.map(&method(:inspect_flag)).join(' ')}"
  end

  def flag_help(flag)
    return unless (config = flag_config(flag))

    real_help = config[:help]
    flag_help = real_help || case config[:type]
                             when :boolean
                               '(switch)'
                             else
                               "(#{config[:type]})"
                             end
    { real_help: real_help, flag: inspect_flag(flag), help: flag_help } if flag_help
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

  def epilogue_keys
    @epilogue_keys ||= [required_epilogue, optional_epilogue].map(&method(:Array)).flatten
  end

  # Any extra prologue values become the beginning of the epilogue.
  def adopt_extra_prologue(parsed_prologue, consumed_prologue)
    parsed_prologue.drop(consumed_prologue.length).concat(Array(@parsed[:epilogue]))
  end

  def nil_value?(_key, value)
    # Avoid nil values since they're never returned from {@link Aargs.parse}
    value.nil?
  end

  # Reverse-merge epilogue values into {@link @values}
  def consume_epilogue(parsed_epilogue)
    # Remove any epilogue keys whose values appeared as flags:
    expected_epilogue = epilogue_keys - @values.keys
    # Convert the epilogue into a hash based on the epilogue keys we're still waiting for:
    consumed_epilogue = expected_epilogue.zip(parsed_epilogue).reject(&method(:nil_value?)).to_h
    # Reverse-merge epilogue values into {@link @values}
    @values = consumed_epilogue.merge(@values)
    # Return the remaining epilogue elements
    parsed_epilogue.drop(consumed_epilogue.length)
  end

  # @raise if there's an epilogue given but we don't expect one
  # @see epilogue_key
  def apply_epilogue(parsed_prologue, consumed_prologue)
    parsed_epilogue = adopt_extra_prologue(parsed_prologue, consumed_prologue)
    epilogue = consume_epilogue(parsed_epilogue)
    return if epilogue.empty?
    raise "Unexpected epilogue: #{epilogue.inspect}" unless epilogue_key

    @values[epilogue_key] = epilogue
    nil
  end
end
