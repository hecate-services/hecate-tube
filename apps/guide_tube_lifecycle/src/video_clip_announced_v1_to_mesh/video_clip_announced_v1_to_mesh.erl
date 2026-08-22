%% @doc Publishes tube.video_clip_announced_v1 to the fixed rendezvous
%% topic on every clip lifecycle write that changes public visibility
%% (published/retracted/archived). No heartbeat -- a clip's presence is
%% already covered by its channel's own heartbeat-carried
%% published_clip_count; see plans/EVENT_STORM_HECATE_TUBE.md sec 4.2.
-module(video_clip_announced_v1_to_mesh).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4]).

-define(TOPIC, <<"io.macula/tube-commons/tube/video_clip_announced_v1">>).

interested_in() ->
    [<<"video_clip_published_v1">>, <<"video_clip_retracted_v1">>,
     <<"video_clip_archived_v1">>].

init(_Config) ->
    {ok, undefined}.

handle_event(<<"video_clip_published_v1">>, Event, _Meta, State) ->
    announce(data(Event), <<"published">>),
    {ok, State};
handle_event(<<"video_clip_retracted_v1">>, Event, _Meta, State) ->
    announce(data(Event), <<"retracted">>),
    {ok, State};
handle_event(<<"video_clip_archived_v1">>, Event, _Meta, State) ->
    announce(data(Event), <<"archived">>),
    {ok, State};
handle_event(_Other, _Event, _Meta, State) ->
    {ok, State}.

announce(Data, Action) ->
    announce_from_row(project_tube_store:get_clip(field(clip_id, Data)),
                      field(clip_id, Data), Action).

announce_from_row({ok, Row}, ClipId, Action) ->
    Fact = #{
        clip_id        => ClipId,
        channel_id     => maps:get(channel_id, Row, undefined),
        action         => Action,
        name           => maps:get(name, Row, undefined),
        description    => maps:get(description, Row, undefined),
        tags           => maps:get(tags, Row, []),
        thumbnail_mcid => maps:get(thumbnail_mcid, Row, undefined),
        announced_at   => erlang:system_time(millisecond)
    },
    publish(Fact);
announce_from_row({error, not_found}, _ClipId, _Action) ->
    ok.

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
