defmodule LearningAgent.RuntimeSettingsTest do
  use LearningAgent.DataCase, async: false

  alias LearningAgent.RuntimeSettings

  setup do
    previous_slots = Application.get_env(:learning_agent, :worker_slots)
    previous_lanes = Application.get_env(:learning_agent, :worker_lanes)
    previous_path = Application.get_env(:learning_agent, :settings_path)
    previous_cursor = Application.get_env(:learning_agent, :worker_lane_cursor)
    Application.put_env(:learning_agent, :worker_slots, 1)
    Application.put_env(:learning_agent, :worker_lanes, nil)
    Application.put_env(:learning_agent, :settings_path, nil)
    Application.put_env(:learning_agent, :worker_lane_cursor, 0)

    on_exit(fn ->
      Application.put_env(:learning_agent, :worker_slots, previous_slots || 1)
      restore(:worker_lanes, previous_lanes)
      restore(:settings_path, previous_path)
      restore(:worker_lane_cursor, previous_cursor)
    end)

    :ok
  end

  test "parse_slots accepts 1 through 64" do
    assert RuntimeSettings.parse_slots(1) == {:ok, 1}
    assert RuntimeSettings.parse_slots("8") == {:ok, 8}
    assert RuntimeSettings.parse_slots(40) == {:ok, 40}
    assert RuntimeSettings.parse_slots(0) == {:error, :worker_slots_invalid}
    assert RuntimeSettings.parse_slots(65) == {:error, :worker_slots_invalid}
    assert RuntimeSettings.parse_slots("nope") == {:error, :worker_slots_invalid}
  end

  test "put updates worker slots without a live scheduler" do
    assert {:ok, %{worker_slots: 4}} = RuntimeSettings.put(%{worker_slots: 4})
    assert RuntimeSettings.worker_slots() == 4
    assert RuntimeSettings.put(%{worker_slots: 0}) == {:error, :worker_slots_invalid}
  end

  test "put splits slots across models and round-robins assignment" do
    assert {:ok, snapshot} =
             RuntimeSettings.put(%{
               lanes: [
                 %{model: "ds-pro", slots: 20},
                 %{model: "glm-5.3-flash", slots: 20}
               ]
             })

    assert snapshot.worker_slots == 40

    assert snapshot.lanes == [
             %{model: "ds-pro", slots: 20},
             %{model: "glm-5.3-flash", slots: 20}
           ]

    models = Enum.map(1..40, fn _ -> RuntimeSettings.take_model() end)
    assert Enum.count(models, &(&1 == "ds-pro")) == 20
    assert Enum.count(models, &(&1 == "glm-5.3-flash")) == 20
  end

  test "load restores lanes from disk" do
    path = Path.join(System.tmp_dir!(), "la-settings-#{System.unique_integer([:positive])}.json")
    Application.put_env(:learning_agent, :settings_path, path)

    assert {:ok, _} =
             RuntimeSettings.put(%{
               lanes: [
                 %{model: "ds-pro", slots: 20},
                 %{model: "glm-5.3-flash", slots: 20}
               ]
             })

    Application.put_env(:learning_agent, :worker_slots, 1)
    Application.put_env(:learning_agent, :worker_lanes, nil)
    assert RuntimeSettings.load() == :ok
    assert RuntimeSettings.snapshot().worker_slots == 40
    File.rm(path)
  end

  test "put_model_connection persists and snapshot redacts the api key" do
    previous_connection = Application.get_env(:learning_agent, :model_connection)

    on_exit(fn ->
      restore(:model_connection, previous_connection)
    end)

    assert {:ok, snapshot} =
             RuntimeSettings.put_model_connection(%{
               "base_url" => " http://127.0.0.1:11434/v1 ",
               "api_key" => "secret-key",
               "model" => "qwen3:8b"
             })

    assert snapshot.model_connection == %{
             base_url: "http://127.0.0.1:11434/v1",
             model: "qwen3:8b",
             api_key_set: true
           }

    assert RuntimeSettings.model_connection().api_key == "secret-key"

    assert {:error, :model_connection_invalid} =
             RuntimeSettings.put_model_connection(%{"base_url" => "not a url"})
  end

  test "a saved model connection overrides the LA_MODEL_* env defaults" do
    previous_env = System.get_env("LA_MODEL_BASE_URL")
    previous_model = System.get_env("LA_MODEL")

    System.put_env("LA_MODEL_BASE_URL", "http://127.0.0.1:11434/v1")
    System.put_env("LA_MODEL", "replace-with-a-model-id")

    previous = Application.get_env(:learning_agent, :model_connection)

    Application.put_env(:learning_agent, :model_connection, %{
      base_url: "https://top-tools-ai.example/v1",
      api_key: "sk-test",
      model: "DeepSeek-V4-Pro"
    })

    try do
      conn = LearningAgent.ModelGateway.connection()
      assert conn.base_url == "https://top-tools-ai.example/v1"
      assert conn.model == "DeepSeek-V4-Pro"
      assert conn.api_key == "sk-test"
    after
      if is_nil(previous_env),
        do: System.delete_env("LA_MODEL_BASE_URL"),
        else: System.put_env("LA_MODEL_BASE_URL", previous_env)

      if is_nil(previous_model),
        do: System.delete_env("LA_MODEL"),
        else: System.put_env("LA_MODEL", previous_model)

      restore(:model_connection, previous)
    end
  end

  defp restore(key, nil), do: Application.delete_env(:learning_agent, key)
  defp restore(key, value), do: Application.put_env(:learning_agent, key, value)
end
