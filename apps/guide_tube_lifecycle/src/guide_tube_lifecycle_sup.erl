%% @doc Supervises the CMD department's own processes: the mesh-fact
%% emitters that react to this app's own domain events, and the channel
%% heartbeat timer.
%%
%% No aggregate children here -- evoq's own aggregate registry/supervisor
%% starts channel_aggregate / video_clip_aggregate processes on demand,
%% keyed by stream id, the first time a command dispatches against them.
-module(guide_tube_lifecycle_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        worker(channel_announced_v1_to_mesh, evoq_event_handler, start_link,
              [channel_announced_v1_to_mesh, #{}, #{}]),
        worker(video_clip_announced_v1_to_mesh, evoq_event_handler, start_link,
              [video_clip_announced_v1_to_mesh, #{}, #{}]),
        worker(video_clip_viewed_v1_to_mesh, evoq_event_handler, start_link,
              [video_clip_viewed_v1_to_mesh, #{}, #{}]),
        worker(channel_heartbeat, channel_heartbeat, start_link, [])
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.

worker(Id, Module, Function, Args) ->
    #{
        id       => Id,
        start    => {Module, Function, Args},
        restart  => permanent,
        shutdown => 5000,
        type     => worker,
        modules  => [Module]
    }.
