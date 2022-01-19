# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'redis'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'helpers', 'docker'))

if NewRelic::Agent::Datastores::Redis.is_supported_version?
  class NewRelic::Agent::Instrumentation::RedisInstrumentationTest < Minitest::Test
    include MultiverseHelpers
    setup_and_teardown_agent

    def after_setup
      super
      # Default timeout is 5 secs; a flushall takes longer on a busy box (i.e. CI)
      @redis = Redis.new(:host => redis_host, :timeout => 25)

      # Creating a new client doesn't actually establish a connection, so make
      # sure we do that by issuing a dummy get command, and then drop metrics
      # generated by the connect
      @redis.get('bogus')
      NewRelic::Agent.drop_buffered_data
    end

    def after_teardown
      @redis.flushall
    end

    def test_records_metrics_for_connect
      redis = Redis.new(:host => redis_host)

      in_transaction "test_txn" do
        redis.get("foo")
      end

      expected = {
        "test_txn" => {:call_count => 1},
        "OtherTransactionTotalTime" => {:call_count => 1},
        "OtherTransactionTotalTime/test_txn" => {:call_count => 1},
        ["Datastore/operation/Redis/connect", "test_txn"] => {:call_count => 1},
        "Datastore/operation/Redis/connect" => {:call_count => 1},
        ["Datastore/operation/Redis/get", "test_txn"] => {:call_count => 1},
        "Datastore/operation/Redis/get" => {:call_count => 1},
        "Datastore/Redis/allOther" => {:call_count => 2},
        "Datastore/Redis/all" => {:call_count => 2},
        "Datastore/allOther" => {:call_count => 2},
        "Datastore/all" => {:call_count => 2},
        "Datastore/instance/Redis/#{redis_host}/6379" => {:call_count => 2},
        "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all" => {:call_count => 1},
        "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther" => {:call_count => 1}
      }

      assert_metrics_recorded_exclusive(expected, :ignore_filter => /Supportability/)
    end

    def test_records_connect_tt_node_within_call_that_triggered_it
      in_transaction do
        redis = Redis.new(:host => redis_host)
        redis.get("foo")
      end

      tt = last_transaction_trace

      get_node = tt.root_node.children[0].children[0]
      assert_equal('Datastore/operation/Redis/get', get_node.metric_name)

      connect_node = get_node.children[0]
      assert_equal('Datastore/operation/Redis/connect', connect_node.metric_name)
    end

    def test_records_metrics_for_set
      in_transaction do
        @redis.set 'time', 'walk'
      end

      expected = {
        "Datastore/operation/Redis/set" => {:call_count => 1},
        "Datastore/Redis/allOther" => {:call_count => 1},
        "Datastore/Redis/all" => {:call_count => 1},
        "Datastore/allOther" => {:call_count => 1},
        "Datastore/all" => {:call_count => 1},
        "Datastore/instance/Redis/#{redis_host}/6379" => {:call_count => 1}
      }
      assert_metrics_recorded(expected)
    end

    def test_records_metrics_for_get_in_web_transaction
      in_web_transaction do
        @redis.set 'prodigal', 'sorcerer'
      end

      expected = {
        "Datastore/operation/Redis/set" => {:call_count => 1},
        "Datastore/Redis/allWeb" => {:call_count => 1},
        "Datastore/Redis/all" => {:call_count => 1},
        "Datastore/allWeb" => {:call_count => 1},
        "Datastore/all" => {:call_count => 1},
        "Datastore/instance/Redis/#{redis_host}/6379" => {:call_count => 1}
      }
      assert_metrics_recorded(expected)
    end

    def test_records_metrics_for_get_in_background_txn
      in_background_transaction do
        @redis.get 'mox sapphire'
      end

      expected = {
        "Datastore/operation/Redis/get" => {:call_count => 1},
        "Datastore/Redis/allOther" => {:call_count => 1},
        "Datastore/Redis/all" => {:call_count => 1},
        "Datastore/allOther" => {:call_count => 1},
        "Datastore/all" => {:call_count => 1},
        "Datastore/instance/Redis/#{redis_host}/6379" => {:call_count => 1}
      }
      assert_metrics_recorded(expected)
    end

    def test_records_tt_node_for_get
      in_transaction do
        @redis.get 'mox sapphire'
      end

      tt = last_transaction_trace
      get_node = tt.root_node.children[0].children[0]
      assert_equal('Datastore/operation/Redis/get', get_node.metric_name)
    end

    def test_does_not_record_statement_on_individual_command_node_by_default
      in_transaction do
        @redis.get 'mox sapphire'
      end

      tt = last_transaction_trace
      get_node = tt.root_node.children[0].children[0]

      assert_equal('Datastore/operation/Redis/get', get_node.metric_name)
      refute get_node[:statement]
    end

    def test_records_metrics_for_set_in_web_transaction
      in_web_transaction do
        @redis.get 'timetwister'
      end

      expected = {
        "Datastore/operation/Redis/get" => {:call_count => 1},
        "Datastore/Redis/allWeb" => {:call_count => 1},
        "Datastore/Redis/all" => {:call_count => 1},
        "Datastore/allWeb" => {:call_count => 1},
        "Datastore/all" => {:call_count => 1},
        "Datastore/instance/Redis/#{redis_host}/6379" => {:call_count => 1}
      }
      assert_metrics_recorded(expected)
    end

    def test_records_metrics_for_pipelined_commands
      in_transaction 'test_txn' do
        @redis.pipelined do
          @redis.get 'great log'
          @redis.get 'late log'
        end
      end

      expected = {
        "test_txn" => {:call_count => 1},
        "OtherTransactionTotalTime" => {:call_count => 1},
        "OtherTransactionTotalTime/test_txn" => {:call_count => 1},
        ["Datastore/operation/Redis/pipeline", "test_txn"] => {:call_count => 1},
        "Datastore/operation/Redis/pipeline" => {:call_count => 1},
        "Datastore/Redis/allOther" => {:call_count => 1},
        "Datastore/Redis/all" => {:call_count => 1},
        "Datastore/allOther" => {:call_count => 1},
        "Datastore/all" => {:call_count => 1},
        "Datastore/instance/Redis/#{redis_host}/6379" => {:call_count => 1},
        "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all" => {:call_count => 1},
        "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther" => {:call_count => 1}
      }
      assert_metrics_recorded_exclusive(expected, :ignore_filter => /Supportability/)
    end

    def test_records_commands_without_args_in_pipelined_block_by_default
      in_transaction do
        @redis.pipelined do
          @redis.set 'late log', 'goof'
          @redis.get 'great log'
        end
      end

      tt = last_transaction_trace
      pipeline_node = tt.root_node.children[0].children[0]

      assert_equal "set ?\nget ?", pipeline_node[:statement]
    end

    def test_records_metrics_for_multi_blocks
      in_transaction 'test_txn' do
        @redis.multi do
          @redis.get 'darkpact'
          @redis.get 'chaos orb'
        end
      end

      expected = {
        "test_txn" => {:call_count => 1},
        "OtherTransactionTotalTime" => {:call_count => 1},
        "OtherTransactionTotalTime/test_txn" => {:call_count => 1},
        ["Datastore/operation/Redis/multi", "test_txn"] => {:call_count => 1},
        "Datastore/operation/Redis/multi" => {:call_count => 1},
        "Datastore/Redis/allOther" => {:call_count => 1},
        "Datastore/Redis/all" => {:call_count => 1},
        "Datastore/allOther" => {:call_count => 1},
        "Datastore/all" => {:call_count => 1},
        "Datastore/instance/Redis/#{redis_host}/6379" => {:call_count => 1},
        "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all" => {:call_count => 1},
        "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther" => {:call_count => 1}
      }
      assert_metrics_recorded_exclusive(expected, :ignore_filter => /Supportability/)
    end

    def test_records_commands_without_args_in_tt_node_for_multi_blocks
      in_transaction do
        @redis.multi do
          @redis.set 'darkpact', 'sorcery'
          @redis.get 'chaos orb'
        end
      end

      tt = last_transaction_trace
      pipeline_node = tt.root_node.children[0].children[0]

      assert_equal("multi\nset ?\nget ?\nexec", pipeline_node[:statement])
    end

    def test_records_commands_with_args_in_tt_node_for_multi_blocks
      with_config(:'transaction_tracer.record_redis_arguments' => true) do
        in_transaction do
          @redis.multi do
            @redis.set 'darkpact', 'sorcery'
            @redis.get 'chaos orb'
          end
        end
      end

      tt = last_transaction_trace
      pipeline_node = tt.root_node.children[0].children[0]

      assert_equal("multi\nset \"darkpact\" \"sorcery\"\nget \"chaos orb\"\nexec", pipeline_node[:statement])
    end

    def test_records_instance_parameters_on_tt_node_for_get
      in_transaction do
        @redis.get("foo")
      end

      tt = last_transaction_trace

      get_node = tt.root_node.children[0].children[0]
      assert_includes(either_hostname, get_node[:host])
      assert_equal('6379', get_node[:port_path_or_id])
      assert_equal('0', get_node[:database_name])
    end

    def test_records_hostname_on_tt_node_for_get_with_unix_domain_socket
      redis = Redis.new(:host => redis_host)
      redis.send(client).stubs(:path).returns('/tmp/redis.sock')

      in_transaction do
        redis.get("foo")
      end

      tt = last_transaction_trace

      node = tt.root_node.children[0].children[0]
      assert_includes(either_hostname, node[:host])
      assert_equal('/tmp/redis.sock', node[:port_path_or_id])
    end

    def test_records_instance_parameters_on_tt_node_for_multi
      in_transaction do
        @redis.multi do
          @redis.get("foo")
        end
      end

      tt = last_transaction_trace

      node = tt.root_node.children[0].children[0]
      assert_includes(either_hostname, node[:host])
      assert_equal('6379', node[:port_path_or_id])
      assert_equal('0', node[:database_name])
    end

    def test_records_hostname_on_tt_node_for_multi_with_unix_domain_socket
      redis = Redis.new(:host => redis_host)
      redis.send(client).stubs(:path).returns('/tmp/redis.sock')

      in_transaction do
        redis.multi do
          redis.get("foo")
        end
      end

      tt = last_transaction_trace

      node = tt.root_node.children[0].children[0]
      assert_includes(either_hostname, node[:host])
      assert_equal('/tmp/redis.sock', node[:port_path_or_id])
    end

    def test_records_unknown_unknown_metric_when_error_gathering_instance_data
      redis = Redis.new(:host => redis_host)
      redis.send(client).stubs(:path).raises StandardError.new
      in_transaction do
        redis.get("foo")
      end

      assert_metrics_recorded('Datastore/instance/Redis/unknown/unknown')
    end

    def simulated_error_class
      Redis::CannotConnectError
    end

    def simulate_read_error
      redis = Redis.new(:host => redis_host)
      redis.send(client).stubs("establish_connection").raises(simulated_error_class, "Error connecting to Redis")
      redis.get "foo"
    ensure
    end

    def test_noticed_error_at_segment_and_txn_on_error
      txn = nil
      begin
        in_transaction do |redis_txn|
          txn = redis_txn
          simulate_read_error
        end
      rescue StandardError => e
        # NOOP -- allowing span and transaction to notice error
      end

      assert_segment_noticed_error txn, /Redis\/connect$/, simulated_error_class.name, /error connecting/i
      assert_transaction_noticed_error txn, simulated_error_class.name
    end

    def test_noticed_error_only_at_segment_on_error
      txn = nil
      in_transaction do |redis_txn|
        begin
          txn = redis_txn
          simulate_read_error
        rescue StandardError => e
          # NOP -- allowing ONLY span to notice error
        end
      end

      assert_segment_noticed_error txn, /Redis\/connect$/, simulated_error_class.name, /error connecting/i
      refute_transaction_noticed_error txn, simulated_error_class.name
    end

    def test_instrumentation_returns_expected_values
      assert_equal 0, @redis.del('foo')

      assert_equal 'OK', @redis.set('foo', 'bar')
      assert_equal 'bar', @redis.get('foo')
      assert_equal 1, @redis.del('foo')

      assert_equal ['OK', 'OK'], @redis.multi { @redis.set('foo', 'bar'); @redis.set('baz', 'bat') }
      assert_equal ['bar', 'bat'], @redis.multi { @redis.get('foo'); @redis.get('baz') }
      assert_equal 2, @redis.del('foo', 'baz')

      assert_equal ['OK', 'OK'], @redis.pipelined { @redis.set('foo', 'bar'); @redis.set('baz', 'bat') }
      assert_equal ['bar', 'bat'], @redis.pipelined { @redis.get('foo'); @redis.get('baz') }
      assert_equal 2, @redis.del('foo', 'baz')
    end

    def client
      if Gem::Version.new(Redis::VERSION).segments[0] < 4
        :client
      else
        :_client
      end
    end

    def redis_host
      docker? ? 'redis' : NewRelic::Agent::Hostname.get
    end

    def either_hostname
      [NewRelic::Agent::Hostname, 'redis']
    end
  end
end
