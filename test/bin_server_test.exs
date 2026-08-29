defmodule LearningAgent.BinServerTest do
  use ExUnit.Case, async: false

  test "waits and retries when the readiness evaluation fails" do
    root =
      Path.join(
        System.tmp_dir!(),
        "learning_agent_release_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    bin_dir = Path.join(root, "bin")
    state_file = Path.join(root, "readiness-attempts")
    script = Path.join(bin_dir, "learning_agent")
    File.mkdir_p!(bin_dir)
    File.write!(state_file, "0")

    File.write!(
      script,
      ~S"""
      #!/bin/sh
      set -eu

      if [ "${1-}" = "eval" ]; then
        expression="$2"

        case "$expression" in
          *"SELECT 1"*)
            attempts=$(cat "$STATE_FILE")
            attempts=$((attempts + 1))
            printf '%s' "$attempts" > "$STATE_FILE"

            if [ "$attempts" -eq 1 ] && printf '%s' "$expression" | grep -Fq '{:ok, _} = LearningAgent.Repo.query'; then
              exit 1
            fi
            ;;
        esac

        exit 0
      fi

      exit 0
      """
    )

    File.chmod!(script, 0o755)
    on_exit(fn -> File.rm_rf!(root) end)

    {output, status} =
      System.cmd("sh", [Path.expand("../bin/server", __DIR__)],
        env: [{"RELEASE_ROOT", root}, {"STATE_FILE", state_file}],
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "waiting for db..."
    assert File.read!(state_file) == "2"
  end
end
