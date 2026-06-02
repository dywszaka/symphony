defmodule Symphony.TaskTracker.Client do
  @moduledoc """
  Minimal HTTP client for the TaskTracker REST API.
  """

  @timeout_ms 30_000

  @type response :: %{status: non_neg_integer(), body: term()}

  @spec request(atom(), String.t(), [{String.t(), String.t()}], keyword(), map() | nil) ::
          {:ok, response()} | {:error, term()}
  def request(method, url, headers, params, json)
      when is_atom(method) and is_binary(url) and is_list(headers) and is_list(params) do
    request_url = append_query(url, params)
    request = request_tuple(request_url, headers, json)

    http_method = method |> Atom.to_string() |> String.downcase() |> String.to_atom()

    case :httpc.request(http_method, request, [timeout: @timeout_ms], body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, response_body}} ->
        {:ok, %{status: status, body: decode_body(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_tuple(url, headers, nil) do
    {String.to_charlist(url), request_headers(headers)}
  end

  defp request_tuple(url, headers, json) do
    {
      String.to_charlist(url),
      request_headers(headers),
      ~c"application/json",
      Jason.encode!(json)
    }
  end

  defp append_query(url, []), do: url

  defp append_query(url, params) do
    separator = if String.contains?(url, "?"), do: "&", else: "?"
    url <> separator <> URI.encode_query(params)
  end

  defp request_headers(headers) do
    headers
    |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
    |> then(&[{~c"content-type", ~c"application/json"} | &1])
  end

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> body
    end
  end
end
