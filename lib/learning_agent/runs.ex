defmodule LearningAgent.Run do
  @moduledoc """
  Durable learning run (docs/03 §4). The (repository_id, pass_number) uniqueness
  blocks duplicate same runs. State follows the domain state machine in
  LearningAgent.Domain.Run; transition/2 delegates validity to it so a run can
  never leave an invalid path.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias LearningAgent.Domain.Run, as: RunDomain

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "runs" do
    field(:repository_id, :binary_id)
    field(:pin_id, :binary_id)
    field(:pass_number, :integer)
    field(:state, :string, default: "queued")
    field(:outcome, :string)
    field(:lease_epoch, :integer)
    field(:current_gate, :string)
    field(:selected_subsystem_id, :binary_id)
    field(:cancel_requested, :boolean, default: false)
    field(:cancel_requested_at, :utc_datetime_usec)
    field(:started_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)
    field(:blocked_reason, :string)
    field(:failure_class, :string)
    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(repository_id pin_id pass_number)a

  def changeset(run, attrs) do
    run
    |> cast(
      attrs,
      @required ++
        [
          :state,
          :outcome,
          :lease_epoch,
          :current_gate,
          :selected_subsystem_id,
          :cancel_requested,
          :cancel_requested_at,
          :started_at,
          :finished_at,
          :blocked_reason,
          :failure_class
        ]
    )
    |> validate_required(@required)
    |> validate_inclusion(:state, RunDomain.all_states() |> Enum.map(&Atom.to_string/1))
  end

  @doc """
  Build a changeset transitioning to new_state. Returns {:ok, changeset} when the
  domain allows from -> to, else {:error, :invalid_transition}.
  """
  def transition(run, new_state, attrs \\ %{}) do
    from = String.to_atom(run.state)
    to = String.to_atom(new_state)

    if RunDomain.valid_transition?(from, to) do
      {:ok, change(run, Map.merge(%{state: new_state}, attrs))}
    else
      {:error, :invalid_transition}
    end
  end

  def request_cancel(run) do
    change(run, cancel_requested: true, cancel_requested_at: DateTime.utc_now())
  end
end
