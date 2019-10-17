# frozen_string_literal: true

require_relative "lib/aargs"
require "pp"

ARGV = ["look", "how", "--easy", "--this=is", "to", "use!"]

class Example
  extend Aargs::Main

  def self.main(aargs)
    puts("self.main")
    pp(aargs)
  end
end
