%% @doc Publishes tube.video_clip_viewed_v1 on its OWN topic, separate
%% from the catalog rendezvous topic every channel's discoverability
%% heartbeat shares -- a view happens far more often than a config
%% change, so mixing it into that topic would flood every other
%% channel's discoverability messages. project_tube_catalog (macula-realm
%% side) subscribes to this to keep a view_count column warm for grid
%% display; the RPC lookup (advertise_video_clip_lookup) stays the
%% authoritative source for a single clip's detail page.
-module(video_clip_viewed_v1_to_mesh).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4]).

-define(TOPIC, <<"io.macula/tube-commons/tube/video_clip_viewed_v1">>).

interested_in() ->
    [<<"video_clip_viewed_v1">>].

init(_Config) ->
    {ok, undefined}.

handle_event(<<"video_clip_viewed_v1">>, Event, _Meta, State) ->
    Data = data(Event),
    Fact = #{
        clip_id    => field(clip_id, Data),
        channel_id => field(channel_id, Data),
        viewed_at  => field(viewed_at, Data)
    },
    publish(Fact),
    {ok, State};
handle_event(_Other, _Event, _Meta, State) ->
    {ok, State}.

publish(Fact) ->
    publish_via(hecate_om:mesh_handles(), Fact).

publish_via({ok, Pool, Realm}, Fact) ->
    {ok, _Pid} = macula_publisher:start_link(tube_mesh_publisher, Pool, Realm,
                                             ?TOPIC, Fact, []),
    ok;
publish_via({error, _}, _Fact) ->
    ok.

data(Event) -> maps:get(data, Event, Event).

field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
