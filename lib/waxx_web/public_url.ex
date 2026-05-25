defmodule WaxxWeb.PublicUrl do
  @moduledoc """
  Derives the public-facing origin (`scheme://host[:port]`) the native
  client should dial back to.

  Resolution (highest precedence first):

  1. `WAXX_PUBLIC_URL` env (explicit override for reverse-proxy setups).
  2. Composed from forwarded headers + conn fallbacks:
     - scheme: `X-Forwarded-Proto` (first value) if present, else `conn.scheme`
     - host:   `X-Forwarded-Host`  (first value, may carry `:port`) if present,
               else `conn.host` (with `conn.port` appended if non-default)
  3. The endpoint's configured URL as a last resort.

  Proto and host are sourced independently so a proxy that only sets
  `X-Forwarded-Proto: https` (the common Traefik / nginx default —
  Host is preserved unchanged) still yields the right scheme. Treating
  them as a unit caused QRs to encode `http://` behind TLS-terminated
  proxies, which then broke WebSocket upgrades when Plug.SSL bounced
  the upgrade with a 301.

  Returned URL has no trailing slash so callers can concatenate
  `"\#{base}/api/..."` without worrying about double slashes.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @spec derive(Plug.Conn.t()) :: String.t()
  def derive(%Plug.Conn{} = conn) do
    case env_override() do
      nil ->
        compose(scheme_from_conn(conn), host_from_conn(conn)) || endpoint_url()

      url ->
        url
    end
  end

  @doc """
  LiveView-flavoured derivation. Must be called from `mount/3` (LiveView
  destroys connect_info after mount). The endpoint must expose `:uri`
  and `:x_headers` in `connect_info`.
  """
  @spec derive(Phoenix.LiveView.Socket.t()) :: String.t()
  def derive(%Phoenix.LiveView.Socket{} = socket) do
    case env_override() do
      nil ->
        compose(scheme_from_socket(socket), host_from_socket(socket)) || endpoint_url()

      url ->
        url
    end
  end

  ## Scheme + host extraction ------------------------------------------

  defp scheme_from_conn(conn) do
    forwarded_proto(get_req_header(conn, "x-forwarded-proto")) ||
      to_string(conn.scheme)
  end

  defp host_from_conn(conn) do
    case get_req_header(conn, "x-forwarded-host") do
      [h | _] -> normalise_host(h)
      _ -> host_with_port(conn.host, to_string(conn.scheme), conn.port)
    end
  end

  defp scheme_from_socket(socket) do
    headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []

    forwarded_proto([find_header(headers, "x-forwarded-proto")]) ||
      uri_field(socket, :scheme)
  end

  defp host_from_socket(socket) do
    headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []

    case find_header(headers, "x-forwarded-host") do
      nil -> uri_host(socket)
      host -> normalise_host(host)
    end
  end

  defp uri_field(socket, key) do
    case Phoenix.LiveView.get_connect_info(socket, :uri) do
      %URI{} = uri -> Map.get(uri, key) |> to_string_safe()
      _ -> nil
    end
  end

  defp uri_host(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :uri) do
      %URI{host: host, scheme: scheme, port: port} when is_binary(host) ->
        host_with_port(host, scheme, port)

      _ ->
        nil
    end
  end

  ## Helpers ------------------------------------------------------------

  defp compose(nil, _), do: nil
  defp compose(_, nil), do: nil
  defp compose(scheme, host), do: strip_trailing_slash("#{scheme}://#{host}")

  defp forwarded_proto([proto | _]) when is_binary(proto) do
    proto |> String.split(",") |> List.first() |> String.trim()
  end

  defp forwarded_proto(_), do: nil

  # X-Forwarded-Host may itself be a comma-separated list (chained proxies).
  # Take the first value verbatim — it may already include `:port`.
  defp normalise_host(h) when is_binary(h) do
    h |> String.split(",") |> List.first() |> String.trim()
  end

  defp host_with_port(host, _scheme, nil), do: host

  defp host_with_port(host, scheme, port) do
    if default_port?(scheme, port), do: host, else: "#{host}:#{port}"
  end

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

  defp endpoint_url do
    WaxxWeb.Endpoint.url() |> strip_trailing_slash()
  end

  defp to_string_safe(nil), do: nil
  defp to_string_safe(v), do: to_string(v)

  defp strip_trailing_slash(s), do: String.replace_suffix(s, "/", "")
end
