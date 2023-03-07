defmodule LightningWeb.ProjectLive.Settings do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.Permissions
  alias Lightning.Accounts.User
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects.ProjectUser
  alias Lightning.{Projects, Credentials}

  on_mount({LightningWeb.Hooks, :project_scope})

  @impl true
  def mount(_params, _session, socket) do
    can_edit_project =
      case Bodyguard.permit(
             Lightning.Projects.Policy,
             :edit,
             socket.assigns.current_user,
             socket.assigns.project
           ) do
        :ok -> true
        {:error, :unauthorized} -> false
      end

    project_users =
      Projects.get_project_with_users!(socket.assigns.project.id).project_users

    credentials = Credentials.list_credentials(socket.assigns.project)

    {:ok,
     socket
     |> assign(
       active_menu_item: :settings,
       can_edit_project: can_edit_project,
       credentials: credentials,
       project_users: project_users,
       current_user: socket.assigns.current_user,
       project_changeset: Projects.change_project(socket.assigns.project)
     )}
  end

  def can_edit_project_user(
        %User{} = current_user,
        %ProjectUser{} = project_user
      ) do
    ProjectUsers
    |> Permissions.can(:edit_project_user, current_user, project_user)
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, socket |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Project settings")
  end

  @impl true
  def handle_event("validate", %{"project" => project_params} = _params, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :project_changeset, changeset)}
  end

  def handle_event("save", %{"project" => project_params} = _params, socket) do
    save_project(socket, project_params)
  end

  def handle_event(
        "set_failure_alert",
        %{
          "project_user_id" => project_user_id,
          "value" => value
        } = _params,
        socket
      ) do
    project_user = Projects.get_project_user!(project_user_id)

    changeset =
      {%{failure_alert: project_user.failure_alert}, %{failure_alert: :boolean}}
      |> Ecto.Changeset.cast(%{failure_alert: value}, [:failure_alert])

    case Ecto.Changeset.get_change(changeset, :failure_alert) do
      nil ->
        {:noreply, socket}

      setting ->
        Projects.update_project_user(project_user, %{failure_alert: setting})
        |> dispatch_flash(socket)
    end
  end

  def handle_event(
        "set_digest",
        %{"project_user_id" => project_user_id, "value" => value},
        socket
      ) do
    project_user = Projects.get_project_user!(project_user_id)

    changeset =
      {%{digest: project_user.digest |> Atom.to_string()}, %{digest: :string}}
      |> Ecto.Changeset.cast(%{digest: value}, [:digest])

    case Ecto.Changeset.get_change(changeset, :digest) do
      nil ->
        {:noreply, socket}

      digest ->
        Projects.update_project_user(project_user, %{digest: digest})
        |> dispatch_flash(socket)
    end
  end

  defp dispatch_flash(change_result, socket) do
    case change_result do
      {:ok, %ProjectUser{}} ->
        {:noreply,
         socket
         |> assign(
           :project_users,
           Projects.get_project_with_users!(socket.assigns.project.id).project_users
         )
         |> put_flash(:info, "Project user updated successfuly")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error when updating the project user")}
    end
  end

  def failure_alert(assigns) do
    ~H"""
    <%= if can_edit_project_user(@current_user, @project_user) do %>
      <select
        id={"failure-alert-#{@project_user.id}"}
        phx-change="set_failure_alert"
        phx-value-project_user_id={@project_user.id}
        class="mt-1 block w-full rounded-md border-secondary-300 shadow-sm text-sm focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-opacity-50"
      >
        <%= options_for_select(
          [Disabled: "false", Enabled: "true"],
          @project_user.failure_alert
        ) %>
      </select>
    <% else %>
      <%= if @project_user.failure_alert,
        do: "Enabled",
        else: "Disabled" %>
    <% end %>
    """
  end

  def digest(assigns) do
    # you will get a form
    # assigns.form.source.project_user
    assigns =
      assigns
      |> assign(
        can_edit_project_user:
          can_edit_project_user(assigns.current_user, assigns.project_user)
      )

    ~H"""
    <%= if @can_edit_project_user do %>
      <select
        id={"digest-#{@project_user.id}"}
        phx-change="set_digest"
        phx-value-project_user_id={@project_user.id}
        class="mt-1 block w-full rounded-md border-secondary-300 shadow-sm text-sm focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-opacity-50"
      >
        <%= options_for_select(
          [Never: "never", Daily: "daily", Weekly: "weekly", Monthly: "monthly"],
          @project_user.digest
        ) %>
      </select>
    <% else %>
      <%= @project_user.digest
      |> Atom.to_string()
      |> String.capitalize() %>
    <% end %>
    """
  end

  def role(assigns) do
    ~H"""
    <%= @project_user.role
    |> Atom.to_string()
    |> String.capitalize() %>
    """
  end

  def user(assigns) do
    ~H"""
    <%= @project_user.user.first_name %> <%= @project_user.user.last_name %>
    """
  end

  defp save_project(socket, project_params) do
    case Projects.update_project(socket.assigns.project, project_params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(:project, project)
         |> put_flash(:info, "Project updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :project_changeset, changeset)}
    end
  end
end
