defmodule LearningAgent.Skills.Root do
  @moduledoc "Containment for generated skills. All writes stay under the skills root."
  require Logger

  @default ".agents/skills"

  def path do
    Application.get_env(:learning_agent, :skills_root, @default)
    |> Path.expand()
  end

  @doc "Make the skills root writable, falling back to ./skills-data when the configured path is not writable."
  def ensure do
    case probe(path()) do
      :ok ->
        :ok

      {:error, reason} ->
        fallback = Path.expand("skills-data")

        Logger.warning(
          "skills_root_unwritable path=#{path()} reason=#{inspect(reason)} fallback=#{fallback}"
        )

        case probe(fallback) do
          :ok ->
            Application.put_env(:learning_agent, :skills_root, fallback)
            :ok

          error ->
            error
        end
    end
  end

  @doc "Resolve `rel` inside the skills root. Rejects `..` escapes."
  def contain(rel) when is_binary(rel) do
    root = path()
    full = Path.expand(rel, root)

    if full == root or String.starts_with?(full, root <> "/") do
      case File.mkdir_p(full) do
        :ok -> {:ok, full}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :path_escape}
    end
  end

  def contain(_), do: {:error, :path_escape}

  def leaf_name(name) when is_binary(name) do
    if Regex.match?(~r/^[a-z0-9][a-z0-9-]{0,62}$/, name),
      do: {:ok, name},
      else: {:error, :invalid_leaf}
  end

  def leaf_name(_), do: {:error, :invalid_leaf}

  defp probe(root) do
    marker = Path.join(root, ".write-probe")

    with :ok <- File.mkdir_p(root),
         :ok <- File.write(marker, "ok") do
      _ = File.rm(marker)
      :ok
    end
  end
end
