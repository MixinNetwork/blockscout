defmodule Explorer.Token.MetadataRetriever do
  @moduledoc """
  Reads Token's fields using Smart Contract functions from the blockchain.
  """

  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.{Hash, Token}
  alias Explorer.SmartContract.Reader

  import Explorer.Token.Utils, only: [fetch_functions_from_contract: 3]

  @contract_abi [
    %{
      "constant" => true,
      "inputs" => [],
      "name" => "name",
      "outputs" => [
        %{
          "name" => "",
          "type" => "string"
        }
      ],
      "payable" => false,
      "type" => "function"
    },
    %{
      "constant" => true,
      "inputs" => [],
      "name" => "name",
      "outputs" => [
        %{"name" => "", "type" => "bytes32"}
      ],
      "payable" => false,
      "type" => "function"
    },
    %{
      "constant" => true,
      "inputs" => [],
      "name" => "decimals",
      "outputs" => [
        %{
          "name" => "",
          "type" => "uint8"
        }
      ],
      "payable" => false,
      "type" => "function"
    },
    %{
      "constant" => true,
      "inputs" => [],
      "name" => "totalSupply",
      "outputs" => [
        %{
          "name" => "",
          "type" => "uint256"
        }
      ],
      "payable" => false,
      "type" => "function"
    },
    %{
      "constant" => true,
      "inputs" => [],
      "name" => "symbol",
      "outputs" => [
        %{
          "name" => "",
          "type" => "string"
        }
      ],
      "payable" => false,
      "type" => "function"
    },
    %{
      "constant" => true,
      "inputs" => [],
      "name" => "symbol",
      "outputs" => [
        %{
          "name" => "",
          "type" => "bytes32"
        }
      ],
      "payable" => false,
      "type" => "function"
    }
  ]

  # 18160ddd = keccak256(totalSupply())
  # 313ce567 = keccak256(decimals())
  # 06fdde03 = keccak256(name())
  # 95d89b41 = keccak256(symbol())
  @contract_functions %{
    "18160ddd" => [],
    "313ce567" => [],
    "06fdde03" => [],
    "95d89b41" => []
  }

  # 18160ddd = keccak256(totalSupply())
  @total_supply_function %{
    "18160ddd" => []
  }

  @doc """
  Read functions below in the Smart Contract given the Contract's address hash.

  * totalSupply
  * decimals
  * name
  * symbol

  This function will return a map with functions that were read in the Smart Contract, for instance:

  * Given that all functions were read:
  %{
    name: "BNT",
    decimals: 18,
    total_supply: 1_000_000_000_000_000_000,
    symbol: nil
  }

  * Given that some of them were read:
  %{
    name: "BNT",
    decimals: 18
  }

  It will retry to fetch each function in the Smart Contract according to :token_functions_reader_max_retries
  configured in the application env case one of them raised error.
  """
  @spec get_functions_of([String.t()] | Hash.t() | String.t()) :: map() | {:ok, [map()]}
  def get_functions_of(hashes) when is_list(hashes) do
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
      |> Enum.chunk_every(4)
      |> Enum.zip(hashes)
      |> Enum.map(fn {result, hash} ->
        formatted_result =
          ["name", "totalSupply", "decimals", "symbol"]
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
    res =
      contract_address_hash
      |> fetch_functions_from_contract(@contract_functions, @contract_abi)
      |> format_contract_functions_result(contract_address_hash)

    if res == %{} do
      token_to_update =
        Token
        |> Repo.get_by(contract_address_hash: contract_address_hash)
        |> Repo.preload([:contract_address])

      set_skip_metadata(token_to_update)
    end

    res
  end

  def set_skip_metadata(token_to_update) do
    Chain.update_token(%{token_to_update | updated_at: DateTime.utc_now()}, %{skip_metadata: true})
  end

  def get_total_supply_of(contract_address_hash) when is_binary(contract_address_hash) do
    contract_address_hash
    |> fetch_functions_from_contract(@total_supply_function, @contract_abi)
    |> format_contract_functions_result(contract_address_hash)
  end

  defp format_contract_functions_result(contract_functions, contract_address_hash) do
    contract_functions =
      for {method_id, {:ok, [function_data]}} <- contract_functions, into: %{} do
        {atomized_key(method_id), function_data}
      end

    contract_functions
    |> handle_invalid_strings(contract_address_hash)
    |> handle_large_strings
  end

  defp atomized_key("decimals"), do: :decimals
  defp atomized_key("name"), do: :name
  defp atomized_key("symbol"), do: :symbol
  defp atomized_key("totalSupply"), do: :total_supply
  defp atomized_key("313ce567"), do: :decimals
  defp atomized_key("06fdde03"), do: :name
  defp atomized_key("95d89b41"), do: :symbol
  defp atomized_key("18160ddd"), do: :total_supply

  # It's a temp fix to store tokens that have names and/or symbols with characters that the database
  # doesn't accept. See https://github.com/blockscout/blockscout/issues/669 for more info.
  defp handle_invalid_strings(%{name: name, symbol: symbol} = contract_functions, contract_address_hash) do
    name = handle_invalid_name(name, contract_address_hash)
    symbol = handle_invalid_symbol(symbol)

    %{contract_functions | name: name, symbol: symbol}
  end

  defp handle_invalid_strings(%{name: name} = contract_functions, contract_address_hash) do
    name = handle_invalid_name(name, contract_address_hash)

    %{contract_functions | name: name}
  end

  defp handle_invalid_strings(%{symbol: symbol} = contract_functions, _contract_address_hash) do
    symbol = handle_invalid_symbol(symbol)

    %{contract_functions | symbol: symbol}
  end

  defp handle_invalid_strings(contract_functions, _contract_address_hash), do: contract_functions

  defp handle_invalid_name(nil, _contract_address_hash), do: nil

  defp handle_invalid_name(name, contract_address_hash) do
    case String.valid?(name) do
      true -> remove_null_bytes(name)
      false -> format_according_contract_address_hash(contract_address_hash)
    end
  end

  defp handle_invalid_symbol(symbol) do
    case String.valid?(symbol) do
      true -> remove_null_bytes(symbol)
      false -> nil
    end
  end

  defp format_according_contract_address_hash(contract_address_hash) do
    String.slice(contract_address_hash, 0, 6)
  end

  defp handle_large_strings(%{name: name, symbol: symbol} = contract_functions) do
    [name, symbol] = Enum.map([name, symbol], &handle_large_string/1)

    %{contract_functions | name: name, symbol: symbol}
  end

  defp handle_large_strings(%{name: name} = contract_functions) do
    name = handle_large_string(name)

    %{contract_functions | name: name}
  end

  defp handle_large_strings(%{symbol: symbol} = contract_functions) do
    symbol = handle_large_string(symbol)

    %{contract_functions | symbol: symbol}
  end

  defp handle_large_strings(contract_functions), do: contract_functions

  defp handle_large_string(nil), do: nil
  defp handle_large_string(string), do: handle_large_string(string, byte_size(string))

  defp handle_large_string(string, size) when size > 255,
    do: string |> binary_part(0, 255) |> String.chunk(:valid) |> List.first()

  defp handle_large_string(string, _size), do: string

  defp remove_null_bytes(string) do
    String.replace(string, "\0", "")
  end
end
