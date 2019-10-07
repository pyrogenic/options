# frozen_string_literal: true

# Basic options parser
class Options
  def self.to_arg(sym)
    sym.to_s.gsub('_', '-')
  end

  def self.parse(*args, aliases: {}, **kwargs)
    args.map! do |arg|
      case arg
      when Symbol
        "--#{to_arg(arg)}"
      else
        arg
      end
    end
    kwargs.each do |arg, value|
      case value
      when TrueClass
        args << "--#{to_arg(arg)}"
      when FalseClass
        args << "--no-#{to_arg(arg)}"
      when Array
        value.each do |v|
          args << "--#{to_arg(arg)}=#{v}"
        end
      else
        arg
      end
    end
    literal_only = false
    prologue = []
    epilogue = []
    flags = {}
    last_sym = nil
    last_sym_pending = nil

    resolve = lambda do |src|
      raise "Missing value after '#{last_sym_pending}'" if last_sym_pending

      sym = src.to_sym
      aliases[sym] || sym
    end

    args.each do |arg|
      if literal_only
        epilogue << arg
        next
      end
      case arg
      when /^--$/
        literal_only = true
        last_sym = nil
      when /^-([[:alnum:]])$/
        last_sym = sym = resolve.call($1)
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

      when /^--(?<no>no-)?(?<flag>[[:alnum:]]+)(?:=(?<value>.*))?$/
        flag = Regexp.last_match[:flag]
        value = Regexp.last_match[:value]
        no = Regexp.last_match[:no]
        sym = resolve.call(flag)
        if no
          raise "Unexpected value specified with no- prefix: #{arg}" unless value.nil?

          flags[sym] = false
          last_sym = nil
        elsif value.nil?
          last_sym = sym
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
          last_sym = nil
          case flags[sym]
          when nil
            flags[sym] = value
          else
            raise 'Unexpected value flag after value set:' \
                  " #{arg} after set to #{flags[sym]}"
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
        else
          raise "Unexpected literal: #{arg}"
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

  attr_reader :aliases
  def initialize(aliases: {})
    @aliases = aliases.freeze
  end
end
