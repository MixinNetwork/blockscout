defmodule Explorer.MixinApi do
  @moduledoc false

  @base_url "https://api.mixin.one"

  def request(url) do
    case HTTPoison.get(@base_url <> url, "Content-Type": "application/json") do
      {:ok, %HTTPoison.Response{body: body}} ->
        data = Jason.decode!(body)

        case is_nil(data["error"]) do
          true -> {:ok, data["data"]}
          _ -> {:error, data["error"]["description"]}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
