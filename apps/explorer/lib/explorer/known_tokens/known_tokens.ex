defmodule Explorer.KnownTokens do
  @moduledoc """
  Local cache for known tokens addresses. This fetches and exposes a mapping from a token symbol to the known contract
  address for the token with that symbol. This data can be consumed through the Market module.

  Data is updated every 1 hour.
  """

  use GenServer

  require Logger

  alias Explorer.Chain.Hash
  alias Explorer.KnownTokens.Source

  @interval :timer.hours(1)
  @table_name :known_tokens

  @impl GenServer
  def handle_info(:update, state) do
    Logger.debug(fn -> "Updating cached known tokens" end)

    fetch_known_tokens()

    {:noreply, state}
  end

  # Callback for successful fetch
  @impl GenServer
  def handle_info({_ref, {:ok, list}}, state) do
    if store() == :ets do
      tokens = if(is_list(list), do: list, else: list["data"])
      records = Enum.map(tokens, fn x -> to_tuple(x) end)

      :ets.insert(table_name(), records)
    end

    {:noreply, state}
  end

  # Callback for errored fetch
  @impl GenServer
  def handle_info({_ref, {:error, reason}}, state) do
    Logger.warn(fn -> "Failed to get known tokens with reason '#{reason}'." end)

    fetch_known_tokens()

    {:noreply, state}
  end

  # Callback that a monitored process has shutdown
  @impl GenServer
  def handle_info({:DOWN, _, :process, _, _}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def init(_) do
    send(self(), :update)
    :timer.send_interval(@interval, :update)

    table_opts = [
      :set,
      :named_table,
      :public,
      read_concurrency: true
    ]

    if store() == :ets do
      :ets.new(table_name(), table_opts)
    end

    {:ok, %{}}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Lists known tokens.
  """
  @spec list :: [{String.t(), Hash.Address.t()}]
  def list do
    if enabled?() do
      list_from_store(store())
    else
      []
    end
  end

  @doc """
  Returns a specific address from the known tokens by symbol
  """
  @spec lookup(String.t()) :: {:ok, tuple()} | {:error, :not_found} | {:error, :no_cache}
  def lookup(asset_id) do
    if store() == :ets && enabled?() do
      if ets_table_exists?(table_name()) do
        case :ets.lookup(table_name(), asset_id) do
          [res | _] -> {:ok, res}
          [] -> {:error, :not_found}
        end
      else
        {:error, :no_cache}
      end
    else
      {:error, :no_cache}
    end
  end

  defp ets_table_exists?(table) do
    :ets.whereis(table) !== :undefined
  end

  @doc false
  @spec table_name() :: atom()
  def table_name do
    config(:table_name) || @table_name
  end

  @spec config(atom()) :: term
  defp config(key) do
    Application.get_env(:explorer, __MODULE__, [])[key]
  end

  @spec fetch_known_tokens :: Task.t()
  defp fetch_known_tokens do
    Task.Supervisor.async_nolink(Explorer.MarketTaskSupervisor, fn ->
      Source.fetch_known_tokens()
    end)
  end

  defp list_from_store(:ets) do
    table_name()
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.map(&Hash.Address.cast/1)
    |> Enum.sort()
  end

  defp list_from_store(_), do: []

  defp store do
    config(:store) || :ets
  end

  defp enabled? do
    Application.get_env(:explorer, __MODULE__, [])[:enabled] == true
  end

  defp to_tuple(asset) do
    {asset["asset_id"], asset["chain_id"], asset["name"], asset["symbol"], asset["icon_url"]}
  end
end
