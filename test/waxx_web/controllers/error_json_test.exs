defmodule WaxxWeb.ErrorJSONTest do
  use WaxxWeb.ConnCase, async: true

  test "renders 404" do
    assert WaxxWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert WaxxWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
