# Smoke test for Konsolidator + real Telegram bot.
#
# Run with:
#   $env:TELEGRAM_BOT_TOKEN = "..."
#   $env:TELEGRAM_CHAT_ID = "..."
#   mix run scripts/smoke_real_bot.exs
#
# Sends a test message to the configured chat, prints the message_id,
# then polls getUpdates for ~5 seconds looking for an echo.

{:ok, _} = Application.ensure_all_started(:konsolidator)
Process.sleep(200)

alias Konsolidator.{Content, Button, Router}
alias Konsolidator.Adapters.Telegram

token = System.fetch_env!("TELEGRAM_BOT_TOKEN")
chat_id = String.to_integer(System.fetch_env!("TELEGRAM_CHAT_ID"))

IO.puts("Starting Telegram adapter with token #{String.slice(token, 0, 10)}...")

{:ok, _pid} =
  case Telegram.start_link(token: token, long_poll_timeout: 5) do
    {:ok, p} -> {:ok, p}
    {:error, {:already_started, p}} -> {:ok, p}
  end

# Subscribe to incoming so we can see if the user replies.
:ok = Phoenix.PubSub.subscribe(Router.pubsub(), "incoming")
IO.puts("Subscribed to incoming. Sending test message...")

{:ok, ref} =
  Telegram.send(
    Telegram,
    chat_id,
    %Content{
      text: "[konsolidator smoke] hello from konsolidator!",
      parse_mode: :html
    }
  )

IO.puts("Sent. message_id = #{inspect(ref)}")

# Now edit the message.
Process.sleep(500)

edit_result = Telegram.edit(Telegram, chat_id, ref, %Content{text: "[konsolidator smoke] edited!"})
IO.puts("Edit result: #{inspect(edit_result)}")

# Now send a message with inline buttons.
{:ok, ref2} =
  Telegram.send(
    Telegram,
    chat_id,
    %Content{
      text: "Pick a fruit:",
      buttons: [
        [
          %Button{label: "Apple", data: "fruit:apple"},
          %Button{label: "Banana", data: "fruit:banana"}
        ],
        [%Button{label: "Open docs", url: "https://hex.pm"}]
      ]
    }
  )

IO.puts("Sent buttons. message_id = #{inspect(ref2)}")

# Typing indicator test.
IO.puts("Typing on...")
:ok = Telegram.typing(Telegram, chat_id, :on)
Process.sleep(1000)
IO.puts("Typing off...")
:ok = Telegram.typing(Telegram, chat_id, :off)

# Listen for incoming events for 5 seconds.
IO.puts("Listening for incoming events for 8 seconds... (press a button in TG or send /start)")
listen_until = System.monotonic_time(:millisecond) + 8_000

listen_loop = fn loop ->
  if System.monotonic_time(:millisecond) < listen_until do
    receive do
      {:incoming, payload} ->
        IO.puts("INCOMING: #{inspect(payload, pretty: true, limit: 5)}")
        loop.(loop)
    after
      500 -> loop.(loop)
    end
  else
    :ok
  end
end

listen_loop.(listen_loop)

# Delete both messages.
:ok = Telegram.delete(Telegram, chat_id, ref)
:ok = Telegram.delete(Telegram, chat_id, ref2)
IO.puts("Cleaned up. Done.")
