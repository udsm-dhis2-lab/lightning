defmodule Lightning.Attempts.Handlers do
  @moduledoc """
  Handler modules for working with attempts.
  """

  alias Lightning.Attempt
  alias Lightning.AttemptRun
  alias Lightning.Attempts
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Run
  alias Lightning.Repo
  alias Lightning.WorkOrders

  defmodule StartRun do
    @moduledoc """
    Schema to validate the input attributes of a started run.
    """
    use Ecto.Schema
    import Ecto.Changeset
    import Ecto.Query

    @primary_key false
    embedded_schema do
      field :attempt_id, Ecto.UUID
      field :run_id, Ecto.UUID
      field :credential_id, Ecto.UUID
      field :job_id, Ecto.UUID
      field :input_dataclip_id, Ecto.UUID
      field :started_at, :utc_datetime_usec
    end

    def new(params) do
      cast(%__MODULE__{}, params, [
        :attempt_id,
        :run_id,
        :credential_id,
        :job_id,
        :input_dataclip_id,
        :started_at
      ])
      |> then(fn changeset ->
        if get_change(changeset, :started_at) do
          changeset
        else
          put_change(changeset, :started_at, DateTime.utc_now())
        end
      end)
      |> validate_required([
        :attempt_id,
        :run_id,
        :job_id,
        :input_dataclip_id,
        :started_at
      ])
      |> then(&validate_job_reachable/1)
    end

    def call(params) do
      with {:ok, attrs} <- new(params) |> apply_action(:validate),
           {:ok, run} <- insert(attrs) do
        attempt = Attempts.get(attrs.attempt_id, include: [:workflow])
        WorkOrders.Events.attempt_updated(attempt.workflow.project_id, attempt)
        Attempts.Events.run_started(attrs.attempt_id, run)

        {:ok, run}
      end
    end

    defp insert(attrs) do
      Repo.transact(fn ->
        with {:ok, run} <- attrs |> to_run() |> Repo.insert(),
             {:ok, _} <- attrs |> to_attempt_run() |> Repo.insert() do
          {:ok, run}
        end
      end)
    end

    defp to_run(%__MODULE__{run_id: run_id} = start_run) do
      start_run
      |> Map.take([:credential_id, :input_dataclip_id, :job_id, :started_at])
      |> Map.put(:id, run_id)
      |> Run.new()
    end

    defp to_attempt_run(%__MODULE__{run_id: run_id, attempt_id: attempt_id}) do
      AttemptRun.new(%{
        run_id: run_id,
        attempt_id: attempt_id
      })
    end

    defp validate_job_reachable(changeset) do
      case changeset do
        %{valid?: false} ->
          changeset

        _ ->
          job_id = get_field(changeset, :job_id)
          attempt_id = get_field(changeset, :attempt_id)

          # Verify that all of the required entities exist with a single query,
          # then reduce the results into a single changeset by adding errors for
          # any columns/ids that are null.
          attempt_id
          |> fetch_existing_job(job_id)
          |> Enum.reduce(changeset, fn {k, v}, changeset ->
            if is_nil(v) do
              add_error(changeset, k, "does not exist")
            else
              changeset
            end
          end)
      end
    end

    defp fetch_existing_job(attempt_id, job_id) do
      query =
        from(a in Attempt,
          where: a.id == ^attempt_id,
          left_join: w in assoc(a, :workflow),
          left_join: j in assoc(w, :jobs),
          on: j.id == ^job_id,
          select: %{attempt_id: a.id, job_id: j.id}
        )

      Repo.one(query) || %{attempt_id: nil, job_id: nil}
    end
  end

  defmodule CompleteRun do
    @moduledoc """
    Schema to validate the input attributes of a completed run.
    """
    use Ecto.Schema
    import Ecto.Changeset
    import Ecto.Query

    @primary_key false
    embedded_schema do
      field :project_id, Ecto.UUID
      field :attempt_id, Ecto.UUID
      field :output_dataclip, :string
      field :output_dataclip_id, Ecto.UUID
      field :reason, :string
      field :error_type, :string
      field :error_message, :string
      field :run_id, Ecto.UUID
      field :finished_at, :utc_datetime_usec
    end

    def new(params) do
      cast(%__MODULE__{}, params, [
        :attempt_id,
        :output_dataclip,
        :output_dataclip_id,
        :project_id,
        :reason,
        :error_type,
        :error_message,
        :run_id,
        :finished_at
      ])
      |> then(fn changeset ->
        if get_change(changeset, :finished_at) do
          changeset
        else
          put_change(changeset, :finished_at, DateTime.utc_now())
        end
      end)
      |> then(fn changeset ->
        output_dataclip_id = get_change(changeset, :output_dataclip_id)
        output_dataclip = get_change(changeset, :output_dataclip)

        case {output_dataclip, output_dataclip_id} do
          {nil, nil} ->
            changeset

          _ ->
            changeset
            |> validate_required([:output_dataclip, :output_dataclip_id])
        end
      end)
      |> validate_required([
        :attempt_id,
        :finished_at,
        :project_id,
        :reason,
        :run_id
      ])
    end

    def call(params) do
      with {:ok, complete_run} <- new(params) |> apply_action(:validate),
           {:ok, run} <- update(complete_run) do
        Attempts.Events.run_completed(complete_run.attempt_id, run)

        {:ok, run}
      end
    end

    defp update(complete_run) do
      Repo.transact(fn ->
        with %Run{} = run <- get_run(complete_run.run_id),
             {:ok, _} <- maybe_save_dataclip(complete_run) do
          update_run(run, complete_run)
        else
          nil ->
            {:error,
             complete_run
             |> change()
             |> add_error(:run_id, "not found")}

          error ->
            error
        end
      end)
    end

    defp get_run(id) do
      from(r in Lightning.Invocation.Run, where: r.id == ^id)
      |> Repo.one()
    end

    defp maybe_save_dataclip(%__MODULE__{output_dataclip: nil}) do
      {:ok, nil}
    end

    defp maybe_save_dataclip(%__MODULE__{
           output_dataclip: output_dataclip,
           project_id: project_id,
           output_dataclip_id: dataclip_id
         }) do
      Dataclip.new(%{
        id: dataclip_id,
        project_id: project_id,
        body: output_dataclip |> Jason.decode!(),
        type: :run_result
      })
      |> Repo.insert()
    end

    defp update_run(run, %{
           reason: reason,
           error_type: error_type,
           error_message: error_message,
           output_dataclip_id: output_dataclip_id
         }) do
      run
      |> Run.finished(output_dataclip_id, {reason, error_type, error_message})
      |> Repo.update()
    end
  end
end
