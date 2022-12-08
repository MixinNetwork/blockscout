defmodule Explorer.KnownTokens.Source do
  @moduledoc """
  Behaviour for fetching list of known tokens.
  """

  alias Explorer.MixinApi

  @doc """
  Fetches known tokens
  """
  @spec fetch_known_tokens() :: {:ok, any} | {:error, any}
  def fetch_known_tokens do
    MixinApi.request("/network/assets/top")
  end

  @doc """
  Url for querying the list of known tokens.
  """
  @callback source_url() :: String.t()

  @callback headers() :: [any()]
end
