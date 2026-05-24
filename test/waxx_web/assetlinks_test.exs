defmodule WaxxWeb.AssetlinksTest do
  use WaxxWeb.ConnCase, async: true

  test "GET /.well-known/assetlinks.json is served as JSON", %{conn: conn} do
    conn = get(conn, "/.well-known/assetlinks.json")

    assert conn.status == 200
    body = response(conn, 200)
    decoded = Jason.decode!(body)
    assert is_list(decoded)
    assert hd(decoded)["target"]["package_name"] == "org.neiam.waxx.app"
  end
end
