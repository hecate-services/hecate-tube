%% @doc PM: on video_clip_retracted, withdraw the clip's listing from
%% the mesh catalog rendezvous topic. See video_clip_publication.erl.
-module(on_video_clip_retracted_withdraw_clip).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4]).

interested_in() -> [<<"video_clip_retracted_v1">>].

init(_Config) -> {ok, undefined}.

handle_event(<<"video_clip_retracted_v1">>, Event, _Meta, State) ->
    video_clip_publication:withdraw_from_mesh(data(Event)),
    {ok, State};
handle_event(_Other, _Event, _Meta, State) ->
    {ok, State}.

data(Event) -> maps:get(data, Event, Event).
