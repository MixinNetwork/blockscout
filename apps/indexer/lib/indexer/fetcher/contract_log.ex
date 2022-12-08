defmodule Indexer.Fetcher.ContractLog do
  @moduledoc """
  Fetches information about tx logs.
  """
  @dialyzer {:nowarn_function, loop_contract_logs: 1}

  require Decimal

  use Indexer.Fetcher
  use Spandex.Decorators

  alias Ecto
  alias Ecto.UUID
  alias EthereumJSONRPC.HTTP.HTTPoison, as: RPC
  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.Address, as: ChainAddress
  alias Explorer.Chain.Hash.Address
  alias Explorer.Chain.Token
  alias Explorer.MixinApi
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

  @registry_contract "0x3c84b6c98fbeb813e05a7a7813f0442883450b1f"
  @create_asset_topic "0x20df459a0f7f1bc64a42346a9e6536111a3512be01de7a0f5327a4e13b337038"

  @contract_logs_filter %{
    @registry_contract => %{
      "address" => @registry_contract,
      "topics" => [@create_asset_topic]
    }
  }

  @first_create_asset_block 1_880_820

  @doc false
  def child_spec([init_options, gen_server_options]) do
    :ets.new(:log, [:named_table, :set, :public])
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
    contracts = [@registry_contract]

    acc =
      Enum.reduce(contracts, initial_acc, fn adr, acc ->
        reducer.(adr, acc)
      end)

    acc
  end

  @impl BufferedTask
  @decorate trace(name: "fetch", resource: "Indexer.Fetcher.ContractLog.run/2", service: :indexer, tracer: Tracer)
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

  defp get_last_block_number do
    b = Chain.get_last_fetched_counter("asset_counter")

    case Decimal.compare(b, Decimal.new(0)) do
      :eq -> @first_create_asset_block
      _ -> Decimal.to_integer(b)
    end
  end

  defp fetch_asset_native_contract_address(uuid) do
    resp = MixinApi.request("/network/assets/#{uuid}")

    case resp do
      {:ok, asset} ->
        if(asset["asset_key"] == uuid or asset["asset_key"] == "0x0000000000000000000000000000000000000000",
          do: nil,
          else: asset["asset_key"]
        )

      _ ->
        nil
    end
  end

  defp loop_contract_logs(filter) do
    url = Application.get_env(:block_scout_web, :json_rpc)
    start = get_last_block_number()

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
            native_contract_address = fetch_asset_native_contract_address(uuid)

            case Chain.token_from_address_hash(addr) do
              {:ok, token} ->
                Chain.update_token(%{token | updated_at: DateTime.utc_now()}, %{
                  :mixin_asset_id => uuid
                })

              {:error, _} ->
                params =
                  addr
                  |> MetadataRetriever.get_functions_of()
                  |> Map.put(:mixin_asset_id, uuid)
                  |> Map.put(:native_contract_address, native_contract_address)
                  |> Map.put(:type, "ERC-20")
                  |> Map.put(:inserted_at, DateTime.utc_now())
                  |> Map.put(:updated_at, DateTime.utc_now())

                a = Repo.get(ChainAddress, addr)

                if is_nil(a) do
                  Chain.create_address(%{
                    :hash => address_string
                  })
                end

                Chain.update_token(
                  %Token{
                    contract_address_hash: addr
                  },
                  params
                )
            end
          else
            {:error, _} -> :ok
          end
        end)

        Chain.upsert_last_fetched_counter(%{
          counter_type: "asset_counter",
          value: start + interval
        })

        :ok

      {:error, _} ->
        :ok
    end

    :ok
  end
end
