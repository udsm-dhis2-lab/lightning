defmodule Lightning.DashboardStats do
  @moduledoc false

  import Ecto.Query

  alias Lightning.Attempt
  alias Lightning.Invocation.Run
  alias Lightning.Repo
  alias Lightning.Workflows.Workflow

  defmodule WorkflowStats do
    defstruct last_workorder: %{state: nil, updated_at: nil},
              last_failed_workorder: %{state: nil, updated_at: nil},
              failed_workorders_count: 0,
              grouped_attempts_count: %{},
              grouped_workorders_count: %{},
              runs_count: 0,
              runs_success_rate: 0.0,
              workorders_count: 0,
              workflow: %Workflow{}
  end

  defmodule ProjectMetrics do
    defstruct work_order_metrics: %{
                total: 0,
                pending: 0,
                failed: 0,
                failed_percentage: 0.0
              },
              attempt_metrics: %{
                total: 0,
                pending: 0,
                success: 0,
                success_rate: 0.0
              }
  end

  def get_workflow_stats(%Workflow{} = workflow) do
    %{failed: failed_wo_count} =
      grouped_workorders_count = count_workorders(workflow)

    workorders_count =
      grouped_workorders_count
      |> Enum.map(fn {_key, count} -> count end)
      |> Enum.sum()

    grouped_attempts_count = count_attempts(workflow)

    {runs_count, runs_success_rate} =
      workflow |> count_runs() |> runs_stats()

    last_workorder = get_last_workorder(workflow)

    %WorkflowStats{
      workflow: workflow,
      last_workorder: last_workorder,
      last_failed_workorder: get_last_failed_workorder(workflow, last_workorder),
      failed_workorders_count: failed_wo_count,
      grouped_attempts_count: grouped_attempts_count,
      grouped_workorders_count: grouped_workorders_count,
      runs_count: runs_count,
      runs_success_rate: round(runs_success_rate * 100) / 100,
      workorders_count: workorders_count
    }
  end

  def aggregate_project_metrics(workflows_stats) do
    %ProjectMetrics{
      work_order_metrics:
        aggregate_metrics(workflows_stats, :grouped_workorders_count),
      attempt_metrics:
        aggregate_metrics(workflows_stats, :grouped_attempts_count)
    }
  end

  defp runs_stats(%{
         success: success_count,
         failed: failed_count,
         pending: pending_count
       }) do
    runs_count = success_count + failed_count + pending_count

    if runs_count == 0 do
      {0, 0.0}
    else
      success_rate = success_count * 100 / (success_count + failed_count)
      {runs_count, success_rate}
    end
  end

  defp get_last_failed_workorder(workflow, %{state: :success}) do
    excluded_states = [:pending, :running, :success]
    get_last_workorder(workflow, excluded_states)
  end

  defp get_last_failed_workorder(_workflow, %{state: _other} = failed_wo) do
    failed_wo
  end

  defp get_last_workorder(
         %Workflow{id: workflow_id},
         excluded_states \\ [:pending, :running]
       ) do
    from(wo in Lightning.WorkOrder,
      where: wo.workflow_id == ^workflow_id,
      where: wo.state not in ^excluded_states,
      order_by: [desc: wo.inserted_at],
      select: %{state: wo.state, updated_at: wo.updated_at}
    )
    |> filter_days_ago(30)
    |> limit(1)
    |> Repo.one() ||
      %{state: nil, updated_at: nil}
  end

  defp count_workorders(%Workflow{id: workflow_id}) do
    from(wo in Lightning.WorkOrder,
      where: wo.workflow_id == ^workflow_id,
      select: wo.state
    )
    |> filter_days_ago(30)
    |> Repo.all()
    |> Enum.group_by(fn state ->
      cond do
        state in [:pending, :running] -> :pending
        state == :success -> :success
        true -> :failed
      end
    end)
    |> Enum.into(%{success: 0, failed: 0, pending: 0}, fn {state, list} ->
      {state, length(list)}
    end)
  end

  defp count_attempts(%Workflow{id: workflow_id}) do
    from(a in Attempt,
      join: wo in assoc(a, :work_order),
      join: wf in assoc(wo, :workflow),
      where: wf.id == ^workflow_id,
      select: a.state
    )
    |> filter_days_ago(30)
    |> Repo.all()
    |> Enum.group_by(fn state ->
      cond do
        state == :success -> :success
        state in [:available, :claimed, :started] -> :pending
        true -> :failed
      end
    end)
    |> Enum.into(%{success: 0, failed: 0, pending: 0}, fn {state, list} ->
      {state, length(list)}
    end)
  end

  defp count_runs(%Workflow{id: workflow_id}) do
    from(r in Run,
      join: j in assoc(r, :job),
      join: wf in assoc(j, :workflow),
      where: wf.id == ^workflow_id,
      select: r.exit_reason
    )
    |> filter_days_ago(30)
    |> Repo.all()
    |> Enum.group_by(fn exit_reason ->
      cond do
        exit_reason == "success" -> :success
        exit_reason == nil -> :pending
        true -> :failed
      end
    end)
    |> Enum.into(%{success: 0, failed: 0, pending: 0}, fn {state, list} ->
      {state, length(list)}
    end)
  end

  defp aggregate_metrics(workflows, grouped_entity_count) do
    Enum.reduce(
      workflows,
      %{success: 0, failed: 0, pending: 0, total: 0},
      fn stats,
         %{
           success: acc_success,
           failed: acc_failed,
           pending: acc_pending,
           total: acc_total
         } ->
        %{success: success, failed: failed, pending: pending} =
          Map.get(stats, grouped_entity_count)

        total = success + failed + pending

        %{
          success: acc_success + success,
          failed: acc_failed + failed,
          pending: acc_pending + pending,
          total: acc_total + total
        }
      end
    )
    |> then(fn %{success: success, failed: failed, total: total} = map ->
      completed = success + failed
      failed_percent = if completed > 0, do: failed * 100 / total, else: 0.0
      success_rate = if completed > 0, do: success * 100 / completed, else: 0.0

      Map.merge(map, %{
        success_rate: round(success_rate * 100) / 100,
        failed_percentage: round(failed_percent * 100) / 100
      })
    end)
  end

  def filter_days_ago(query, days) do
    days_ago = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60)

    query
    |> where([r], r.inserted_at > ^days_ago)
  end
end
