defmodule Explorer.Token.Utils do
  @moduledoc """
  Common code for token and registry metadata_retriever
  """

  alias Explorer.SmartContract.Reader

  require Logger

  def fetch_functions_from_contract(contract_address_hash, contract_functions, abi) do
    max_retries = Application.get_env(:explorer, :token_functions_reader_max_retries)
    fetch_functions_with_retries(contract_address_hash, contract_functions, %{}, abi, max_retries)
  end

  defp fetch_functions_with_retries(_contract_address_hash, _contract_functions, accumulator, _contract_abi, 0),
    do: accumulator

  defp fetch_functions_with_retries(contract_address_hash, contract_functions, accumulator, contract_abi, retries_left)
       when retries_left > 0 do
    contract_functions_result = Reader.query_contract(contract_address_hash, contract_abi, contract_functions, false)

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
        contract_abi,
        retries_left - 1
      )
    else
      fetch_functions_with_retries(
        contract_address_hash,
        %{},
        Map.merge(accumulator, contract_functions_result),
        contract_abi,
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
end
