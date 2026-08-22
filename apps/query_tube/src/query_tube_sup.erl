%% @doc Supervises the QRY department. Owns no HTTP listener itself --
%% hecate_tube_sup starts the one listener and mounts routes/0 here, so
%% every desk's routes actually get served (hecate-mpong-bot scaffolded
%% this same aggregation and never wired it in; don't repeat that gap).
%%
%% Also owns tube_mesh_providers, which advertises this service's
%% mesh-facing RPC/Streaming providers -- a QRY-department concern since
%% every provider desk it wires (advertise_channel_lookup,
%% advertise_video_clip_lookup, stream_video_clip_by_id) lives here too.
-module(query_tube_sup).

-behaviour(supervisor).

-export([start_link/0, init/1, routes/0]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        worker(tube_mesh_providers, tube_mesh_providers, start_link, [])
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.

-spec routes() -> [{string(), module(), list()}].
routes() ->
    get_channel_by_id_api:routes() ++
    get_channels_page_api:routes() ++
    get_video_clips_page_api:routes() ++
    get_video_clip_by_id_api:routes().

worker(Id, Module, Function, Args) ->
    #{
        id       => Id,
        start    => {Module, Function, Args},
        restart  => permanent,
        shutdown => 5000,
        type     => worker,
        modules  => [Module]
    }.
