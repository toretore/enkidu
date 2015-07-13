require 'minitest/autorun'

class EnkiduTestCase < MiniTest::Test

  def setup
    @setups && @setups.each do |setup|
      setup.call
    end
  end

  class << self


    def setup(&b)
      @setups ||= []
      @setups << b
    end


    def test(name, &b)
      define_method "test_#{name}", &b
    end


  end

end
