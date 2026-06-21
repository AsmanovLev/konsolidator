# Smoke test for Konsolidator + real Telegram bot via curl.
#
# This script sends a test message, edits it, sends buttons,
# then listens for incoming events.
#
# Run with:  mix run scripts/smoke_real_bot.exs

token = "6627691089:AAEuOmCEoKSiQlN1FkLi-XcZdUB4OOrxX58"
chat_id = 10_551_980_77
proxy = "socks5h://127.0.0.1:10808"

defmodule SmokeBot do
  def api(token, method, params \\ [], proxy \\ "") do
    url = "https://api.telegram.org/bot#{token}/#{method}"

    args =
      ["--proxy", proxy, "-s", "-m", "15", "--data-urlencode", "chat_id=#{chat_id()}", "--data-urlencode", "text=#{params[:text] || ""}"] ++
        if(params[:reply_markup], do: ["--data-urlencode", "reply_markup=#{Jason.encode!(params[:reply_markup])}"], else: []) ++
        if(params[:message_id], do: ["--data-urlencode", "message_id=#{params[:message_id]}"], else: []) ++
        if(params[:action], do: ["--data-urlencode", "action=#{params[:action]}"], else: [])

    args = args ++ [url]

    case System.cmd("curl", args, stderr_to_stdout: true) do
      {output, 0} ->
        Jason.decode(output)

      {output, code} ->
        IO.puts("curl error #{code}: #{output}")
        {:error, output}
    end
  end

  defp chat_id, do: 10_551_980_77
end

# 1. getMe — verify token
IO.puts("\n=== getMe ===")
{:ok, me} = SmokeBot.api(token, "getMe", [], proxy)
IO.puts("Bot: @#{me["result"]["username"]} (#{me["result"]["first_name"]})")

# 2. sendMessage
IO.puts("\n=== sendMessage ===")
{:ok, msg} = SmokeBot.api(token, "sendMessage", [text: "[konsolidator] smoke test #{System.os_time(:second)}"], proxy)
ref = msg["result"]["message_id"]
IO.puts("Sent. message_id = #{ref}")

# 3. editMessageText
Process.sleep(500)
IO.puts("\n=== editMessageText ===")
{:ok, _} = SmokeBot.api(token, "editMessageText", [text: "[konsolidator] edited!", message_id: ref], proxy)
IO.puts("Edited.")

# 4. send with inline buttons
IO.puts("\n=== sendMessage with buttons ===")
markup = %{
  "inline_keyboard" => [
    [%{"text" => "Apple", "callback_data" => "fruit:apple"}, %{"text" => "Banana", "callback_data" => "fruit:banana"}],
    [%{"text" => "Open docs", "url" => "https://hex.pm/packages/konsolidator"}]
  ]
}

{:ok, msg2} = SmokeBot.api(token, "sendMessage", [text: "Pick a fruit:", reply_markup: markup], proxy)
ref2 = msg2["result"]["message_id"]
IO.puts("Sent buttons. message_id = #{ref2}")

# 5. typing indicator
IO.puts("\n=== sendChatAction ===")
SmokeBot.api(token, "sendChatAction", [action: "typing"], proxy)
IO.puts("Typing sent.")

# 6. Listen for incoming events (long-poll getUpdates)
IO.puts("\n=== Listening for incoming events for 15s ===")
IO.puts("Press a button or send /start to the bot in Telegram...")
IO.puts("")

listen_until = System.monotonic_time(:millisecond) + 15_000
offset = 0

listen_loop = fn loop, offset ->
  if System.monotonic_time(:millisecond) < listen_until do
    case System.cmd("curl", [
           "--proxy", proxy, "-s", "-m", "5",
           "https://api.telegram.org/bot#{token}/getUpdates?offset=#{offset}&timeout=3"
         ], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"ok" => true, "result" => updates}} when updates != [] ->
            Enum.each(updates, fn update ->
              IO.puts("  INCOMING: #{inspect(update, pretty: true, limit: 4)}")
            end)
            new_offset = List.last(updates)["update_id"] + 1
            loop.(loop, new_offset)

          _ ->
            loop.(loop, offset)
        end

      _ ->
        loop.(loop, offset)
    end
  else
    :ok
  end
end

listen_loop.(listen_loop, offset)

# 7. Cleanup
IO.puts("\n=== Cleanup ===")
SmokeBot.api(token, "deleteMessage", [message_id: ref], proxy)
SmokeBot.api(token, "deleteMessage", [message_id: ref2], proxy)
IO.puts("Done.")
