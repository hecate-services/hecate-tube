%% @doc Event: video_clip_published_v1.
-module(video_clip_published_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_command/1, to_map/1]).
-export([clip_id/1]).

-record(video_clip_published_v1, {
    clip_id      :: binary(),
    channel_id   :: binary(),
    published_at :: integer()
}).

-opaque t() :: #video_clip_published_v1{}.
-export_type([t/0]).

event_type() -> <<"video_clip_published_v1">>.

-spec new(map()) -> t().
new(#{clip_id := Id, channel_id := ChannelId}) ->
    #video_clip_published_v1{
        clip_id = Id,
        channel_id = ChannelId,
        published_at = erlang:system_time(millisecond)
    }.

-spec from_command(publish_video_clip_v1:t()) -> t().
from_command(Cmd) ->
    new(#{
        clip_id    => publish_video_clip_v1:clip_id(Cmd),
        channel_id => publish_video_clip_v1:channel_id(Cmd)
    }).

-spec to_map(t()) -> map().
to_map(#video_clip_published_v1{} = E) ->
    #{
        event_type   => event_type(),
        clip_id      => E#video_clip_published_v1.clip_id,
        channel_id   => E#video_clip_published_v1.channel_id,
        published_at => E#video_clip_published_v1.published_at
    }.

clip_id(#video_clip_published_v1{clip_id = V}) -> V.
