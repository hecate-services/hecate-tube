%% @doc Event: video_clip_scanned_v1. The scan's measurements --
%% distinct from the accepted/rejected verdict built from them (see
%% video_clip_accepted_v1.erl / video_clip_rejected_v1.erl). For v1
%% they're 1:1 (any successful scan is accepted), but keeping them
%% separate now avoids a schema break once scan scope grows a real
%% pass/fail policy beyond "did the file parse". See
%% plans/EVENT_STORM_HECATE_TUBE.md sec 16.4.
-module(video_clip_scanned_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_scan/2, to_map/1]).
-export([clip_id/1, duration_ms/1, thumbnail_mcid/1]).

-record(video_clip_scanned_v1, {
    clip_id          :: binary(),
    channel_id       :: binary(),
    duration_ms      :: non_neg_integer(),
    width            :: non_neg_integer() | undefined,
    height           :: non_neg_integer() | undefined,
    codec            :: binary() | undefined,
    container_format :: binary() | undefined,
    file_size_bytes  :: non_neg_integer(),
    has_audio        :: boolean(),
    thumbnail_mcid   :: binary() | undefined,
    scanned_at       :: integer()
}).

-opaque t() :: #video_clip_scanned_v1{}.
-export_type([t/0]).

event_type() -> <<"video_clip_scanned_v1">>.

-spec new(map()) -> t().
new(#{clip_id := Id, channel_id := ChannelId, duration_ms := DurationMs,
      file_size_bytes := FileSizeBytes} = M) ->
    #video_clip_scanned_v1{
        clip_id          = Id,
        channel_id       = ChannelId,
        duration_ms      = DurationMs,
        width            = maps:get(width, M, undefined),
        height           = maps:get(height, M, undefined),
        codec            = maps:get(codec, M, undefined),
        container_format = maps:get(container_format, M, undefined),
        file_size_bytes  = FileSizeBytes,
        has_audio        = maps:get(has_audio, M, false),
        thumbnail_mcid   = maps:get(thumbnail_mcid, M, undefined),
        scanned_at       = erlang:system_time(millisecond)
    }.

%% @doc Builds the event from the upload command plus the scan result
%% map `video_clip_scan:probe/3' returned.
-spec from_scan(upload_video_clip_v1:t(), map()) -> t().
from_scan(Cmd, Scan) ->
    new(Scan#{
        clip_id    => upload_video_clip_v1:clip_id(Cmd),
        channel_id => upload_video_clip_v1:channel_id(Cmd)
    }).

-spec to_map(t()) -> map().
to_map(#video_clip_scanned_v1{} = E) ->
    #{
        event_type       => event_type(),
        clip_id          => E#video_clip_scanned_v1.clip_id,
        channel_id       => E#video_clip_scanned_v1.channel_id,
        duration_ms      => E#video_clip_scanned_v1.duration_ms,
        width            => E#video_clip_scanned_v1.width,
        height           => E#video_clip_scanned_v1.height,
        codec            => E#video_clip_scanned_v1.codec,
        container_format => E#video_clip_scanned_v1.container_format,
        file_size_bytes  => E#video_clip_scanned_v1.file_size_bytes,
        has_audio        => E#video_clip_scanned_v1.has_audio,
        thumbnail_mcid   => E#video_clip_scanned_v1.thumbnail_mcid,
        scanned_at       => E#video_clip_scanned_v1.scanned_at
    }.

clip_id(#video_clip_scanned_v1{clip_id = V}) -> V.
duration_ms(#video_clip_scanned_v1{duration_ms = V}) -> V.
thumbnail_mcid(#video_clip_scanned_v1{thumbnail_mcid = V}) -> V.
