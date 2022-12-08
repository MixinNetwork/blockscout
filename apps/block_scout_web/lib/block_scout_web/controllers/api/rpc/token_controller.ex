defmodule BlockScoutWeb.API.RPC.TokenController do
  use BlockScoutWeb, :controller

  alias BlockScoutWeb.API.RPC.Helpers
  alias Explorer.{Chain, PagingOptions}

  @filter_assets [
    "4d8c508b-91c5-375b-92b0-ee702ed2dac5", # USDT ERC20
    "f5ef6b5d-cc5a-3d90-b2c0-a2fd386e7a3c", # BOX
    "336d5d97-329c-330d-8e62-2b7c9ba40ea0", # IQ
    "c94ac88f-4671-3976-b60a-09064f1811e8", # XIN
    "2566bf58-c4de-3479-8c55-c137bb7fe2ae", # ONE
    "6cfe566e-4aad-470b-8c9a-2fd35b49c68d", # EOS
    "31d2ea9c-95eb-3355-b65b-ba096853bc18", # pUSD
    "eea900a8-b327-488c-8d8d-1428702fe240", # MOB
    "9b180ab6-6abe-3dc0-a13f-04169eb34bfa", # USDC
    "6770a1e5-6086-44d5-b60f-545f9d9e8ffd", # DOGE
    "a31e847e-ca87-3162-b4d1-322bc552e831", # UNI
    "965e5c6e-434c-3fa9-b780-c50f43cd955c", # CNB
    "43d61dcd-e413-450d-80b8-101d5e903357", # ETH
    "dcde18b9-f015-326f-b8b1-5b820a060e44", # SHIB
    "aa189c4c-99ca-39eb-8d96-71a8f6f7218a", # AKITA
    "4f2ec12c-22f4-3a9e-b757-c84b6415ea8f", # RUM
    "08285081-e1d8-4be6-9edc-e203afa932da", # FIL
    "9c612618-ca59-4583-af34-be9482f5002d", # AKT
    "c3dc19ae-d087-3279-ac51-dc655940256a", # MANA
    "2f5bef0e-d41a-3cf3-b6fa-b8dd0d8a3327", # EURT
    "14693c1a-d835-3572-b9b4-e0cbb62099e5", # PINK
    "54c61a72-b982-4034-a556-0d99e3c21e39", # DOT
    "25dabac5-056a-48ff-b9f9-f67395dc407c", # TRX
    "706b6f84-3333-4e55-8e89-275e71ce9803", # ALGO
    "56e63c06-b506-4ec5-885a-4a5ac17b83c1", # XLM
    "c6d0c728-2624-429b-8e0d-d9d19b6592fa", # BTC
    "f6f1c01c-8489-3346-b127-dc0dc09b9ce7", # LINK
    "23dfb5a5-5d7b-48b6-905f-3970e3176e27", # XRP
    "9682b8e9-6f16-3729-b07b-bc3bc56e5d79", # MATIC
    "b91e18ff-a9ae-3dc7-8679-e935d9a4b34b", # USDT TRC20
    "d243386e-6d84-42e6-be03-175be17bf275", # CKB
    "76c802a2-7c88-447f-a93e-c29c9e5dd9c8", # LTC
    "64692c23-8971-4cf4-84a7-4dd1271dd887", # SOL
    "17f78d7c-ed96-40ff-980c-5dc62fecbc85", # BNB, Binance
    "b5289c48-ec3a-3cdb-b2c4-0913d1812cd5", # mAED
    "1949e683-6a08-49e2-b087-d6b72398588f", # BNB, Binance Smart Chain
  ]

  def gettoken(conn, params) do
    with {:contractaddress_param, {:ok, contractaddress_param}} <- fetch_contractaddress(params),
         {:format, {:ok, address_hash}} <- to_address_hash(contractaddress_param),
         {:token, {:ok, token}} <- {:token, Chain.token_from_address_hash(address_hash)} do
      render(conn, "gettoken.json", %{token: token})
    else
      {:contractaddress_param, :error} ->
        render(conn, :error, error: "Query parameter contract address is required")

      {:format, :error} ->
        render(conn, :error, error: "Invalid contract address hash")

      {:token, {:error, :not_found}} ->
        render(conn, :error, error: "contract address not found")
    end
  end

  def gettokenholders(conn, params) do
    with pagination_options <- Helpers.put_pagination_options(%{}, params),
         {:contractaddress_param, {:ok, contractaddress_param}} <- fetch_contractaddress(params),
         {:format, {:ok, address_hash}} <- to_address_hash(contractaddress_param) do
      options_with_defaults =
        pagination_options
        |> Map.put_new(:page_number, 0)
        |> Map.put_new(:page_size, 10)

      options = [
        paging_options: %PagingOptions{
          key: nil,
          page_number: options_with_defaults.page_number,
          page_size: options_with_defaults.page_size
        }
      ]

      from_api = true
      token_holders = Chain.fetch_token_holders_from_token_hash(address_hash, from_api, options)
      render(conn, "gettokenholders.json", %{token_holders: token_holders})
    else
      {:contractaddress_param, :error} ->
        render(conn, :error, error: "Query parameter contract address is required")

      {:format, :error} ->
        render(conn, :error, error: "Invalid contract address hash")
    end
  end

  def getmixinassets(conn, _params) do
    total_assets = Chain.list_top_tokens("", paging_options: %PagingOptions{page_size: 1000})
    erc20_assets = Enum.filter(total_assets, fn x -> x.type == "ERC-20" and not is_nil(x.mixin_asset_id) and Enum.member?(@filter_assets, x.mixin_asset_id) end)

    asset_list = Enum.map(erc20_assets, fn t -> 
      info = Chain.token_add_price_and_chain_info(t)
      Map.merge(Map.from_struct(t), info)
    end)

    render(conn, :getmixinassets, %{asset_list: asset_list})
  end

  def search(conn, %{"q" => query} = _params) do
    res = Chain.search_token_asset(query)    
    erc20_assets = Enum.filter(res, fn x -> x.type == "ERC-20" and not is_nil(x.mixin_asset_id) and Enum.member?(@filter_assets, x.mixin_asset_id) end)

    asset_list = Enum.map(erc20_assets, fn t ->
      info = Chain.token_add_price_and_chain_info(t)
      Map.merge(t, info)
    end)

    render(conn, :search, %{list: asset_list})
  end

  defp fetch_contractaddress(params) do
    {:contractaddress_param, Map.fetch(params, "contractaddress")}
  end

  defp to_address_hash(address_hash_string) do
    {:format, Chain.string_to_address_hash(address_hash_string)}
  end
end
