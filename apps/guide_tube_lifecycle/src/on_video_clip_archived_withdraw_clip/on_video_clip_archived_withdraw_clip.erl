%% @doc PM: on video_clip_archived, withdraw the clip's listing from
%% the mesh catalog rendezvous topic -- the same withdrawal an explicit
%% retract would send, since the mesh has no use for the distinction
%% between the two (see video_clip_publication.erl).
-module(on_video_clip_archived_withdraw_clip).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4]).

interested_in() -> [<<"video_clip_archived_v1">>].

init(_Config) -> {ok, undefined}.

handle_event(<<"video_clip_archived_v1">>, Event, _Meta, State) ->
    video_clip_publication:withdraw_from_mesh(data(Event)),
    {ok, State};
handle_event(_Other, _Event, _Meta, State) ->
    {ok, State}.

data(Event) -> maps:get(data, Event, Event).
