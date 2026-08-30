defmodule LearningAgent.SourceReaderUtf8Test do
  use ExUnit.Case, async: true
  alias LearningAgent.SourceReader

  defp valid_utf8?(bin) do
    case :unicode.characters_to_binary(bin, :utf8, :utf8) do
      {:ok, _} -> true
      bins when is_binary(bins) -> true
      _ -> false
    end
  end

  test "bound keeps a valid utf8 prefix when truncation would split a codepoint" do
    content = "a" <> <<0xE2, 0x80, 0x94>> <> "b"
    bound = SourceReader.bound(content, 4)
    assert valid_utf8?(bound)
    assert bound =~ "truncated"
  end

  test "sanitize_utf8 drops stray invalid bytes" do
    clean = SourceReader.sanitize_utf8("ok" <> <<0xFF, 0xFF>> <> "stop")
    assert valid_utf8?(clean)
    assert clean == "ok"
  end
end
