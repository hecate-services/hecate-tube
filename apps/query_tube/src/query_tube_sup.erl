%% @doc Supervises the QRY department. Owns no HTTP listener itself --
%% hecate_tube_sup starts the one listener and mounts routes/0 here, so
%% every desk's routes actually get served (hecate-mpong-bot scaffolded
%% this same aggregation and never wired it in; don't repeat that gap).
%%
%% Owns no mesh-advertising worker either: all four of this service's
%% capabilities (tube.lookup_channel, tube.lookup_video_clip,
%% tube.lookup_content, tube.watch_video_clip) are declared in
%% hecate_tube_service:capabilities/0 and advertised generically by
%% hecate_om:boot/1 (hecate_om >= 0.18.0, which added a streamer-backed
%% capability kind for tube.watch_video_clip). This supervisor used to
%% own a bespoke tube_mesh_providers worker duplicating that job by hand
%% -- see hecate-corpus/skills/antipatterns/structure.md, Demon 59.
-module(query_tube_sup).

-behaviour(supervisor).

-export([start_link/0, init/1, routes/0]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, []}}.

-spec routes() -> [{string(), module(), list()}].
routes() ->
    get_channel_by_id_api:routes() ++
    get_channels_page_api:routes() ++
    get_video_clips_page_api:routes() ++
    get_video_clip_by_id_api:routes().
