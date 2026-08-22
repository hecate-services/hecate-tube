%% @doc The `video_clip' aggregate: routes commands to a desk handler
%% after checking the business rule for that command against current
%% status, mirroring channel_aggregate's shape. Sibling aggregate type to
%% `channel' in this same CMD app/store, per the mpong-bot precedent of
%% one CMD app hosting multiple aggregate types.
-module(video_clip_aggregate).

-behaviour(evoq_aggregate).

-include("tube_video_clip_status.hrl").

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

state_module() -> video_clip_state.

init(ClipId) -> {ok, video_clip_state:new(ClipId)}.

apply(State, Event) -> video_clip_state:apply_event(State, Event).

execute(State, #{command_type := CommandType} = Payload) ->
    do_execute(CommandType, video_clip_state:status(State), Payload).

do_execute(upload_video_clip, Status, Payload) when Status =:= 0 ->
    maybe_upload_video_clip:handle_from_map(Payload);
do_execute(upload_video_clip, _Status, _Payload) ->
    {error, already_uploaded};

do_execute(publish_video_clip, Status, Payload)
  when Status band ?VIDEO_CLIP_UPLOADED =:= ?VIDEO_CLIP_UPLOADED,
       Status band ?VIDEO_CLIP_REJECTED =:= 0,
       Status band ?VIDEO_CLIP_PUBLISHED =:= 0,
       Status band ?VIDEO_CLIP_ARCHIVED =:= 0 ->
    maybe_publish_video_clip:handle_from_map(Payload);
do_execute(publish_video_clip, _Status, _Payload) ->
    {error, cannot_publish};

do_execute(retract_video_clip, Status, Payload)
  when Status band ?VIDEO_CLIP_PUBLISHED =:= ?VIDEO_CLIP_PUBLISHED,
       Status band ?VIDEO_CLIP_ARCHIVED =:= 0 ->
    maybe_retract_video_clip:handle_from_map(Payload);
do_execute(retract_video_clip, _Status, _Payload) ->
    {error, cannot_retract};

do_execute(archive_video_clip, Status, Payload)
  when Status band ?VIDEO_CLIP_ARCHIVED =:= 0 ->
    maybe_archive_video_clip:handle_from_map(Payload);
do_execute(archive_video_clip, _Status, _Payload) ->
    {error, already_archived};

do_execute(record_video_clip_view, Status, Payload)
  when Status band ?VIDEO_CLIP_PUBLISHED =:= ?VIDEO_CLIP_PUBLISHED ->
    maybe_record_video_clip_view:handle_from_map(Payload);
do_execute(record_video_clip_view, _Status, _Payload) ->
    {error, not_published};

do_execute(_Other, _Status, _Payload) ->
    {error, unknown_command}.

%% A clip's id is minted (via reckon_gater_stream_id:new/1, in
%% upload_video_clip_v1:new/1) at the same moment it becomes a stream id --
%% no separate derivation needed.
-spec stream_id(binary()) -> binary().
stream_id(ClipId) -> ClipId.
