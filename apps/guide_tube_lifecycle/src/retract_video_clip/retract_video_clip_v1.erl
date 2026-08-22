%% @doc Command: retract_video_clip_v1 -- returns a published clip to
%% private. Symmetric with publish_video_clip; no separate state machine.
-module(retract_video_clip_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, from_map/1]).
-export([clip_id/1, channel_id/1]).

-record(retract_video_clip_v1, {
    clip_id    :: binary(),
    channel_id :: binary()
}).

-opaque t() :: #retract_video_clip_v1{}.
-export_type([t/0]).

command_type() -> retract_video_clip.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{clip_id := Id, channel_id := ChannelId})
  when is_binary(Id), Id =/= <<>>, is_binary(ChannelId), ChannelId =/= <<>> ->
    {ok, #retract_video_clip_v1{clip_id = Id, channel_id = ChannelId}};
new(_) ->
    {error, clip_id_and_channel_id_required}.

-spec to_map(t()) -> map().
to_map(#retract_video_clip_v1{} = Cmd) ->
    #{
        command_type => command_type(),
        clip_id      => Cmd#retract_video_clip_v1.clip_id,
        channel_id   => Cmd#retract_video_clip_v1.channel_id
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{clip_id := Id, channel_id := ChannelId}) ->
    {ok, #retract_video_clip_v1{clip_id = Id, channel_id = ChannelId}};
from_map(_) ->
    {error, missing_required_fields}.

clip_id(#retract_video_clip_v1{clip_id = V}) -> V.
channel_id(#retract_video_clip_v1{channel_id = V}) -> V.
