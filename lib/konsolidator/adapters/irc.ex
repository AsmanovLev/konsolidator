defmodule Konsolidator.Adapters.IRC do
  @moduledoc """
  IRC adapter over plain TCP or TLS using `:gen_tcp` / `:ssl`.

  Connects to an IRC server, authenticates with NICK/USER (and optionally
  PASS for NickServ), joins configured channels, and relays messages to
  `Konsolidator.Router`.

  `user_id` for outgoing messages is the channel name, e.g. `"#lobby"`.

  ## Config

      config :konsolidator, Konsolidator.Adapters.IRC,
        host: "irc.libera.chat",
        port: 6697,
        tls: true,
        nick: "mybot",
        user: "mybot",
        realname: "My IRC Bot",
        password: nil,        # optional NickServ/PASS
        channels: ["#mychan"]
  """

  use GenServer
  require Logger

  alias Konsolidator.{Content, Router}

  @behaviour Konsolidator.Adapter

  @default_port_tls 6697
  @default_port_plain 6667
  @reconnect_after 10_000

  @impl Konsolidator.Adapter
  def name, do: :irc

  @impl Konsolidator.Adapter
  def capabilities do
    [:send_text, :typing_indicator]
  end

  @impl Konsolidator.Adapter
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Konsolidator.Adapter
  def send(adapter, channel, content), do: GenServer.call(adapter, {:send, channel, content}, 10_000)

  @impl Konsolidator.Adapter
  def edit(_adapter, _channel, _ref, _content), do: {:error, :not_supported}

  @impl Konsolidator.Adapter
  def delete(_adapter, _channel, _ref), do: {:error, :not_supported}

  @impl Konsolidator.Adapter
  def typing(_adapter, _channel, _state), do: :ok

  @impl Konsolidator.Adapter
  def answer_callback(_adapter, _callback_id, _opts), do: :ok

  @impl true
  def init(opts) do
    tls = Keyword.get(opts, :tls, true)
    default_port = if tls, do: @default_port_tls, else: @default_port_plain
    state = %{
      host: Keyword.fetch!(opts, :host),
      port: Keyword.get(opts, :port, default_port),
      tls: tls,
      nick: Keyword.fetch!(opts, :nick),
      user: Keyword.get(opts, :user, "konsolidator"),
      realname: Keyword.get(opts, :realname, "Konsolidator IRC Bot"),
      password: Keyword.get(opts, :password),
      channels: Keyword.get(opts, :channels, []),
      socket: nil,
      transport: nil,
      buf: ""
    }
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case do_connect(state) do
      {:ok, socket, transport} ->
        state2 = %{state | socket: socket, transport: transport}
        :ok = register_nick(state2)
        send(self(), :recv)
        {:noreply, state2}
      {:error, reason} ->
        Logger.error("[IRC] Connection failed: #{inspect(reason)}, retrying in #{@reconnect_after}ms")
        Process.send_after(self(), :reconnect, @reconnect_after)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:reconnect, state), do: {:noreply, state, {:continue, :connect}}

  @impl true
  def handle_info(:recv, %{socket: nil} = state), do: {:noreply, state}

  @impl true
  def handle_info(:recv, state) do
    case state.transport.recv(state.socket, 0, 5_000) do
      {:ok, data} ->
        {lines, buf} = split_lines(state.buf <> data)
        state2 = Enum.reduce(lines, %{state | buf: buf}, &process_line/2)
        send(self(), :recv)
        {:noreply, state2}
      {:error, :timeout} ->
        send(self(), :recv)
        {:noreply, state}
      {:error, reason} ->
        Logger.warning("[IRC] Recv error: #{inspect(reason)}, reconnecting in #{@reconnect_after}ms")
        state.transport.close(state.socket)
        Process.send_after(self(), :reconnect, @reconnect_after)
        {:noreply, %{state | socket: nil}}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:send, channel, %Content{text: text}}, _from, state) when is_binary(text) do
    # Split into lines; IRC PRIVMSG is single-line
    lines = String.split(text, "\n", trim: true)
    Enum.each(lines, fn line ->
      irc_send(state, "PRIVMSG #{channel} :#{line}")
    end)
    {:reply, {:ok, nil}, state}
  end

  def handle_call({:send, _channel, _content}, _from, state) do
    {:reply, {:error, :no_text}, state}
  end

  ## Private helpers

  defp do_connect(state) do
    host = String.to_charlist(state.host)
    if state.tls do
      opts = [verify: :verify_peer, cacerts: :public_key.cacerts_get(),
              server_name_indication: host, depth: 10]
      case :ssl.connect(host, state.port, opts, 15_000) do
        {:ok, sock} -> {:ok, sock, :ssl}
        err -> err
      end
    else
      case :gen_tcp.connect(host, state.port, [:binary, active: false], 15_000) do
        {:ok, sock} -> {:ok, sock, :gen_tcp}
        err -> err
      end
    end
  end

  defp register_nick(state) do
    if state.password do
      irc_send(state, "PASS #{state.password}")
    end
    irc_send(state, "NICK #{state.nick}")
    irc_send(state, "USER #{state.user} 0 * :#{state.realname}")
    :ok
  end

  defp irc_send(state, line) do
    state.transport.send(state.socket, "#{line}\r\n")
  end

  defp split_lines(buf) do
    parts = String.split(buf, "\r\n")
    {complete, [remainder]} = Enum.split(parts, length(parts) - 1)
    {complete, remainder}
  end

  defp process_line(line, state) do
    Logger.debug("[IRC] < #{line}")
    cond do
      String.starts_with?(line, "PING") ->
        token = String.replace_prefix(line, "PING ", "")
        irc_send(state, "PONG #{token}")
        state
      Regex.match?(~r/ 376 | 422 /, line) ->
        # RPL_ENDOFMOTD or ERR_NOMOTD — safe to JOIN
        Enum.each(state.channels, fn ch -> irc_send(state, "JOIN #{ch}") end)
        state
      true ->
        parse_privmsg(line, state)
    end
  end

  defp parse_privmsg(line, state) do
    # :nick!user@host PRIVMSG #channel :message
    case Regex.run(~r/^:([^!]+)![^\s]+ PRIVMSG ([^\s]+) :(.*)$/, line) do
      [_, _nick, target, text] ->
        Router.publish_incoming(%{
          source: :irc,
          user_id: target,
          text: text,
          ref: nil,
          raw: line
        })
        state
      _ ->
        state
    end
  end
end
