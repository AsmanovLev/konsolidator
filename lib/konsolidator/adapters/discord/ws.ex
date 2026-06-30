defmodule Konsolidator.Adapters.Discord.WS do
  @moduledoc """
  Minimal RFC 6455 WebSocket client over `:ssl` for the Discord Gateway.

  Opens a TLS connection to the Discord gateway host, performs an HTTP/1.1
  Upgrade handshake, then sends and receives framed WebSocket messages.
  No external WebSocket library required.

  ## Usage

      {:ok, ws} = Discord.WS.connect("gateway.discord.gg", 443, "/?v=10&encoding=json")
      :ok = Discord.WS.send_json(ws, %{op: 2, d: %{...}})
      {:ok, frame} = Discord.WS.recv(ws)
      :ok = Discord.WS.close(ws)
  """

  import Bitwise

  @handshake_key Base.encode64(:crypto.strong_rand_bytes(16))
  @type t :: %__MODULE__{socket: :ssl.sslsocket(), buffer: binary()}

  defstruct [:socket, buffer: ""]

  @doc "Connect to a WebSocket endpoint over TLS."
  @spec connect(String.t(), pos_integer(), String.t()) :: {:ok, t()} | {:error, term()}
  def connect(host, port, path) do
    host_charlist = String.to_charlist(host)
    ssl_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: host_charlist,
      depth: 10
    ]
    with {:ok, sock} <- :ssl.connect(host_charlist, port, ssl_opts, 10_000),
         :ok <- do_handshake(sock, host, path) do
      {:ok, %__MODULE__{socket: sock}}
    end
  end

  @doc "Send a map as a JSON text frame."
  @spec send_json(t(), map()) :: :ok | {:error, term()}
  def send_json(%__MODULE__{socket: sock}, payload) do
    data = Jason.encode!(payload)
    :ssl.send(sock, encode_frame(1, data))
  end

  @doc "Receive the next complete JSON frame, blocking."
  @spec recv(t()) :: {:ok, map(), t()} | {:error, term()}
  def recv(%__MODULE__{} = ws) do
    recv_loop(ws)
  end

  @doc "Send a close frame and shut down the socket."
  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: sock}) do
    :ssl.send(sock, encode_frame(8, <<1000::16>>))
    :ssl.close(sock)
    :ok
  end

  ## Private

  defp do_handshake(sock, host, path) do
    req =
      "GET #{path} HTTP/1.1\r\n" <>
      "Host: #{host}\r\n" <>
      "Upgrade: websocket\r\n" <>
      "Connection: Upgrade\r\n" <>
      "Sec-WebSocket-Key: #{@handshake_key}\r\n" <>
      "Sec-WebSocket-Version: 13\r\n\r\n"
    :ok = :ssl.send(sock, req)
    case recv_until_crlfcrlf(sock, "") do
      {:ok, headers} ->
        if String.contains?(headers, "101") do
          :ok
        else
          {:error, {:bad_handshake, headers}}
        end
      err -> err
    end
  end

  defp recv_until_crlfcrlf(sock, acc) do
    case :ssl.recv(sock, 0, 5_000) do
      {:ok, data} ->
        acc2 = acc <> data
        if String.contains?(acc2, "\r\n\r\n"), do: {:ok, acc2}, else: recv_until_crlfcrlf(sock, acc2)
      {:error, _} = err -> err
    end
  end

  defp recv_loop(%__MODULE__{socket: sock, buffer: buf} = ws) do
    case :ssl.recv(sock, 0, 35_000) do
      {:ok, data} ->
        buf2 = buf <> data
        case decode_frame(buf2) do
          {:ok, opcode, payload, rest} ->
            handle_frame(opcode, payload, %{ws | buffer: rest})
          :incomplete ->
            recv_loop(%{ws | buffer: buf2})
          {:error, _} = err -> err
        end
      {:error, :timeout} ->
        recv_loop(ws)
      {:error, _} = err -> err
    end
  end

  defp handle_frame(1, payload, ws) do
    # Text frame
    case Jason.decode(payload) do
      {:ok, map} -> {:ok, map, ws}
      {:error, _} -> {:error, {:bad_json, payload}}
    end
  end
  defp handle_frame(2, payload, ws) do
    # Binary frame - treat as text
    case Jason.decode(payload) do
      {:ok, map} -> {:ok, map, ws}
      {:error, _} -> {:ok, %{raw_binary: payload}, ws}
    end
  end
  defp handle_frame(8, _payload, ws) do
    # Close frame
    :ssl.close(ws.socket)
    {:error, :closed}
  end
  defp handle_frame(9, payload, ws) do
    # Ping - send pong
    :ssl.send(ws.socket, encode_frame(10, payload))
    recv_loop(ws)
  end
  defp handle_frame(10, _payload, ws) do
    # Pong
    recv_loop(ws)
  end
  defp handle_frame(_op, _payload, ws) do
    recv_loop(ws)
  end

  # Encode a WebSocket frame (client→server, always masked)
  defp encode_frame(opcode, payload) when is_binary(payload) do
    len = byte_size(payload)
    mask_key = :crypto.strong_rand_bytes(4)
    masked = mask(payload, mask_key)
    len_bytes =
      cond do
        len <= 125 -> <<1::1, len::7>>
        len <= 65_535 -> <<1::1, 126::7, len::16>>
        true -> <<1::1, 127::7, len::64>>
      end
    <<1::1, 0::3, opcode::4>> <> len_bytes <> mask_key <> masked
  end

  defp mask(data, key) do
    key_bytes = :binary.bin_to_list(key)
    data_bytes = :binary.bin_to_list(data)
    masked = Enum.with_index(data_bytes, fn byte, i ->
      Bitwise.bxor(byte, Enum.at(key_bytes, rem(i, 4)))
    end)
    :binary.list_to_bin(masked)
  end

  defp decode_frame(<<fin_rsv_op::8, rest::binary>>) when byte_size(rest) >= 1 do
    <<_fin::1, _rsv::3, opcode::4>> = <<fin_rsv_op>>
    <<mask_len::8, rest2::binary>> = rest
    masked = (mask_len &&& 0x80) != 0
    len_raw = mask_len &&& 0x7F
    case parse_length(len_raw, rest2) do
      {:ok, payload_len, mask_key_rest} ->
        {mask_key, payload_rest} =
          if masked do
            <<mk::binary-size(4), pr::binary>> = mask_key_rest
            {mk, pr}
          else
            {"", mask_key_rest}
          end
        if byte_size(payload_rest) >= payload_len do
          payload_len_pinned = payload_len
          <<payload::binary-size(^payload_len_pinned), remaining::binary>> = payload_rest
          final_payload = if masked, do: mask(payload, mask_key), else: payload
          {:ok, opcode, final_payload, remaining}
        else
          :incomplete
        end
      :incomplete -> :incomplete
    end
  end
  defp decode_frame(_), do: :incomplete

  defp parse_length(126, <<len::16, rest::binary>>), do: {:ok, len, rest}
  defp parse_length(127, <<len::64, rest::binary>>), do: {:ok, len, rest}
  defp parse_length(len, rest) when len <= 125, do: {:ok, len, rest}
  defp parse_length(126, _), do: :incomplete
  defp parse_length(127, _), do: :incomplete
end
