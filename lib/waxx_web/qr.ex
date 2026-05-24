defmodule WaxxWeb.QR do
  @moduledoc """
  Thin wrapper around `EQRCode` for rendering QR codes to SVG. The SVG
  is intended to be embedded inline in a HEEx template via `raw/1`.
  """

  @default_width 280

  @doc """
  Renders `payload` as an SVG QR code at `width` pixels (default
  #{@default_width}).

  Returns the SVG document as a string. Raises if the payload is too long
  for the underlying encoder (the limit is generous — > 2KB).
  """
  @spec svg(String.t(), keyword()) :: String.t()
  def svg(payload, opts \\ []) when is_binary(payload) do
    width = Keyword.get(opts, :width, @default_width)

    payload
    |> EQRCode.encode()
    |> EQRCode.svg(width: width)
  end
end
