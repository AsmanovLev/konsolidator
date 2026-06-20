defmodule Konsolidator.Adapters.Telegram.ApiTest do
  use ExUnit.Case, async: true

  alias Konsolidator.Adapters.Telegram.Api

  def fixture(name), do: File.read!("test/support/fixtures/telegram/#{name}.json") |> Jason.decode!()

  test "call/4 with a successful response returns {:ok, result}" do
    body = fixture("send_message_200")
    fn _url, _params -> {:ok, body} end
    |> then(fn request_fn ->
      assert {:ok, %{"message_id" => 12345}} =
               Api.call("TOKEN", :send_message, [chat_id: 42, text: "hi"], request_fn)
    end)
  end

  test "call/4 with API error returns {:error, %{description: ...}}" do
    body = fixture("error_400")
    fn _, _ -> {:ok, body} end
    |> then(fn request_fn ->
      assert {:error, %{description: "Bad Request: chat not found", code: 400}} =
               Api.call("TOKEN", :send_message, [chat_id: 99999], request_fn)
    end)
  end

  test "call/4 with HTTP error returns {:error, {:http, ...}}" do
    fn _, _ -> {:error, %Req.TransportError{reason: :econnrefused}} end
    |> then(fn request_fn ->
      assert {:error, {:http, :transport, :econnrefused}} =
               Api.call("TOKEN", :send_message, [], request_fn)
    end)
  end

  test "base_url/2 builds the expected URL" do
    assert Api.base_url("12345:ABC", :send_message) ==
             "https://api.telegram.org/bot12345:ABC/send_message"
  end

  test "file/1 returns the path unchanged (Req handles multipart upload)" do
    assert Api.file("/tmp/foo.txt") == "/tmp/foo.txt"
  end
end
