defmodule BlockScoutWeb.MIXIN_API do

  def request(url) do
    base = "https://mixin-api.zeromesh.net"

    case HTTPoison.get(base <> url, ["Content-Type": "application/json"]) do
      {:ok, %HTTPoison.Response{body: body, status_code: status_code}} ->
        {:ok, Jason.decode!(body)["data"]}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
