# frozen_string_literal: true

require_relative 'lib/aargs'
require 'pp'

ARGV = ['look', 'how', '--easy', '--this=is', 'to', 'use!'].freeze

# Example entrypoint for Aargs
class Example
  extend Aargs::Main

  def self.main(aargs)
    puts "prologue: #{aargs.prologue}"
    puts "it's so easy!" if aargs.easy?
    puts "this #{aargs.this} it!"
    puts "epilogue: #{aargs.epilogue}"
  end
end
