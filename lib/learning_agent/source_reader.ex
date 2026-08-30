defmodule LearningAgent.SourceReader do
  @moduledoc """
  Bounded, read-only source access (docs/01, docs/05 §15, D-005).

  Enforces repository-relative containment: no absolute paths, no .. escapes, no
  symlink escapes past the root; reads are bounded to a max byte window. The model
  sees source only through here — it never opens arbitrary files itself.
  """

  @default_max_bytes 64 * 1024

  @doc "Resolve a repo-relative path under root, rejecting escapes."
  def resolve(root, relative) do
    with {:ok, clean} <- ensure_relative(relative) do
      real_root = Path.expand(root)
      real = Path.expand(Path.join(root, clean))
      if within?(real, real_root), do: {:ok, real}, else: {:error, :escape}
    end
  end

  defp within?(real, root) do
    real == root or String.starts_with?(real, root <> "/")
  end

  @doc "Paths must be relative, non-empty, and free of .. and leading /."
  def ensure_relative(""), do: {:error, :empty}

  def ensure_relative(rel) when is_binary(rel) do
    cond do
      String.starts_with?(rel, "/") -> {:error, :absolute}
      Enum.any?(Path.split(rel), &(&1 == "..")) -> {:error, :traversal}
      true -> {:ok, rel}
    end
  end

  def ensure_relative(_), do: {:error, :invalid}

  @doc "Read a bounded line window from a resolved absolute path."
  def read(abs, start_line, end_line, opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)

    case File.read(abs) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        selected = Enum.slice(lines, (start_line - 1)..min(end_line, length(lines)))
        joined = Enum.join(selected, "\n")

        {:ok,
         %{
           content: bound(joined, max_bytes),
           source_hash: sha256(content),
           truncated: byte_size(joined) > max_bytes
         }}

      {:error, reason} ->
        {:error, {:read_error, reason}}
    end
  end

  def bound(content, max_bytes) when byte_size(content) <= max_bytes, do: content

  def bound(content, max_bytes) do
    binary_part(content, 0, max_bytes)
    |> sanitize_utf8()
    |> Kernel.<>("\n... [truncated]")
  end

  @doc "Keep the longest valid UTF-8 prefix of a binary (drops stray bytes)."
  def sanitize_utf8(bin) when is_binary(bin) do
    case :unicode.characters_to_binary(bin, :utf8, :utf8) do
      {:ok, valid} -> valid
      {:error, valid, _rest} -> valid
      {:incomplete, valid, _rest} -> valid
      valid when is_binary(valid) -> valid
    end
  end

  def sha256(bin) do
    :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
  end
end
