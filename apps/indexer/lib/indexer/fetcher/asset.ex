defmodule Indexer.Fetcher.Asset do
  @moduledoc """
  Fetches information about a asset.
  """

  use Indexer.Fetcher
  use Spandex.Decorators

  alias Explorer.Chain
  alias Explorer.Chain.Hash.Address
  alias Explorer.Chain.Token
  alias Explorer.Registry.MapRetriever
  alias Indexer.{BufferedTask, Tracer}

  @behaviour BufferedTask

  @defaults [
    flush_interval: :timer.seconds(30),
    max_batch_size: 1,
    max_concurrency: 10,
    poll: true,
    task_supervisor: Indexer.Fetcher.Asset.TaskSupervisor
  ]

  @doc false
  def child_spec([init_options, gen_server_options]) do
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
    {:ok, acc} =
      Chain.stream_erc20_token(initial_acc, fn address, acc ->
        reducer.(address, acc)
      end)

    acc
  end

  @impl BufferedTask
  @decorate trace(name: "fetch", resource: "Indexer.Fetcher.Token.run/2", service: :indexer, tracer: Tracer)
  def run([token_contract_address], _json_rpc_named_arguments) do
    options = [necessity_by_association: %{[contract_address: :smart_contract] => :optional}]

    case Chain.token_from_address_hash(token_contract_address, options) do
      {:ok, %Token{} = token} ->
        update_token_asset_id(token)
    end
  end

  @doc """
  Fetches token data asynchronously given a list of `t:Explorer.Chain.Token.t/0`s.
  """
  @spec async_fetch([Address.t()]) :: :ok
  def async_fetch(token_contract_addresses) do
    BufferedTask.buffer(__MODULE__, token_contract_addresses)
  end

  defp update_token_asset_id(%Token{contract_address_hash: contract_address_hash} = token) do
    token_params = MapRetriever.get_functions_of(contract_address_hash)

    if not is_nil(token_params.asset_id) do
      {:ok, _} = Chain.update_token(%{token | updated_at: DateTime.utc_now()}, token_params)
    end

    :ok
  end
end
