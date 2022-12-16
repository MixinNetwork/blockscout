defmodule Explorer.ExchangeRates.Source do
  @moduledoc """
  Behaviour for fetching exchange rates from external sources.
  """
  alias Explorer.{Chain, MixinApi}
  alias Explorer.ExchangeRates.Source.CoinGecko
  alias Explorer.ExchangeRates.Token
  alias HTTPoison.{Error, Response}

  @eth_asset_id "43d61dcd-e413-450d-80b8-101d5e903357"

  @doc """
  Fetches exchange rates for currencies/tokens.
  """
  @spec fetch_exchange_rates(module) :: {:ok, [Token.t()]} | {:error, any}
  def fetch_exchange_rates(source \\ exchange_rates_source()) do
    source_url = source.source_url()
    resp = fetch_exchange_rates_request(source, source_url, source.headers())
    update_price_with_mixin_asset(resp)
  end

  @spec fetch_exchange_rates_for_token(String.t()) :: {:ok, [Token.t()]} | {:error, any}
  def fetch_exchange_rates_for_token(symbol) do
    source_url = CoinGecko.source_url(symbol)
    headers = CoinGecko.headers()
    fetch_exchange_rates_request(CoinGecko, source_url, headers)
  end

  @spec fetch_exchange_rates_for_token_address(String.t()) :: {:ok, [Token.t()]} | {:error, any}
  def fetch_exchange_rates_for_token_address(address_hash) do
    source_url = CoinGecko.source_url(address_hash)
    headers = CoinGecko.headers()
    fetch_exchange_rates_request(CoinGecko, source_url, headers)
  end

  def fetch_exchange_rates_from_mixin do
    {:ok, [eth_rate]} = fetch_exchange_rates()

    resp = MixinApi.request("/network/assets/top")

    case resp do
      {:ok, asset_list} ->
        tokens = Chain.list_erc20_tokens_with_mixin_asset_id()

        asset_map =
          Enum.reduce(asset_list, %{}, fn x, acc ->
            Map.put(acc, x["asset_id"], x)
          end)

        token_rate =
          Enum.map(tokens, fn t ->
            asset = asset_map[t.mixin_asset_id]
            get_exchange_rate_token(asset)
          end)

        token_list = Enum.filter([eth_rate | token_rate], fn t -> not is_nil(t) end)

        {:ok, token_list}

      _ ->
        {:ok, [eth_rate]}
    end
  end

  defp update_price_with_mixin_asset(resp) do
    asset = fetch_eth_asset()

    case is_nil(asset) do
      true ->
        resp

      false ->
        case resp do
          {:ok, data} ->
            token =
              data
              |> List.first()
              |> Map.put(:btc_value, to_decimal(asset["price_btc"]))
              |> Map.put(:usd_value, to_decimal(asset["price_usd"]))
              |> Map.put(:mixin_asset_id, asset["asset_id"])

            {:ok, [token]}

          _ ->
            token_rate = %Token{
              available_supply: to_decimal(asset["amount"]),
              total_supply: to_decimal(asset["amount"]),
              btc_value: to_decimal(asset["price_btc"]),
              id: "",
              last_updated: DateTime.utc_now(),
              market_cap_usd: to_decimal(asset["capitalization"]),
              name: asset["name"],
              symbol: String.upcase(asset["symbol"]),
              usd_value: to_decimal(asset["price_usd"]),
              volume_24h_usd: to_decimal(0),
              mixin_asset_id: asset["asset_id"]
            }

            {:ok, [token_rate]}
        end
    end
  end

  defp get_exchange_rate_token(asset) do
    case asset do
      nil ->
        nil

      _ ->
        %Token{
          available_supply: to_decimal(asset["amount"]),
          total_supply: to_decimal(asset["total_supply"]),
          btc_value: to_decimal(asset["price_btc"]),
          id: "",
          last_updated: DateTime.utc_now(),
          market_cap_usd: to_decimal(asset["capitalization"]),
          name: asset["name"],
          symbol: String.upcase(asset["symbol"]),
          usd_value: to_decimal(asset["price_usd"]),
          volume_24h_usd: to_decimal(0),
          mixin_asset_id: asset["asset_id"]
        }
    end
  end

  defp fetch_eth_asset do
    url = "/network/assets/#{@eth_asset_id}"

    case MixinApi.request(url) do
      {:ok, asset} -> asset
      {:error, _} -> nil
    end
  end

  defp fetch_exchange_rates_request(_source, source_url, _headers) when is_nil(source_url),
    do: {:error, "Source URL is nil"}

  defp fetch_exchange_rates_request(source, source_url, headers) do
    case http_request(source_url, headers) do
      {:ok, result} = resp ->
        if is_map(result) do
          result_formatted =
            result
            |> source.format_data()

          {:ok, result_formatted}
        else
          resp
        end

      resp ->
        resp
    end
  end

  @doc """
  Callback for api's to format the data returned by their query.
  """
  @callback format_data(String.t()) :: [any]

  @doc """
  Url for the api to query to get the market info.
  """
  @callback source_url :: String.t()

  @callback source_url(String.t()) :: String.t() | :ignore

  @callback headers :: [any]

  def headers do
    [{"Content-Type", "application/json"}]
  end

  def decode_json(data) do
    Jason.decode!(data)
  rescue
    _ -> data
  end

  def to_decimal(nil), do: nil

  def to_decimal(%Decimal{} = value), do: value

  def to_decimal(value) when is_float(value) do
    Decimal.from_float(value)
  end

  def to_decimal(value) when is_integer(value) or is_binary(value) do
    Decimal.new(value)
  end

  @spec exchange_rates_source() :: module()
  defp exchange_rates_source do
    config(:source) || Explorer.ExchangeRates.Source.CoinGecko
  end

  @spec config(atom()) :: term
  defp config(key) do
    Application.get_env(:explorer, __MODULE__, [])[key]
  end

  def http_request(source_url, additional_headers) do
    case HTTPoison.get(source_url, headers() ++ additional_headers) do
      {:ok, %Response{body: body, status_code: 200}} ->
        parse_http_success_response(body)

      {:ok, %Response{body: body, status_code: status_code}} when status_code in 400..526 ->
        parse_http_error_response(body)

      {:ok, %Response{status_code: status_code}} when status_code in 300..308 ->
        {:error, "Source redirected"}

      {:ok, %Response{status_code: _status_code}} ->
        {:error, "Source unexpected status code"}

      {:error, %Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp parse_http_success_response(body) do
    body_json = decode_json(body)

    cond do
      is_map(body_json) ->
        {:ok, body_json}

      is_list(body_json) ->
        {:ok, body_json}

      true ->
        {:ok, body}
    end
  end

  defp parse_http_error_response(body) do
    body_json = decode_json(body)

    if is_map(body_json) do
      {:error, body_json["error"]}
    else
      {:error, body}
    end
  end
end
