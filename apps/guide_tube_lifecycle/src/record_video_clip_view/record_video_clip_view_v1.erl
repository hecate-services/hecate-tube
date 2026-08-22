%% @doc Command: record_video_clip_view_v1 -- dispatched from inside the
%% streaming provider's own `handle_open/2' callback (query_tube's
%% stream_video_clip_by_id), the moment a stream genuinely opens for a
%% published clip. Not an API-handler dispatch and not a Policy reacting
%% to another domain event -- a third, uncontroversial dispatch site,
%% mechanically identical to what an API handler does.
-module(record_video_clip_view_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, from_map/1]).
-export([clip_id/1, channel_id/1, viewer_ref/1]).

-record(record_video_clip_view_v1, {
    clip_id    :: binary(),
    channel_id :: binary(),
    viewer_ref :: binary() | undefined
}).

-opaque t() :: #record_video_clip_view_v1{}.
-export_type([t/0]).

command_type() -> record_video_clip_view.

%% `viewer_ref' is nullable -- anonymous viewers are the common case.
-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{clip_id := Id, channel_id := ChannelId} = Params)
  when is_binary(Id), Id =/= <<>>, is_binary(ChannelId), ChannelId =/= <<>> ->
    {ok, #record_video_clip_view_v1{
        clip_id = Id,
        channel_id = ChannelId,
        viewer_ref = maps:get(viewer_ref, Params, undefined)
    }};
new(_) ->
    {error, clip_id_and_channel_id_required}.

-spec to_map(t()) -> map().
to_map(#record_video_clip_view_v1{} = Cmd) ->
    #{
        command_type => command_type(),
        clip_id      => Cmd#record_video_clip_view_v1.clip_id,
        channel_id   => Cmd#record_video_clip_view_v1.channel_id,
        viewer_ref   => Cmd#record_video_clip_view_v1.viewer_ref
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{clip_id := Id, channel_id := ChannelId, viewer_ref := ViewerRef}) ->
    {ok, #record_video_clip_view_v1{clip_id = Id, channel_id = ChannelId,
                                    viewer_ref = ViewerRef}};
from_map(_) ->
    {error, missing_required_fields}.

clip_id(#record_video_clip_view_v1{clip_id = V}) -> V.
channel_id(#record_video_clip_view_v1{channel_id = V}) -> V.
viewer_ref(#record_video_clip_view_v1{viewer_ref = V}) -> V.
