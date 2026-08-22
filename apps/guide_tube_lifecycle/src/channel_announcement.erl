%% @doc Builds and publishes `tube.channel_announced_v1' -- shared
%% between the write-reactive emitter (channel_announced_v1_to_mesh) and
%% the 60s heartbeat (channel_heartbeat), since both publish the exact
%% same fact shape, just on different triggers (Demon #45: fire-once
%% publishing over an unreliable transport is a previously-burned bug in
%% this workspace, hence the heartbeat exists at all).
-module(channel_announcement).

-export([announce/2]).

-define(TOPIC, <<"io.macula/tube-commons/tube/channel_announced_v1">>).

-spec announce(binary() | undefined, binary()) -> ok.
announce(undefined, _Action) -> ok;
announce(ChannelId, Action) ->
    publish_from_row(project_tube_store:get_channel(ChannelId), ChannelId, Action).

publish_from_row({ok, Row}, ChannelId, Action) ->
    Fact = #{
        channel_id           => ChannelId,
        action                => Action,
        name                  => maps:get(name, Row, undefined),
        description           => maps:get(description, Row, undefined),
        owner                 => maps:get(owner, Row, undefined),
        tags                  => maps:get(tags, Row, []),
        logo_mcid             => maps:get(logo_mcid, Row, undefined),
        published_clip_count  => published_clip_count(ChannelId),
        announced_at          => erlang:system_time(millisecond)
    },
    publish(Fact);
publish_from_row({error, not_found}, _ChannelId, _Action) ->
    ok.

%% `status' on a clip row is the read model's own display-friendly
%% binary (project_tube's video_clip_lifecycle_to_video_clips.erl), not
%% the aggregate's bit-flag integer -- PRJ owns that representation
%% choice, this just reads it back.
published_clip_count(ChannelId) ->
    length([C || C <- project_tube_store:list_clips_by_channel(ChannelId),
                maps:get(status, C, undefined) =:= <<"published">>]).

publish(Fact) ->
    publish_via(hecate_om:mesh_handles(), Fact).

publish_via({ok, Pool, Realm}, Fact) ->
    {ok, _Pid} = macula_publisher:start_link(tube_mesh_publisher, Pool, Realm,
                                             ?TOPIC, Fact, []),
    ok;
publish_via({error, _}, _Fact) ->
    ok.
