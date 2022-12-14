defmodule BlockScoutWeb.API.RPC.TokenController do
  use BlockScoutWeb, :controller

  alias BlockScoutWeb.API.RPC.Helpers
  alias Ecto.UUID
  alias Explorer.{Chain, PagingOptions}
  alias Explorer.Chain.Hash.Address

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

    erc20_assets =
      Enum.filter(total_assets, fn x ->
        x.type == "ERC-20" and not is_nil(x.mixin_asset_id)
      end)

    asset_list =
      Enum.map(erc20_assets, fn t ->
        info = Chain.token_add_price_and_chain_info(t)
        asset = Map.merge(Map.from_struct(t), info)
        asset
      end)

    render(conn, :getmixinassets, %{asset_list: asset_list})
  end

  def search(conn, %{"q" => query} = _params) do
    res = Chain.search_token_asset(query)

    erc20_assets =
      Enum.filter(res, fn x ->
        x.type == "ERC-20" and not is_nil(x.mixin_asset_id)
      end)

    asset_list =
      Enum.map(erc20_assets, fn t ->
        info = Chain.token_add_price_and_chain_info(t)
        asset = Map.merge(t, info)
        asset
      end)

    render(conn, :search, %{list: asset_list})
  end

  def batchsearch(conn, params) do
    with {:index_type, {:ok, index_type}} <- fetch_type(params),
         {:indices, {:ok, indices}} <- fetch_indices(params),
         {:user_address, user} <- fetch_user(params),
         {:ok, index_list} <- is_valid_type_and_indices(index_type, indices),
         {:ok, user_address_hash} <- is_valid_user_address(user) do
      tokens = Chain.search_batch_tokens(index_type, index_list, user_address_hash)

      asset_list =
        Enum.map(tokens, fn t ->
          info = Chain.token_add_price_and_chain_info(t)
          Map.merge(t, info)
        end)

      render(conn, :batchsearch, %{list: asset_list})
    else
      {:index_type, :error} ->
        conn
        |> put_status(200)
        |> render(:error, error: "Type is required.")

      {:indices, :error} ->
        conn
        |> put_status(200)
        |> render(:error, error: "Indices is required.")

      {:error, :invalid_type} ->
        conn
        |> put_status(200)
        |> render(:error, error: "Invalid type. Type should be in ['contract', 'uuid'].")

      {:error, :invalid_indices} ->
        conn
        |> put_status(200)
        |> render(:error, error: "Invalid indices, indices should be either contract addresses or uuids split by ','.")

      {:error, :invalid_user} ->
        conn
        |> put_status(200)
        |> render(:error, error: "Invalid user, user should be the address of wallet.")
    end
  end

  defp is_valid_type_and_indices(index_type, indices) do
    index_list = String.split(indices, ",")

    check_list =
      Enum.map(index_list, fn x ->
        case index_type do
          "contract" -> Address.cast(x)
          "uuid" -> UUID.cast(x)
        end
      end)

    is_valid_type = index_type == "uuid" or index_type == "contract"

    is_valid_indices =
      Enum.all?(check_list, fn x ->
        case x do
          {:ok, _} -> true
          :error -> false
        end
      end)

    cond do
      not is_valid_type -> {:error, :invalid_type}
      is_valid_indices -> {:ok, index_list}
      true -> {:error, :invalid_indices}
    end
  end

  defp is_valid_user_address(user) do
    case user do
      :error ->
        {:ok, nil}

      {:ok, user_address} ->
        case Address.cast(user_address) do
          {:ok, hash} -> {:ok, hash}
          :error -> {:error, :invalid_user}
        end
    end
  end

  defp fetch_contractaddress(params) do
    {:contractaddress_param, Map.fetch(params, "contractaddress")}
  end

  defp fetch_type(params) do
    {:index_type, Map.fetch(params, "type")}
  end

  defp fetch_indices(params) do
    {:indices, Map.fetch(params, "indices")}
  end

  defp fetch_user(params) do
    {:user_address, Map.fetch(params, "user")}
  end

  defp to_address_hash(address_hash_string) do
    {:format, Chain.string_to_address_hash(address_hash_string)}
  end
end
