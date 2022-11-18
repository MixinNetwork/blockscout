defmodule Explorer.Registry.MapRetriever do
  @moduledoc """
  Reads Token's fields using Smart Contract functions from the blockchain.
  """

  require Logger

  alias Ecto.UUID
  alias Explorer.Chain.{Hash, Token}
  alias Explorer.SmartContract.Reader

  @contract_abi [
    %{
      "constant" => true,
      "inputs" => [%{"name" => "address", "type" => "address"}],
      "name" => "assets",
      "outputs" => [
        %{
          "name" => "",
          "type" => "uint128"
        }
      ],
      "payable" => false,
      "type" => "function"
    },
  ]

  @doc """
  Read functions below in the Smart Contract given the Contract's address hash.

  * assets

  """
  @spec get_functions_of([String.t()] | Hash.t() | String.t()) :: map() | {:ok, [map()]}
  def get_functions_of(hashes) when is_list(hashes) do
    IO.inspect(1)
    requests =
      hashes
      |> Enum.flat_map(fn hash ->
        @contract_functions
        |> Enum.map(fn {method_id, args} ->
          %{contract_address: hash, method_id: method_id, args: args}
        end)
      end)

    updated_at = DateTime.utc_now()

    fetched_result =
      requests
      |> Reader.query_contracts(@contract_abi)
      |> Enum.chunk_every(1)
      |> Enum.zip(hashes)
      |> Enum.map(fn {result, hash} ->
        formatted_result =
          ["asset_id"]
          |> Enum.zip(result)
          |> format_contract_functions_result(hash)

        formatted_result
        |> Map.put(:contract_address_hash, hash)
        |> Map.put(:updated_at, updated_at)
      end)

    {:ok, fetched_result}
  end

  def get_functions_of(%Hash{byte_count: unquote(Hash.Address.byte_count())} = address) do
    address_string = Hash.to_string(address)
    get_functions_of(address_string)
  end

  def get_functions_of(contract_address_hash) when is_binary(contract_address_hash) do
    res = fetch_functions_from_contract("0x3c84B6C98FBeB813e05a7A7813F0442883450B1F", %{
      "f11b8188" => [contract_address_hash],
    })
    res = format_contract_functions_result(res, contract_address_hash)

    res
  end

  defp fetch_functions_from_contract(contract_address_hash, contract_functions) do
    max_retries = Application.get_env(:explorer, :token_functions_reader_max_retries)
    fetch_functions_with_retries(contract_address_hash, contract_functions, %{}, max_retries)
  end

  defp fetch_functions_with_retries(_contract_address_hash, _contract_functions, accumulator, 0), do: accumulator

  defp fetch_functions_with_retries(contract_address_hash, contract_functions, accumulator, retries_left)
       when retries_left > 0 do
    contract_functions_result = Reader.query_contract(contract_address_hash, @contract_abi, contract_functions, false)

    functions_with_errors =
      Enum.filter(contract_functions_result, fn function ->
        case function do
          {_, {:error, _}} -> true
          {_, {:ok, _}} -> false
        end
      end)

    if Enum.any?(functions_with_errors) do
      {:error, ""}   
    else
      contract_functions_result
    end
  end

  defp log_functions_with_errors(contract_address_hash, functions_with_errors, retries_left) do
    error_messages =
      Enum.map(functions_with_errors, fn {function, {:error, error_message}} ->
        "function: #{function} - error: #{error_message} \n"
      end)

    Logger.debug(
      [
        "<Token contract hash: #{contract_address_hash}> error while fetching metadata: \n",
        error_messages,
        "Retries left: #{retries_left - 1}"
      ],
      fetcher: :token_functions
    )
  end

  defp format_contract_functions_result(contract_functions, contract_address_hash) do
    contract_functions =
      for {method_id, {:ok, [function_data]}} <- contract_functions, into: %{} do
        if method_id === "f11b8188" do
          {:ok, asset_id} = UUID.load(Base.decode16!(Integer.to_string(function_data, 16), case: :mixed))
          {atomized_key(method_id), asset_id}
        else 
          {atomized_key(method_id), function_data}
        end 
      end

    contract_functions
    |> handle_invalid_strings(contract_address_hash)
    |> handle_large_strings
  end

  defp atomized_key("f11b8188"), do: :asset_id

  # It's a temp fix to store tokens that have names and/or symbols with characters that the database
  # doesn't accept. See https://github.com/blockscout/blockscout/issues/669 for more info.
  defp handle_invalid_strings(contract_functions, _contract_address_hash), do: contract_functions

  defp format_according_contract_address_hash(contract_address_hash) do
    String.slice(contract_address_hash, 0, 6)
  end

  defp handle_large_strings(contract_functions), do: contract_functions

  defp handle_large_string(nil), do: nil
  defp handle_large_string(string), do: handle_large_string(string, byte_size(string))
  defp handle_large_string(string, size) when size > 255, do: binary_part(string, 0, 255)
  defp handle_large_string(string, _size), do: string

  defp remove_null_bytes(string) do
    String.replace(string, "\0", "")
  end
end
