defmodule Explorer.ExchangeRatesTest do
  use ExUnit.Case, async: false

  import Mox

  alias Plug.Conn
  alias Explorer.ExchangeRates
  alias Explorer.ExchangeRates.Token
  alias Explorer.ExchangeRates.Source.TestSource

  @moduletag :capture_log

  setup :verify_on_exit!

  setup do
    # Use TestSource mock and ets table for this test set
    source_configuration = Application.get_env(:explorer, Explorer.ExchangeRates.Source)
    rates_configuration = Application.get_env(:explorer, Explorer.ExchangeRates)

    Application.put_env(:explorer, Explorer.ExchangeRates.Source, source: TestSource)
    Application.put_env(:explorer, Explorer.ExchangeRates, table_name: :rates)
    Application.put_env(:explorer, Explorer.ExchangeRates, enabled: true)

    on_exit(fn ->
      Application.put_env(:explorer, Explorer.ExchangeRates.Source, source_configuration)
      Application.put_env(:explorer, Explorer.ExchangeRates, rates_configuration)
    end)
  end

  test "init" do
    assert :ets.info(ExchangeRates.table_name()) == :undefined

    assert {:ok, %{}} == ExchangeRates.init([])
    assert_received :update
    table = :ets.info(ExchangeRates.table_name())
    refute table == :undefined
    assert table[:name] == ExchangeRates.table_name()
    assert table[:named_table]
    assert table[:read_concurrency]
    assert table[:type] == :set
    assert table[:write_concurrency]
  end

  describe "ticker fetch task" do
    setup do
      ExchangeRates.init([])
      :ok
    end

    test "with successful fetch" do
      expected_token = %Token{
        available_supply: Decimal.new("1000000.0"),
        total_supply: Decimal.new("1000000.0"),
        btc_value: Decimal.new("1.000"),
        id: "test_id",
        last_updated: DateTime.utc_now(),
        market_cap_usd: Decimal.new("1000000.0"),
        name: "test_name",
        symbol: "test_symbol",
        usd_value: Decimal.new("1.0"),
        volume_24h_usd: Decimal.new("1000.0"),
        mixin_asset_id: "43d61dcd-e413-450d-80b8-101d5e903357"
      }

      expected_mixin_asset_id = expected_token.mixin_asset_id
      expected_tuple = Token.to_tuple(expected_token)

      state = %{}

      assert {:noreply, ^state} = ExchangeRates.handle_info({nil, {:ok, [expected_token]}}, state)

      assert [^expected_tuple] = :ets.lookup(ExchangeRates.table_name(), expected_mixin_asset_id)
    end
  end

  test "list/0" do
    ExchangeRates.init([])

    rates = [
      %Token{Token.null() | mixin_asset_id: "z"},
      %Token{Token.null() | mixin_asset_id: "a"}
    ]

    expected_rates = Enum.reverse(rates)
    for rate <- rates, do: :ets.insert(ExchangeRates.table_name(), Token.to_tuple(rate))

    assert expected_rates == ExchangeRates.list()
  end

  test "lookup/1" do
    ExchangeRates.init([])

    z = %Token{Token.null() | mixin_asset_id: "z"}

    rates = [z, %Token{Token.null() | mixin_asset_id: "a"}]

    for rate <- rates, do: :ets.insert(ExchangeRates.table_name(), Token.to_tuple(rate))

    assert z == ExchangeRates.lookup("z")
    assert nil == ExchangeRates.lookup("nope")
  end

  test "lookup when disabled" do
    Application.put_env(:explorer, Explorer.ExchangeRates, enabled: false)

    assert nil == ExchangeRates.lookup("z")
  end
end
