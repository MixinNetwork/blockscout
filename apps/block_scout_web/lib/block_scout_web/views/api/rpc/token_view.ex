defmodule BlockScoutWeb.API.RPC.TokenView do
  use BlockScoutWeb, :view

  alias BlockScoutWeb.API.RPC.RPCView

  def render("gettoken.json", %{token: token}) do
    RPCView.render("show.json", data: prepare_token(token))
  end

  def render("gettokenholders.json", %{token_holders: token_holders}) do
    data = Enum.map(token_holders, &prepare_token_holder/1)
    RPCView.render("show.json", data: data)
  end

  def render("getmixinassets.json", %{asset_list: asset_list}) do
    data = Enum.map(asset_list, &prepare_asset/1)
    RPCView.render("show.json", data: data)
  end

  def render("search.json", %{list: asset_list}) do
    data = Enum.map(asset_list, &prepare_asset/1)
    RPCView.render("show.json", data: data)
  end

  def render("error.json", assigns) do
    RPCView.render("error.json", assigns)
  end

  defp prepare_token(token) do
    %{
      "type" => token.type,
      "name" => token.name,
      "symbol" => token.symbol,
      "totalSupply" => to_string(token.total_supply),
      "decimals" => to_string(token.decimals),
      "contractAddress" => to_string(token.contract_address_hash),
      "mixinAssetId" => token.mixin_asset_id
    }
  end

  defp prepare_asset(asset) do
    a = %{
      "contractAddress" => to_string(asset.contract_address_hash),
      "nativeContractAddress" => if(is_nil(asset.native_contract_address), do: "", else: asset.native_contract_address),
      "mixinAssetId" => asset.mixin_asset_id,
      "name" => asset.name,
      "decimals" => to_string(asset.decimals),
      "symbol" => asset.symbol,
      "type" => asset.type,
      "priceUSD" => asset.price_usd,
      "priceBTC" => asset.price_btc,
    }
   
    case Map.has_key?(asset, :chain_id) and Map.has_key?(asset, :chain_name) and Map.has_key?(asset, :chain_symbol) and Map.has_key?(asset, :chain_icon_url) do
      true ->
       a
       |> Map.put("chainId", asset.chain_id)
       |> Map.put("chainName", asset.chain_name)
       |> Map.put("chainSymbol", asset.chain_symbol)
       |> Map.put("chainIconUrl", asset.chain_icon_url)

      false -> a
    end 
  end

  defp prepare_token_holder(token_holder) do
    %{
      "address" => to_string(token_holder.address_hash),
      "value" => token_holder.value
    }
  end
end
