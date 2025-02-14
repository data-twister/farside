defmodule Farside.Server.UnHealthyCheck do
  @moduledoc """
  Module to check/validate the instance list only for servers with empty instance list every 90 secs, if a sync/check process isnt already running
  """
  use Task
  alias Farside.LastUpdated

  require Logger

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker
    }
  end

  def start_link(_arg) do
    Task.start_link(&poll/0)
  end

  def poll() do
    receive do
    after
      200_000 ->
        run()
        poll()
    end
  end

  def run() do
    LastUpdated.value(DateTime.utc_now())

    Logger.info("Unhealthy Service Check Running")

    Registry.dispatch(:status, "unhealthy", fn entries ->
      for {pid, _} <- entries, do: GenServer.cast(pid, :check)
    end)
  end
end
