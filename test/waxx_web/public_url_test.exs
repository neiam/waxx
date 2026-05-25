defmodule WaxxWeb.PublicUrlTest do
  use ExUnit.Case, async: false

  import Plug.Test
  alias WaxxWeb.PublicUrl

  setup do
    System.delete_env("WAXX_PUBLIC_URL")
    on_exit(fn -> System.delete_env("WAXX_PUBLIC_URL") end)
    :ok
  end

  defp build_conn(opts) do
    conn(:get, "/")
    |> Map.merge(Map.new(opts))
  end

  describe "derive/1 with a Plug.Conn" do
    test "WAXX_PUBLIC_URL takes precedence over everything else" do
      System.put_env("WAXX_PUBLIC_URL", "https://override.example.com/")

      conn =
        build_conn(host: "host.example.com", scheme: :https, port: 443)
        |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
        |> Plug.Conn.put_req_header("x-forwarded-host", "proxy.example.com")

      assert PublicUrl.derive(conn) == "https://override.example.com"
    end

    test "X-Forwarded-* headers used when env is unset" do
      conn =
        build_conn(host: "internal.example.com", scheme: :http, port: 80)
        |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
        |> Plug.Conn.put_req_header("x-forwarded-host", "proxy.example.com")

      assert PublicUrl.derive(conn) == "https://proxy.example.com"
    end

    test "X-Forwarded-Proto alone upgrades the scheme; host comes from conn" do
      conn =
        build_conn(host: "waxx.neiam.co", scheme: :http, port: 80)
        |> Plug.Conn.put_req_header("x-forwarded-proto", "https")

      assert PublicUrl.derive(conn) == "https://waxx.neiam.co"
    end

    test "X-Forwarded-Host alone keeps conn scheme; host from header" do
      conn =
        build_conn(host: "internal", scheme: :https, port: 443)
        |> Plug.Conn.put_req_header("x-forwarded-host", "edge.example.com")

      assert PublicUrl.derive(conn) == "https://edge.example.com"
    end

    test "X-Forwarded-Proto with comma-separated values picks the first" do
      conn =
        build_conn(host: "internal.example.com", scheme: :http, port: 80)
        |> Plug.Conn.put_req_header("x-forwarded-proto", "https, http")
        |> Plug.Conn.put_req_header("x-forwarded-host", "edge.example.com")

      assert PublicUrl.derive(conn) == "https://edge.example.com"
    end

    test "conn.host used when forwarded headers absent (with non-default port)" do
      conn = build_conn(host: "192.168.1.50", scheme: :http, port: 4000)

      assert PublicUrl.derive(conn) == "http://192.168.1.50:4000"
    end

    test "conn.host omits port when it's the default for the scheme" do
      conn = build_conn(host: "waxx.example.com", scheme: :https, port: 443)

      assert PublicUrl.derive(conn) == "https://waxx.example.com"
    end

    test "empty env var is treated as absent" do
      System.put_env("WAXX_PUBLIC_URL", "")

      conn = build_conn(host: "fallback.example.com", scheme: :https, port: 443)

      assert PublicUrl.derive(conn) == "https://fallback.example.com"
    end
  end
end
