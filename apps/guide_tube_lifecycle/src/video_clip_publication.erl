%% @doc Puts or pulls a clip's listing on the mesh catalog rendezvous
%% topics -- shared between the three PM triggers
%% (`on_video_clip_published_publish_clip',
%% `on_video_clip_retracted_withdraw_clip',
%% `on_video_clip_archived_withdraw_clip'), the same way
%% `channel_announcement' is shared between its write-reactive emitter
%% and its heartbeat. Two verbs, not one: `publish_to_mesh/1' makes the
%% clip visible, `withdraw_from_mesh/1' pulls it -- `archived' calls
%% the withdraw path too, since it's a hecate-tube-local terminal state
%% (permanent removal from every local query, "delete" being taboo)
%% and the mesh has no use for the distinction between "temporarily
%% unpublished" and "gone for good", both mean the same thing to a
%% catalog consumer. See plans/EVENT_STORM_HECATE_TUBE.md sec 16.2.
-module(video_clip_publication).

-export([publish_to_mesh/1, withdraw_from_mesh/1]).

-define(PUBLISHED_TOPIC, <<"io.macula/tube-commons/tube/video_clip_published_v1">>).
-define(RETRACTED_TOPIC, <<"io.macula/tube-commons/tube/video_clip_retracted_v1">>).

-spec publish_to_mesh(map()) -> ok.
publish_to_mesh(Data) -> send(?PUBLISHED_TOPIC, Data).

-spec withdraw_from_mesh(map()) -> ok.
withdraw_from_mesh(Data) -> send(?RETRACTED_TOPIC, Data).

send(Topic, Data) ->
    send_from_row(Topic, project_tube_store:get_clip(field(clip_id, Data)),
                  field(clip_id, Data)).

send_from_row(Topic, {ok, Row}, ClipId) ->
    Fact = #{
        clip_id        => ClipId,
        channel_id     => maps:get(channel_id, Row, undefined),
        name           => maps:get(name, Row, undefined),
        description    => maps:get(description, Row, undefined),
        tags           => maps:get(tags, Row, []),
        thumbnail_mcid => maps:get(thumbnail_mcid, Row, undefined),
        sent_at        => erlang:system_time(millisecond)
    },
    publish(Topic, Fact);
send_from_row(_Topic, {error, not_found}, _ClipId) ->
    ok.

publish(Topic, Fact) ->
    publish_via(Topic, hecate_om:mesh_handles(), Fact).

publish_via(Topic, {ok, Pool, Realm}, Fact) ->
    {ok, _Pid} = macula_publisher:start_link(tube_mesh_publisher, Pool, Realm,
                                             Topic, Fact, []),
    ok;
publish_via(_Topic, {error, _}, _Fact) ->
    ok.

field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
