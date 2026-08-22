%% @doc Event: video_clip_rejected_v1. Terminal verdict following a
%% failed scan (unreadable/corrupt file, or the probe itself timed
%% out) -- the clip's stream still exists (video_clip_uploaded_v1
%% fires regardless of scan outcome, since bytes genuinely did land on
%% disk), it simply never becomes publishable. Recording this, rather
%% than treating scan failure as a bare command error with no trace,
%% is the point: a rejected upload is a real business fact worth an
%% audit trail, not silently discarded.
-module(video_clip_rejected_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_command/2, to_map/1]).
-export([clip_id/1, reason/1]).

-record(video_clip_rejected_v1, {
    clip_id     :: binary(),
    channel_id  :: binary(),
    reason      :: binary(),
    rejected_at :: integer()
}).

-opaque t() :: #video_clip_rejected_v1{}.
-export_type([t/0]).

event_type() -> <<"video_clip_rejected_v1">>.

-spec new(map()) -> t().
new(#{clip_id := Id, channel_id := ChannelId, reason := Reason}) ->
    #video_clip_rejected_v1{
        clip_id = Id,
        channel_id = ChannelId,
        reason = Reason,
        rejected_at = erlang:system_time(millisecond)
    }.

-spec from_command(upload_video_clip_v1:t(), term()) -> t().
from_command(Cmd, Reason) ->
    new(#{
        clip_id    => upload_video_clip_v1:clip_id(Cmd),
        channel_id => upload_video_clip_v1:channel_id(Cmd),
        reason     => reason_to_binary(Reason)
    }).

reason_to_binary(Reason) when is_binary(Reason) -> Reason;
reason_to_binary(Reason) -> iolist_to_binary(io_lib:format("~p", [Reason])).

-spec to_map(t()) -> map().
to_map(#video_clip_rejected_v1{} = E) ->
    #{
        event_type  => event_type(),
        clip_id     => E#video_clip_rejected_v1.clip_id,
        channel_id  => E#video_clip_rejected_v1.channel_id,
        reason      => E#video_clip_rejected_v1.reason,
        rejected_at => E#video_clip_rejected_v1.rejected_at
    }.

clip_id(#video_clip_rejected_v1{clip_id = V}) -> V.
reason(#video_clip_rejected_v1{reason = V}) -> V.
