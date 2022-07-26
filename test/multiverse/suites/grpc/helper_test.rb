# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'newrelic_rpm'

class GrpcHelperTest < Minitest::Test
  include MultiverseHelpers

  class HelpedClass
    include NewRelic::Agent::Instrumentation::GRPC::Helper
  end

  def unwanted_host_patterns
    [/unwanted/.freeze].freeze
  end

  def test_class
    HelpedClass.new
  end

  def test_cleans_method_names
    input = '/method/with/leading/slash'
    output = 'method/with/leading/slash'
    assert_equal output, test_class.cleaned_method(input)
  end

  def test_cleans_method_names_as_symbols
    input = :'/method/with/leading/slash'
    output = 'method/with/leading/slash'
    assert_equal output, test_class.cleaned_method(input)
  end

  def test_does_not_clean_methods_that_do_not_need_cleaning
    input = 'method/without/leading/slash'
    assert_equal input, test_class.cleaned_method(input)
  end

  def test_confirms_that_host_is_not_on_the_denylist
    mock = MiniTest::Mock.new
    mock.expect(:[], unwanted_host_patterns, [:'instrumentation.grpc.host_denylist'])
    NewRelic::Agent.stub(:config, mock) do
      refute test_class.host_denylisted?('wanted_host')
    end
  end

  def test_confirms_that_host_is_denylisted
    mock = MiniTest::Mock.new
    mock.expect(:[], unwanted_host_patterns, [:'instrumentation.grpc.host_denylist'])
    NewRelic::Agent.stub(:config, mock) do
      assert test_class.host_denylisted?('unwanted_host')
    end
  end
end
