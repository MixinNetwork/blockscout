defmodule Explorer.Registry.MapRetriever do
  @moduledoc """
  Reads Token's fields using Smart Contract functions from the blockchain.
  """

  require Logger

  alias Ecto.UUID
  alias Explorer.Chain.Hash
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
      log_functions_with_errors(contract_address_hash, functions_with_errors, retries_left)

      contract_functions_with_errors =
        Map.take(
          contract_functions,
          Enum.map(functions_with_errors, fn {function, _status} -> function end)
        )

      fetch_functions_with_retries(
        contract_address_hash,
        contract_functions_with_errors,
        Map.merge(accumulator, contract_functions_result),
        retries_left - 1
      )
    else
      fetch_functions_with_retries(
        contract_address_hash,
        %{},
        Map.merge(accumulator, contract_functions_result),
        0
      )
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
          asset_string = Integer.to_string(function_data, 16)
          case asset_string === "0" do
            true -> 
             {atomized_key(method_id), asset_string}
            _ ->
             asset_string = String.pad_leading(asset_string, 32, "0")
             {:ok, asset_id} = UUID.load(Base.decode16!(asset_string, case: :mixed))
             {atomized_key(method_id), asset_id}
          end
        else 
          {atomized_key(method_id), function_data}
        end 
      end

    contract_functions
  end

  defp atomized_key("f11b8188"), do: :asset_id
end
