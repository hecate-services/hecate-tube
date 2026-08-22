%% @doc Supervises the PRJ department: the ETS store facade every QRY desk
%% reads through, and one evoq_projection worker per projection module.
-module(project_tube_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        worker(project_tube_store, project_tube_store, start_link, []),
        worker(channel_lifecycle_to_channels, evoq_projection, start_link,
              [channel_lifecycle_to_channels, #{}, #{}]),
        worker(video_clip_lifecycle_to_video_clips, evoq_projection, start_link,
              [video_clip_lifecycle_to_video_clips, #{}, #{}])
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
