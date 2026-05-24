defmodule WaxxWeb.PublicUrl do
  @moduledoc """
  Derives the public-facing origin (`scheme://host[:port]`) the native
  client should dial back to, given a `%Plug.Conn{}`.

  Precedence — mirrors `derive_base_url/2` in
  `dms/src/handlers/api_tokens.rs`:

  1. `WAXX_PUBLIC_URL` env (explicit override for reverse-proxy setups).
  2. `X-Forwarded-Proto` + `X-Forwarded-Host` (standard proxy headers).
  3. The request's `Host` header (covers LAN access on `0.0.0.0`).
  4. The endpoint's configured URL as a last resort.

  Returned URL has no trailing slash so callers can concatenate
  `"\#{base}/api/..."` without worrying about double slashes.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @spec derive(Plug.Conn.t()) :: String.t()
  def derive(%Plug.Conn{} = conn) do
    cond do
      override = env_override() -> override
      forwarded = from_forwarded_headers(conn) -> forwarded
      host = from_conn_host(conn) -> host
      true -> endpoint_url()
    end
  end

  @doc """
  LiveView-flavoured derivation. Pulls `:uri` and `:x_headers` from
  `Phoenix.LiveView.get_connect_info/2` so the same precedence applies on
  the connected socket. Falls back to the endpoint URL when the info
  isn't available (e.g. disconnected first render).
  """
  @spec derive(Phoenix.LiveView.Socket.t()) :: String.t()
  def derive(%Phoenix.LiveView.Socket{} = socket) do
    cond do
      override = env_override() ->
        override

      forwarded = forwarded_from_socket(socket) ->
        forwarded

      uri = uri_from_socket(socket) ->
        from_uri(uri)

      true ->
        endpoint_url()
    end
  end

  defp forwarded_from_socket(socket) do
    headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []
    proto = find_header(headers, "x-forwarded-proto")
    host = find_header(headers, "x-forwarded-host")

    if proto && host do
      scheme = proto |> String.split(",") |> List.first() |> String.trim()
      strip_trailing_slash("#{scheme}://#{host}")
    end
  end

  defp uri_from_socket(socket), do: Phoenix.LiveView.get_connect_info(socket, :uri)

  defp from_uri(%URI{scheme: scheme, host: host, port: port}) when is_binary(host) do
    base =
      if default_port?(scheme, port) do
        "#{scheme}://#{host}"
      else
        "#{scheme}://#{host}:#{port}"
      end

    strip_trailing_slash(base)
  end

  defp from_uri(_), do: nil

  defp default_port?("http", 80), do: true
  defp default_port?("https", 443), do: true
  defp default_port?(_, _), do: false

  defp find_header(headers, name) do
    Enum.find_value(headers, fn
      {^name, value} -> value
      _ -> nil
    end)
  end

  defp env_override do
    case System.get_env("WAXX_PUBLIC_URL") do
      nil -> nil
      "" -> nil
      v -> strip_trailing_slash(v)
    end
  end

  defp from_forwarded_headers(conn) do
    with [proto | _] <- get_req_header(conn, "x-forwarded-proto"),
         [host | _] <- get_req_header(conn, "x-forwarded-host") do
      scheme = proto |> String.split(",") |> List.first() |> String.trim()
      strip_trailing_slash("#{scheme}://#{host}")
    else
      _ -> nil
    end
  end

  # Plug normalises the Host header into `conn.host` and `conn.port`.
  defp from_conn_host(%Plug.Conn{host: host, scheme: scheme, port: port})
       when is_binary(host) and host != "" do
    if default_port?(to_string(scheme), port) do
      strip_trailing_slash("#{scheme}://#{host}")
    else
      strip_trailing_slash("#{scheme}://#{host}:#{port}")
    end
  end

  defp from_conn_host(_), do: nil

  defp endpoint_url do
    WaxxWeb.Endpoint.url() |> strip_trailing_slash()
  end

  defp strip_trailing_slash(s), do: String.replace_suffix(s, "/", "")
end
