defmodule LearningAgent.RuntimeSettings do
  @moduledoc """
  Live operator settings. Worker slot and model-lane changes take effect without
  restart; each slot learns one graph at a time. Lanes split that cap across models.
  """

  @min_slots 1
  @max_slots 64
  @max_lanes 8
  @model_bytes 128
  @model_re ~r/^[A-Za-z0-9._:~\/-]+$/

  def snapshot do
    lanes = lanes()

    %{
      worker_slots: Enum.reduce(lanes, 0, fn lane, acc -> acc + lane.slots end),
      lanes: Enum.map(lanes, &surface_lane/1),
      model_connection: surface_connection(model_connection())
    }
  end

  @doc """
  Server-side model connection for the learning fleet. Redacted for snapshots:
  the API key never travels back to a browser.
  """
  def model_connection do
    case Application.get_env(:learning_agent, :model_connection) do
      %{} = conn -> conn
      _ -> nil
    end
  end

  def put_model_connection(attrs) when is_map(attrs) do
    with {:ok, conn} <- parse_connection(attrs) do
      Application.put_env(:learning_agent, :model_connection, conn)
      write_file(snapshot())

      LearningAgent.Activity.log(
        :info,
        "model connection saved: #{conn.base_url}" <> model_suffix(conn)
      )

      {:ok, snapshot()}
    end
  end

  defp model_suffix(%{model: model}) when is_binary(model), do: " · model " <> model
  defp model_suffix(_), do: ""

  defp parse_connection(attrs) do
    base_url = trim_string(Map.get(attrs, :base_url, Map.get(attrs, "base_url")))
    api_key = trim_string(Map.get(attrs, :api_key, Map.get(attrs, "api_key")))
    model = trim_string(Map.get(attrs, :model, Map.get(attrs, "model")))

    cond do
      base_url == nil ->
        {:error, :model_connection_invalid}

      not (base_url =~ ~r{^https?://[^\s]+$}) or byte_size(base_url) > 2_048 ->
        {:error, :model_connection_invalid}

      api_key != nil and byte_size(api_key) > 512 ->
        {:error, :model_connection_invalid}

      model != nil and
          (byte_size(model) > @model_bytes or not Regex.match?(@model_re, model)) ->
        {:error, :model_connection_invalid}

      true ->
        {:ok, %{base_url: base_url, api_key: api_key, model: model}}
    end
  end

  defp trim_string(v) when is_binary(v),
    do:
      (
        t = String.trim(v)
        if t == "", do: nil, else: t
      )

  defp trim_string(_), do: nil

  defp surface_connection(nil), do: nil

  defp surface_connection(conn) do
    %{base_url: conn.base_url, model: conn.model, api_key_set: is_binary(conn.api_key)}
  end

  def worker_slots do
    # Read the mirrored app env directly instead of calling the scheduler: a
    # blocking GenServer.call here turns scheduler starvation (40 workers, DB
    # contention) into HTTP 500s on every board poll. The scheduler keeps this
    # env in sync on init and on every set_concurrency.
    Application.get_env(:learning_agent, :worker_slots, 1)
  end

  def lanes do
    case Application.get_env(:learning_agent, :worker_lanes) do
      list when is_list(list) and list != [] ->
        Enum.map(list, &normalize_lane/1)

      _ ->
        # Never call back into the scheduler here: take_model runs inside the
        # scheduler tick, and a self GenServer.call would crash the loop.
        [%{model: nil, slots: max(env_slots(), @min_slots)}]
    end
  end

  defp env_slots do
    case Application.get_env(:learning_agent, :worker_slots, 1) do
      n when is_integer(n) and n >= @min_slots -> n
      _ -> @min_slots
    end
  end

  @doc "Weighted round-robin model id for the next admitted worker. nil uses the server default."
  def take_model do
    weighted = expand_lanes(lanes())

    case weighted do
      [] ->
        nil

      list ->
        cursor = Application.get_env(:learning_agent, :worker_lane_cursor, 0)
        Application.put_env(:learning_agent, :worker_lane_cursor, cursor + 1)
        Enum.at(list, rem(cursor, length(list)))
    end
  end

  def load do
    case read_file() do
      {:ok, attrs} ->
        _ = put(attrs, persist?: false)

        case Map.get(attrs, "model_connection") || Map.get(attrs, :model_connection) do
          conn when is_map(conn) ->
            _ = put_model_connection(conn)
            :ok

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  def put(attrs, opts \\ [])

  def put(attrs, opts) when is_map(attrs) do
    with {:ok, lanes} <- fetch_lanes(attrs),
         slots = Enum.reduce(lanes, 0, fn lane, acc -> acc + lane.slots end),
         {:ok, _slots} <- LearningAgent.Scheduler.set_concurrency(slots) do
      Application.put_env(:learning_agent, :worker_lanes, lanes)

      LearningAgent.Activity.log(
        :info,
        "worker split updated: #{slots} slots across #{length(lanes)} lane(s)"
      )

      if Keyword.get(opts, :persist?, true) do
        write_file(snapshot())
      end

      {:ok, snapshot()}
    end
  end

  def put(_, _), do: {:error, :worker_slots_invalid}

  def parse_slots(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> parse_slots(n)
      _ -> {:error, :worker_slots_invalid}
    end
  end

  def parse_slots(n) when is_integer(n) and n >= @min_slots and n <= @max_slots, do: {:ok, n}
  def parse_slots(_), do: {:error, :worker_slots_invalid}

  defp fetch_lanes(%{lanes: lanes}), do: parse_lanes(lanes)
  defp fetch_lanes(%{"lanes" => lanes}), do: parse_lanes(lanes)

  defp fetch_lanes(attrs) do
    with {:ok, slots} <- fetch_slots(attrs) do
      {:ok, [%{model: nil, slots: slots}]}
    end
  end

  defp fetch_slots(%{worker_slots: value}), do: parse_slots(value)
  defp fetch_slots(%{"worker_slots" => value}), do: parse_slots(value)
  defp fetch_slots(_), do: {:error, :worker_slots_invalid}

  defp parse_lanes(list) when is_list(list) and length(list) in 1..@max_lanes do
    parsed = Enum.map(list, &parse_lane/1)

    if Enum.all?(parsed, &match?({:ok, _}, &1)) do
      lanes = Enum.map(parsed, fn {:ok, lane} -> lane end)
      total = Enum.reduce(lanes, 0, fn lane, acc -> acc + lane.slots end)

      if total >= @min_slots and total <= @max_slots do
        {:ok, merge_lanes(lanes)}
      else
        {:error, :worker_slots_invalid}
      end
    else
      {:error, :worker_slots_invalid}
    end
  end

  defp parse_lanes(_), do: {:error, :worker_slots_invalid}

  defp parse_lane(lane) when is_map(lane) do
    with {:ok, slots} <- parse_slots(lane_slots(lane)),
         {:ok, model} <- parse_model(lane_model(lane)) do
      {:ok, %{model: model, slots: slots}}
    end
  end

  defp parse_lane(_), do: {:error, :worker_slots_invalid}

  defp lane_slots(lane), do: Map.get(lane, :slots, Map.get(lane, "slots"))
  defp lane_model(lane), do: Map.get(lane, :model, Map.get(lane, "model"))

  defp parse_model(nil), do: {:ok, nil}
  defp parse_model(""), do: {:ok, nil}

  defp parse_model(model) when is_binary(model) do
    trimmed = String.trim(model)

    cond do
      trimmed == "" -> {:ok, nil}
      byte_size(trimmed) <= @model_bytes and Regex.match?(@model_re, trimmed) -> {:ok, trimmed}
      true -> {:error, :worker_slots_invalid}
    end
  end

  defp parse_model(_), do: {:error, :worker_slots_invalid}

  defp expand_lanes(lanes) do
    max_slots = Enum.max(Enum.map(lanes, & &1.slots), fn -> 0 end)

    Enum.flat_map(1..max_slots, fn i ->
      Enum.flat_map(lanes, fn lane ->
        if lane.slots >= i, do: [lane.model], else: []
      end)
    end)
  end

  defp merge_lanes(lanes) do
    Enum.reduce(lanes, [], fn lane, acc ->
      case Enum.find_index(acc, &(&1.model == lane.model)) do
        nil ->
          acc ++ [lane]

        idx ->
          List.update_at(acc, idx, fn match ->
            %{model: lane.model, slots: match.slots + lane.slots}
          end)
      end
    end)
  end

  defp normalize_lane(%{model: model, slots: slots}), do: %{model: model, slots: slots}
  defp normalize_lane(%{"model" => model, "slots" => slots}), do: %{model: model, slots: slots}
  defp normalize_lane(_), do: %{model: nil, slots: @min_slots}

  defp surface_lane(lane), do: %{model: lane.model, slots: lane.slots}

  defp settings_path do
    Application.get_env(:learning_agent, :settings_path, :default)
  end

  defp resolved_path(:default), do: Path.join(File.cwd!(), "data/runtime-settings.json")
  defp resolved_path(path) when is_binary(path), do: path
  defp resolved_path(_), do: nil

  defp read_file do
    case resolved_path(settings_path()) do
      nil ->
        :error

      path ->
        with {:ok, raw} <- File.read(path),
             {:ok, attrs} <- Jason.decode(raw) do
          {:ok, attrs}
        else
          _ -> :error
        end
    end
  end

  defp write_file(snapshot) do
    case resolved_path(settings_path()) do
      nil ->
        :ok

      path ->
        conn = model_connection()

        payload = %{
          "worker_slots" => snapshot.worker_slots,
          "lanes" =>
            Enum.map(snapshot.lanes, fn lane ->
              %{"model" => lane.model || "", "slots" => lane.slots}
            end),
          "model_connection" =>
            if conn do
              %{
                "base_url" => conn.base_url,
                "api_key" => conn.api_key || "",
                "model" => conn.model || ""
              }
            else
              nil
            end
        }

        File.mkdir_p!(Path.dirname(path))
        tmp = path <> ".tmp"
        File.write!(tmp, Jason.encode!(payload))
        File.rename!(tmp, path)
        :ok
    end
  end
end
