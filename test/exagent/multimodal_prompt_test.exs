defmodule ExAgent.MultimodalPromptTest do
  use ExUnit.Case, async: true

  alias ExAgent.Message
  alias ExAgent.Message.{Part, Request}
  alias ExAgent.Models.Test

  @pdf Base.encode64("%PDF-1.4 fixture")

  defp agent(owner) do
    ExAgent.new(
      model: %Test{
        script: [
          fn messages, _params ->
            send(owner, {:messages, messages})
            "seen"
          end
        ]
      }
    )
  end

  test "a content list becomes canonical string-keyed parts that survive JSON" do
    prompt = [
      %{type: :text, text: "Summarize both."},
      %{type: "image_url", url: "https://example.com/a.png"},
      %{
        "type" => "file",
        "data" => @pdf,
        "media_type" => "application/pdf",
        "filename" => "a.pdf"
      }
    ]

    assert {:ok, result} = ExAgent.run(agent(self()), prompt)
    assert result.output == "seen"
    assert_receive {:messages, [%Request{parts: [%Part.User{content: content}]}]}

    assert content == [
             %{"type" => "text", "text" => "Summarize both."},
             %{"type" => "image_url", "url" => "https://example.com/a.png"},
             %{
               "type" => "file",
               "data" => @pdf,
               "media_type" => "application/pdf",
               "filename" => "a.pdf"
             }
           ]

    assert {:ok, decoded} = result.messages |> Message.to_json() |> Message.from_json()
    assert decoded == result.messages
  end

  test "an invalid content part fails before any model request" do
    for {prompt, index} <- [
          {[%{"type" => "text", "text" => "ok"}, %{"type" => "video", "url" => "x"}], 1},
          {[%{"type" => "image", "data" => "not base64!", "media_type" => "image/png"}], 0},
          {[%{"type" => "image_url", "url" => "file:///etc/passwd"}], 0},
          {[%{"type" => "text", "text" => "x", "extra" => "y"}], 0},
          {[%{"type" => "file", "data" => @pdf}], 0},
          {[%{"type" => "image", "data" => @pdf, "media_type" => ""}], 0},
          {[%{"type" => "text", "text" => "x"}, ExAgent.Message.Part.User.__struct__()], 1},
          {[%{{:bad, :key} => "x"}], 0},
          {[%{"type" => "text", :type => "text", "text" => "x"}], 0},
          {["plain string"], 0}
        ] do
      assert {:error, %ExAgent.RunError{reason: {:invalid_prompt_part, ^index}}} =
               ExAgent.run(agent(self()), prompt)
    end

    assert {:error, %ExAgent.RunError{reason: :invalid_prompt}} =
             ExAgent.run(agent(self()), [])

    refute_receive {:messages, _}, 0
  end

  test "string prompts are unchanged" do
    assert {:ok, %{output: "seen"}} = ExAgent.run(agent(self()), "hello")
    assert_receive {:messages, [%Request{parts: [%Part.User{content: "hello"}]}]}
  end
end
