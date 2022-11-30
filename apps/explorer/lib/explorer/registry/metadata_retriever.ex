defmodule Explorer.Registry.MapRetriever do
  @moduledoc """
  Reads Token's fields using Smart Contract functions from the blockchain.
  """

  alias Ecto.UUID
  alias Explorer.Chain.Hash

  import Explorer.Token.Utils, only: [fetch_functions_from_contract: 3]

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
    }
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
    res =
      fetch_functions_from_contract(
        "0x3c84B6C98FBeB813e05a7A7813F0442883450B1F",
        %{
          "f11b8188" => [contract_address_hash]
        },
        @contract_abi
      )

    formatted_res = format_contract_functions_result(res)

    formatted_res
  end

  defp format_contract_functions_result(contract_functions) do
    contract_functions =
      for {method_id, {:ok, [function_data]}} <- contract_functions, into: %{} do
        if method_id === "f11b8188" do
          asset_string = Integer.to_string(function_data, 16)

          case asset_string === "0" do
            true ->
              {atomized_key(method_id), asset_string}

            _ ->
              asset_string = String.pad_leading(asset_string, 32, "0")
              {:ok, mixin_asset_id} = UUID.load(Base.decode16!(asset_string, case: :mixed))
              {atomized_key(method_id), mixin_asset_id}
          end
        else
          {atomized_key(method_id), function_data}
        end
      end

    contract_functions
  end

  defp atomized_key("f11b8188"), do: :mixin_asset_id
end
