%% @doc Builds and publishes `tube.channel_announced_v1' -- shared
%% between the write-reactive emitter (channel_announced_v1_to_mesh) and
%% the 60s heartbeat (channel_heartbeat), since both publish the exact
%% same fact shape, just on different triggers (Demon #45: fire-once
%% publishing over an unreliable transport is a previously-burned bug in
%% this workspace, hence the heartbeat exists at all).
-module(channel_announcement).

-export([announce/2, fact/3]).

-define(TOPIC, <<"io.macula/tube-commons/tube/channel_announced_v1">>).

-spec announce(binary() | undefined, binary()) -> ok.
announce(undefined, _Action) -> ok;
announce(ChannelId, Action) ->
    publish_from_row(project_tube_store:get_channel(ChannelId), ChannelId, Action).

publish_from_row({ok, Row}, ChannelId, Action) ->
    publish(fact(Row, ChannelId, Action));
publish_from_row({error, not_found}, _ChannelId, _Action) ->
    ok.

%% @doc The `channel_announced_v1' fact for a channel row. Text fields go
%% out as `{text, Bin}', a CBOR text string. A bare binary is a CBOR byte
%% string, which non-BEAM subscribers receive as bytes. The channel id and
%% logo mcid stay bytes.
-spec fact(map(), binary(), binary()) -> map().
fact(Row, ChannelId, Action) ->
    #{
        channel_id           => ChannelId,
        action                => text(Action),
        name                  => text(maps:get(name, Row, undefined)),
        description           => text(maps:get(description, Row, undefined)),
        owner                 => text(maps:get(owner, Row, undefined)),
        tags                  => [text(Tag) || Tag <- maps:get(tags, Row, [])],
        logo_mcid             => maps:get(logo_mcid, Row, undefined),
        published_clip_count  => published_clip_count(ChannelId),
        announced_at          => erlang:system_time(millisecond)
    }.

%% `status' on a clip row is the read model's own display-friendly
%% binary (project_tube's video_clip_lifecycle_to_video_clips.erl), not
%% the aggregate's bit-flag integer -- PRJ owns that representation
%% choice, this just reads it back.
published_clip_count(ChannelId) ->
    length([C || C <- project_tube_store:list_clips_by_channel(ChannelId),
                maps:get(status, C, undefined) =:= <<"published">>]).

text(undefined) -> undefined;
text(Bin) when is_binary(Bin) -> {text, Bin}.

publish(Fact) ->
    publish_via(hecate_om:mesh_handles(), Fact).

publish_via({ok, Pool, Realm}, Fact) ->
    {ok, _Pid} = macula_publisher:start_link(tube_mesh_publisher, Pool, Realm,
                                             ?TOPIC, Fact, []),
    ok;
publish_via({error, _}, _Fact) ->
    ok.
