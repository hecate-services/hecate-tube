%% @doc Supervises this service's own processes: the HTTP listener serving
%% both the owner-facing UI (tube_owner_ui_routes) and the QRY read API
%% (query_tube_sup) -- one port, two route sets, since neither owns a
%% listener of its own.
%%
%% Separate port from hecate_om's own `health_port' listener --
%% hecate_om_sup already mounts GET /health there (hecate_om_health_handler),
%% so this listener carries only this service's own business routes.
-module(hecate_tube_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, [http_listener()]}}.

http_listener() ->
    Port = application:get_env(hecate_tube, http_port, 8491),
    Routes = tube_owner_ui_routes:routes() ++ query_tube_sup:routes(),
    Dispatch = cowboy_router:compile([{'_', Routes}]),
    ranch:child_spec(hecate_tube_http, ranch_tcp, [{port, Port}],
                     cowboy_clear, #{env => #{dispatch => Dispatch}}).
