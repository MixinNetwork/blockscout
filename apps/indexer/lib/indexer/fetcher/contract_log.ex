defmodule Indexer.Fetcher.ContractLog do
  @moduledoc """
  Fetches information about tx logs.
  """

  use Indexer.Fetcher
  use Spandex.Decorators

  alias Ecto
  alias Ecto.UUID
  alias EthereumJSONRPC.HTTP.HTTPoison, as: RPC
  alias Explorer.Chain
  alias Explorer.Chain.Hash.Address
  alias Explorer.Chain.Token
  alias Explorer.Token.MetadataRetriever
  alias Indexer.{BufferedTask, Tracer}

  @behaviour BufferedTask

  @defaults [
    flush_interval: :timer.seconds(5),
    max_batch_size: 1,
    max_concurrency: 10,
    poll: true,
    task_supervisor: Indexer.Fetcher.ContractLog.TaskSupervisor
  ]

  @contract_logs_filter %{
    "0x3c84b6c98fbeb813e05a7a7813f0442883450b1f" => %{
      "address" => "0x3c84b6c98fbeb813e05a7a7813f0442883450b1f",
      "topics" => ["0x20df459a0f7f1bc64a42346a9e6536111a3512be01de7a0f5327a4e13b337038"]
    }
  }

  @doc false
  def child_spec([init_options, gen_server_options]) do
    :ets.new(:log, [:named_table, :set, :public])
    # first CreateAsset
    :ets.insert(:log, {"block_number", 1_880_820})
    :ets.insert(:log, {"interval", 100_000})

    {state, mergeable_init_options} = Keyword.pop(init_options, :json_rpc_named_arguments)

    unless state do
      raise ArgumentError,
            ":json_rpc_named_arguments must be provided to `#{__MODULE__}.child_spec " <>
              "to allow for json_rpc calls when running."
    end

    merged_init_opts =
      @defaults
      |> Keyword.merge(mergeable_init_options)
      |> Keyword.put(:state, state)

    Supervisor.child_spec({BufferedTask, [{__MODULE__, merged_init_opts}, gen_server_options]}, id: __MODULE__)
  end

  @impl BufferedTask
  def init(initial_acc, reducer, _) do
    contracts = ["0x3c84b6c98fbeb813e05a7a7813f0442883450b1f"]

    acc =
      Enum.reduce(contracts, initial_acc, fn adr, acc ->
        reducer.(adr, acc)
      end)

    acc
  end

  @impl BufferedTask
  @decorate trace(name: "fetch", resource: "Indexer.Fetcher.Token.run/2", service: :indexer, tracer: Tracer)
  def run([adr], _json_rpc_named_arguments) do
    loop_contract_logs(@contract_logs_filter[adr])
  end

  @spec async_fetch([Address.t()]) :: :ok
  def async_fetch(contract_addresses) do
    BufferedTask.buffer(__MODULE__, contract_addresses)
  end

  defp read_cache(key) do
    cache = :ets.lookup(:log, key)
    elem(hd(cache), 1)
  end

  defp loop_contract_logs(filter) do
    url = Application.get_env(:block_scout_web, :json_rpc)
    start = read_cache("block_number")

    block_body =
      Jason.encode!(%{
        "id" => "0",
        "jsonrpc" => "2.0",
        "method" => "eth_blockNumber",
        "params" => []
      })

    block_result = RPC.json_rpc(url, block_body, [])

    case block_result do
      {:ok, %{body: body}} ->
        data = Jason.decode!(body)["result"]
        latest = String.to_integer(String.slice(data, 2..-1), 16)

        interval = read_cache("interval")

        if start + interval > latest do
          :ets.insert(:log, {"interval", latest - start})
        end

        :ok

      _ ->
        :ok
    end

    interval = read_cache("interval")

    current_filter =
      filter
      |> Map.put("fromBlock", "0x" <> Integer.to_string(start, 16))
      |> Map.put("toBlock", "0x" <> Integer.to_string(start + interval, 16))

    body =
      Jason.encode!(%{
        "id" => "0",
        "jsonrpc" => "2.0",
        "method" => "eth_getLogs",
        "params" => [current_filter]
      })

    res = RPC.json_rpc(url, body, [])

    case res do
      {:ok, %{body: body}} ->
        data = Jason.decode!(body)["result"]

        Enum.each(data, fn x ->
          address_string = "0x" <> String.slice(hd(tl(x["topics"])), 26..-1)

          with {:ok, addr} <- Chain.string_to_address_hash(address_string),
               {:ok, uuid} <- UUID.load(Base.decode16!(String.slice(x["data"], 34..-1), case: :mixed)) do
            case Chain.token_from_address_hash(addr) do
              {:ok, token} ->
                Chain.update_token(%{token | updated_at: DateTime.utc_now()}, %{
                  :asset_id => uuid
                })

              {:error, _} ->
                params = MetadataRetriever.get_functions_of(addr)

                token = %Token{
                  :name => params.name,
                  :symbol => params.symbol,
                  :decimals => params.decimals,
                  :total_supply => params.total_supply,
                  :contract_address_hash => addr,
                  :asset_id => uuid,
                  :inserted_at => DateTime.utc_now(),
                  :updated_at => DateTime.utc_now(),
                  :type => "ERC-20"
                }

                try do
                  Chain.create_address(%{
                    :hash => address_string
                  })
                rescue
                  Ecto.ConstraintError -> nil
                end

                Chain.update_token(token, %{})
            end
          else
            {:error, _} -> :ok
          end
        end)

        :ets.insert(:log, {"block_number", start + interval})
        :ok

      {:error, _} ->
        :ok
    end

    :ok
  end
end
