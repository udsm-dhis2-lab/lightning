defmodule LightningWeb.CredentialLive.Edit do
  @moduledoc """
  LiveView for editing a single job, which inturn uses `LightningWeb.JobLive.FormComponent`
  for common functionality.
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:active_menu_item, :credentials)
     |> assign(:credentials, Credentials.get_credential!(id))}
  end

  defp page_title(:show), do: "Show Job"
  defp page_title(:edit), do: "Edit Job"
end