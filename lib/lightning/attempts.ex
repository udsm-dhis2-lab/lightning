defmodule Lightning.Attempts do
  defmodule Adaptor do
    @moduledoc """
    Behaviour for implementing an adaptor for the Lightning.Attempts module.
    """

    @callback enqueue(
                attempt ::
                  Lightning.Attempt.t() | Ecto.Changeset.t(Lightning.Attempt.t())
              ) ::
                {:ok, Lightning.Attempt.t()}
                | {:error, Ecto.Changeset.t(Lightning.Attempt.t())}

    @callback claim(demand :: non_neg_integer()) ::
                {:ok, [Lightning.Attempt.t()]}

    @callback dequeue(attempt :: Lightning.Attempt.t()) ::
                {:ok, Lightning.Attempt.t()}
  end

  alias Lightning.{Repo, Attempt}
  alias Lightning.Attempts.Handlers
  import Ecto.Query

  @behaviour Adaptor

  @doc """
  Enqueue an attempt to be processed.
  """
  @impl true
  def enqueue(attempt) do
    adaptor().enqueue(attempt)
  end

  # @doc """
  # Claim an available attempt.
  #
  # The `demand` parameter is used to request more than a since attempt,
  # all implementation should default to 1.
  # """
  @impl true
  def claim(demand \\ 1) do
    adaptor().claim(demand)
  end

  # @doc """
  # Removes an attempt from the queue.
  # """
  @impl true
  def dequeue(attempt) do
    adaptor().dequeue(attempt)
  end

  @doc """
  Get an Attempt by id.

  Optionally preload associations by passing a list of atoms to `:include`.

      Lightning.Attempts.get(id, include: [:workflow])
  """
  @spec get(Ecto.UUID.t(), [{:include, [atom() | {atom(), [atom()]}]}]) ::
          %Attempt{} | nil
  def get(id, opts \\ []) do
    preloads = opts |> Keyword.get(:include, [])

    from(a in Attempt,
      where: a.id == ^id,
      preload: ^preloads
    )
    |> Repo.one()
  end

  def get_dataclip_body(attempt = %Attempt{}) do
    from(d in Ecto.assoc(attempt, :dataclip),
      select: type(d.body, :string)
    )
    |> Repo.one()
  end

  def start_attempt(%Attempt{} = attempt) do
    attempt
    |> Attempt.start()
    |> Repo.update()
  end

  def complete_attempt(%Attempt{} = attempt) do
    attempt
    |> Attempt.complete()
    |> Repo.update()
  end

  @doc """
  Creates a Run for a given attempt and job.

  The Run is created with and marked as started at the current time.
  """
  @spec start_run(%{required(binary()) => Ecto.UUID.t()}) ::
          {:ok, %Lightning.Invocation.Run{}} | {:error, Ecto.Changeset.t()}
  def start_run(params) do
    Handlers.StartRun.call(params)
  end

  @spec complete_run(%{required(binary()) => binary()}) ::
          {:ok, %Lightning.Invocation.Run{}} | {:error, Ecto.Changeset.t()}
  def complete_run(params) do
    Handlers.CompleteRun.call(params)
  end

  def get_project_id_for_attempt(attempt) do
    Ecto.assoc(attempt, [:work_order, :workflow, :project])
    |> Ecto.Query.select([p], p.id)
    |> Repo.one()
  end

  defp adaptor do
    Lightning.Config.attempts_adaptor()
  end
end
