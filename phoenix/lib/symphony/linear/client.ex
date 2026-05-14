defmodule Symphony.Linear.Client do
  @moduledoc """
  Minimal Linear GraphQL HTTP client.
  """

  @timeout_ms 30_000

  @type response :: %{status: non_neg_integer(), body: term()}

  @spec post(String.t(), [{String.t(), String.t()}], String.t(), map()) ::
          {:ok, response()} | {:error, term()}
  def post(endpoint, headers, query, variables)
      when is_binary(endpoint) and is_list(headers) and is_binary(query) and is_map(variables) do
    body = Jason.encode!(%{query: query, variables: variables})

    request_headers =
      headers
      |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
      |> then(&[{~c"content-type", ~c"application/json"} | &1])

    request = {String.to_charlist(endpoint), request_headers, ~c"application/json", body}
    options = [timeout: @timeout_ms]
    http_options = [body_format: :binary]

    case :httpc.request(:post, request, options, http_options) do
      {:ok, {{_version, status, _reason}, _headers, response_body}} ->
        {:ok, %{status: status, body: decode_body(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> body
    end
  end
end
