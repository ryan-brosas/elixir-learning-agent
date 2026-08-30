defmodule LearningPassDepthTest do
  use LearningAgent.DataCase, async: false

  alias LearningAgent.{LearningPass, RepositoryContext}

  setup do
    work =
      Path.join(
        System.tmp_dir!(),
        "la_depth_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    src = Path.join(work, "src")
    File.mkdir_p!(Path.join([src, "lib", "router"]))

    File.write!(Path.join([src, "lib", "router", "endpoint.ex"]), """
    defmodule Router.Endpoint do
      @moduledoc "The HTTP entry point: who requests arrive from and how they dispatch."
      def call(_), do: :ok
    end
    """)

    File.write!(Path.join([src, "lib", "router", "pipe.ex"]), """
    defmodule Router.Pipe do
      @moduledoc "Where requests are validated before handlers run."
      def run(_), do: :ok
    end
    """)

    on_exit(fn -> File.rm_rf!(work) end)

    {:ok, repo} =
      RepositoryContext.register(%{
        slug: "depth-repo",
        display_name: "depth",
        graph_project: "depth-repo",
        source_locator: src
      })

    %{repo: repo, src: src}
  end

  defp observation(selected) do
    %{
      selected: selected,
      files: [selected],
      memory: "status=ready root=#{selected}",
      architecture: "overview: one router component, entry endpoint.ex",
      component: "lib/",
      remaining: 0,
      prior: %{note: nil, count: 0}
    }
  end

  defp valid_note do
    """
    # architecture
    Router component learned.

    # covered
    - x

    # partial/uncited
    - y

    # porter-questions
    q

    # selected-subsystem
    x
    """
  end

  test "a component selection studies the component's own files", %{repo: repo} do
    test_pid = self()

    Application.put_env(:learning_agent, :note_complete, fn payload ->
      send(test_pid, {:prompt, payload})
      {:ok, %{text: valid_note()}}
    end)

    previous = Application.get_env(:learning_agent, :model)

    Application.put_env(:learning_agent, :model,
      enabled: true,
      base_url: "http://stub.local/v1",
      model: "stub-model",
      api_key: nil,
      timeout_ms: 1_000
    )

    try do
      assert {:ok, _text} = LearningPass.learn(repo, %{pass_number: 1}, observation("lib/"), nil)
    after
      restore(:model, previous)
      restore(:note_complete, nil)
    end

    assert_received {:prompt, payload}
    [message] = payload.messages
    text = hd(message.content).text
    assert text =~ "Router.Endpoint"
    assert text =~ "Router.Pipe"
    # the W's and the component are framed for the model
    assert text =~ "component lib/"
    assert text =~ "WHO uses it"
    assert text =~ "architecture grounding"
  end

  test "a file selection still reads the file window", %{repo: repo} do
    test_pid = self()

    Application.put_env(:learning_agent, :note_complete, fn payload ->
      send(test_pid, {:prompt, payload})
      {:ok, %{text: valid_note()}}
    end)

    previous = Application.get_env(:learning_agent, :model)

    Application.put_env(:learning_agent, :model,
      enabled: true,
      base_url: "http://stub.local/v1",
      model: "stub-model",
      api_key: nil,
      timeout_ms: 1_000
    )

    try do
      selected = "lib/router/endpoint.ex"

      assert {:ok, _text} =
               LearningPass.learn(repo, %{pass_number: 2}, observation(selected), nil)
    after
      restore(:model, previous)
      restore(:note_complete, nil)
    end

    assert_received {:prompt, payload}
    [message] = payload.messages
    text = hd(message.content).text
    assert text =~ "defmodule Router.Endpoint"
    assert text =~ "component lib/"
  end

  defp restore(key, nil), do: Application.delete_env(:learning_agent, key)
  defp restore(key, value), do: Application.put_env(:learning_agent, key, value)
end
