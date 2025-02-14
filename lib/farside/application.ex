defmodule Farside.Application do
  @moduledoc false

  use Application

  require Logger

  alias Farside.LastUpdated
  alias Farside.Server.HealthyCheck
  alias Farside.Server.UnHealthyCheck
  alias Farside.Server.DeadCheck

  @impl true
  def start(_type, _args) do
    port =
      case Application.fetch_env!(:farside, :port) do
        nil -> System.get_env("PORT", "4001")
        port -> port
      end

    Logger.info("Running on http://localhost:#{port}")

    maybe_loaded_children =
      case is_nil(System.get_env("FARSIDE_TEST")) do
        true ->
          [{HealthyCheck, []}, {UnHealthyCheck, []}, {DeadCheck, []}]

        false ->
          Logger.info("Skipping sync job setup...")
          []
      end

    children =
      [
        Plug.Cowboy.child_spec(
          scheme: :http,
          plug: Farside.Router,
          options: [
            port: String.to_integer(port)
          ]
        ),
        {LastUpdated, DateTime.utc_now()},
        {PlugAttack.Storage.Ets, name: Farside.Throttle.Storage, clean_period: 60_000},
        {DynamicSupervisor, strategy: :one_for_one, name: :instance_supervisor},
        {DynamicSupervisor, strategy: :one_for_one, name: :service_supervisor},
        {Registry, keys: :unique, name: :instance},
        {Registry, keys: :unique, name: :service},
        {Registry, keys: :duplicate, name: :status, partitions: System.schedulers_online()}
      ] ++ maybe_loaded_children

    opts = [strategy: :one_for_one, name: Farside.Supervisor]

    Supervisor.start_link(children, opts)
    |> load()
  end

  def load(response) do
    services_json_data = Application.fetch_env!(:farside, :services_json_data)

    reply =
      case String.length(services_json_data) < 10 do
        true ->
          file = Application.fetch_env!(:farside, :services_json)
          {:ok, data} = File.read(file)
          data

        false ->
          Base.decode64!(services_json_data)
      end

    {:ok, json} = Jason.decode(reply)

    for service_json <- json do
      service_atom =
        for {key, val} <- service_json, into: %{} do
          {String.to_existing_atom(key), val}
        end

      struct(%Service{}, service_atom)
      |> Farside.Instance.Supervisor.start()
    end

    response
    |> maybe_run()
  end

  def maybe_run(response) do
    if is_nil(System.get_env("FARSIDE_TEST")) do
      Task.start(fn ->
        Process.sleep(10_000)
        UnHealthyCheck.run()
      end)
    end

    response
  end
end
