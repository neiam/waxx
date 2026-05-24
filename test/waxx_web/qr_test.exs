defmodule WaxxWeb.QRTest do
  use ExUnit.Case, async: true

  alias WaxxWeb.QR

  test "renders an SVG document" do
    svg = QR.svg("waxx://pair?base=https://example.com&token=abc")
    assert is_binary(svg)
    assert String.contains?(svg, "<svg")
    assert String.contains?(svg, "</svg>")
  end

  test "respects custom width" do
    svg = QR.svg("hello", width: 400)
    assert String.contains?(svg, ~s(width="400))
  end
end
