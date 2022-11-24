defmodule Indexer.Fetcher.ContractLog do
  @moduledoc """
  Fetches information about tx logs.
  """

  use Indexer.Fetcher
  use Spandex.Decorators

  alias Ecto.UUID
  alias Explorer.Chain
  alias Explorer.Chain.Hash.Address
  alias Explorer.Chain.Token
  alias EthereumJSONRPC.HTTP.HTTPoison, as: RPC 
  alias Explorer.Registry.MapRetriever
  alias Indexer.{BufferedTask, Tracer}

  @behaviour BufferedTask

  @defaults [
    flush_interval: :timer.seconds(1),
    max_batch_size: 1,
    max_concurrency: 10,
    poll: true,
    task_supervisor: Indexer.Fetcher.Asset.TaskSupervisor
  ]

  @contract_logs_filter %{
    "0x3c84b6c98fbeb813e05a7a7813f0442883450b1f" => %{
      "address" => "0x3c84b6c98fbeb813e05a7a7813f0442883450b1f",
       "topics" => ["0x20df459a0f7f1bc64a42346a9e6536111a3512be01de7a0f5327a4e13b337038"],
    }
  }

  @doc false
  def child_spec([init_options, gen_server_options]) do
    IO.inspect("child_spec")
    cache = :ets.new(:block_number, [:named_table, :set, :public])
    # :ets.insert(:block_number, {"block_number", 1880545})
    :ets.insert(:block_number, {"block_number", 11351655})

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
    acc = Enum.reduce(contracts, initial_acc, fn adr, acc ->
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

  defp loop_contract_logs(filter) do
    cache =  :ets.lookup(:block_number, "block_number")
    block_number = elem(hd(cache), 1)
    current_filter =
      filter
      |> Map.put("fromBlock", "0x" <> Integer.to_string(block_number, 16))
      |> Map.put("toBlock", "0x" <> Integer.to_string(block_number + 20))

    url = Application.get_env(:block_scout_web, :json_rpc)
    body = Jason.encode!(%{
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
            addr = Chain.string_to_address_hash("0x" <> String.slice(hd(tl(x["topics"])), 26..-1))
            uuid = UUID.load(Base.decode16!(String.slice(x["data"], 34..-1), case: :mixed))
            IO.inspect("0x" <> String.slice(hd(tl(x["topics"])), 26..-1))
            IO.inspect(uuid)
          end)
      {:error, _} -> :ok
    end
    :ets.insert(:block_number, {"block_number", block_number + 20})  
     
    :ok
  end
end
