%% @doc Publishes tube.channel_announced_v1 on every channel write
%% (initiate/reconfigure) -- see channel_heartbeat for the timer-driven
%% re-publish, and channel_announcement for the shared fact-building
%% logic both use.
-module(channel_announced_v1_to_mesh).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4]).

interested_in() ->
    [<<"channel_initiated_v1">>, <<"channel_reconfigured_v1">>].

init(_Config) ->
    {ok, undefined}.

handle_event(<<"channel_initiated_v1">>, Event, _Meta, State) ->
    channel_announcement:announce(field(channel_id, data(Event)), <<"initiated">>),
    {ok, State};
handle_event(<<"channel_reconfigured_v1">>, Event, _Meta, State) ->
    channel_announcement:announce(field(channel_id, data(Event)), <<"reconfigured">>),
    {ok, State};
handle_event(_Other, _Event, _Meta, State) ->
    {ok, State}.

data(Event) -> maps:get(data, Event, Event).

field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
