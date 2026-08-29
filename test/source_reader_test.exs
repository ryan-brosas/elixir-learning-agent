defmodule LearningAgent.SourceReaderTest do
  use ExUnit.Case, async: true
  alias LearningAgent.SourceReader

  test "ensure_relative accepts a normal repo-relative path" do
    assert {:ok, "lib/x.ex"} = SourceReader.ensure_relative("lib/x.ex")
  end

  test "ensure_relative rejects absolute, traversal, and empty" do
    assert {:error, :absolute} = SourceReader.ensure_relative("/etc/passwd")
    assert {:error, :traversal} = SourceReader.ensure_relative("../etc/passwd")
    assert {:error, :traversal} = SourceReader.ensure_relative("lib/../../etc/passwd")
    assert {:error, :empty} = SourceReader.ensure_relative("")
  end

  test "resolve blocks escaping the repo root" do
    assert {:error, :traversal} = SourceReader.resolve("/repos/r", "../outside")
    assert {:ok, p} = SourceReader.resolve("/repos/r", "lib/x.ex")
    assert p == "/repos/r/lib/x.ex"
  end

  test "read returns a stable source hash for exact bytes" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "la_sr_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "a.ex")
    content = "def a;\n  :ok\nend\n"
    File.write!(path, content)

    {:ok, r} = SourceReader.read(path, 1, 20)
    assert r.source_hash == SourceReader.sha256(content)
    assert r.truncated == false
    File.rm_rf!(dir)
  end

  test "read reports truncation when the window exceeds the byte cap" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "la_sr_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "big.ex")
    File.write!(path, String.duplicate("x", 100_000))

    {:ok, r} = SourceReader.read(path, 1, 100_000, max_bytes: 1024)
    assert r.truncated
    File.rm_rf!(dir)
  end
end
