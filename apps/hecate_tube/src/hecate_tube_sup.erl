%% @doc Supervises this service's own processes: the QRY read API's HTTP
%% listener.
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
    Dispatch = cowboy_router:compile([{'_', query_tube_sup:routes()}]),
    ranch:child_spec(hecate_tube_http, ranch_tcp, [{port, Port}],
                     cowboy_clear, #{env => #{dispatch => Dispatch}}).
