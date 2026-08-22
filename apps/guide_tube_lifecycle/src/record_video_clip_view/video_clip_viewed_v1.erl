%% @doc Event: video_clip_viewed_v1.
-module(video_clip_viewed_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_command/1, to_map/1]).
-export([clip_id/1]).

-record(video_clip_viewed_v1, {
    clip_id    :: binary(),
    channel_id :: binary(),
    viewed_at  :: integer(),
    viewer_ref :: binary() | undefined
}).

-opaque t() :: #video_clip_viewed_v1{}.
-export_type([t/0]).

event_type() -> <<"video_clip_viewed_v1">>.

-spec new(map()) -> t().
new(#{clip_id := Id, channel_id := ChannelId, viewer_ref := ViewerRef}) ->
    #video_clip_viewed_v1{
        clip_id = Id,
        channel_id = ChannelId,
        viewed_at = erlang:system_time(millisecond),
        viewer_ref = ViewerRef
    }.

-spec from_command(record_video_clip_view_v1:t()) -> t().
from_command(Cmd) ->
    new(#{
        clip_id    => record_video_clip_view_v1:clip_id(Cmd),
        channel_id => record_video_clip_view_v1:channel_id(Cmd),
        viewer_ref => record_video_clip_view_v1:viewer_ref(Cmd)
    }).

-spec to_map(t()) -> map().
to_map(#video_clip_viewed_v1{} = E) ->
    #{
        event_type => event_type(),
        clip_id    => E#video_clip_viewed_v1.clip_id,
        channel_id => E#video_clip_viewed_v1.channel_id,
        viewed_at  => E#video_clip_viewed_v1.viewed_at,
        viewer_ref => E#video_clip_viewed_v1.viewer_ref
    }.

clip_id(#video_clip_viewed_v1{clip_id = V}) -> V.
