defmodule Explorer.Market do
  @moduledoc """
  Context for data related to the cryptocurrency market.
  """

  alias Explorer.Chain.Address.CurrentTokenBalance
  alias Explorer.ExchangeRates.Token
  alias Explorer.Market.{MarketHistory, MarketHistoryCache}
  alias Explorer.{ExchangeRates, Repo}

  @eth_asset_id "43d61dcd-e413-450d-80b8-101d5e903357"

  @doc """
  Get most recent exchange rate for the given symbol.
  """
  @spec get_exchange_rate(String.t()) :: Token.t() | nil
  def get_exchange_rate(input) do
    mixin_asset_id = if(input == "ETH", do: @eth_asset_id, else: input)
    ExchangeRates.lookup(mixin_asset_id)
  end

  @doc """
  Retrieves the history for the recent specified amount of days.

  Today's date is include as part of the day count
  """
  @spec fetch_recent_history() :: [MarketHistory.t()]
  def fetch_recent_history do
    MarketHistoryCache.fetch()
  end

  @doc false
  def bulk_insert_history(records) do
    records_without_zeroes =
      records
      |> Enum.reject(fn item ->
        Decimal.equal?(item.closing_price, 0) && Decimal.equal?(item.opening_price, 0)
      end)
      # Enforce MarketHistory ShareLocks order (see docs: sharelocks.md)
      |> Enum.sort_by(& &1.date)

    Repo.insert_all(MarketHistory, records_without_zeroes, on_conflict: :nothing, conflict_target: [:date])
  end

  def add_price(%{mixin_asset_id: mixin_asset_id} = token) do
    usd_value = fetch_token_usd_value(mixin_asset_id)
    Map.put(token, :usd_value, usd_value)
  end

  def add_price(%CurrentTokenBalance{token: token} = token_balance) do
    token_with_price = add_price(token)

    Map.put(token_balance, :token, token_with_price)
  end

  def add_price(tokens) when is_list(tokens) do
    Enum.map(tokens, fn item ->
      case item do
        {token_balance, token} ->
          {token_balance, add_price(token)}

        token_balance ->
          add_price(token_balance)
      end
    end)
  end

  defp fetch_token_usd_value(mixin_asset_id) do
    case get_exchange_rate(mixin_asset_id) do
      %{usd_value: usd_value} -> usd_value
      nil -> nil
    end
  end
end
