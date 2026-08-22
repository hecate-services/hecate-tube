%% @doc Handler for upload_video_clip_v1: builds the resulting events
%% (called from the aggregate's execute/2) and dispatches the command.
%%
%% The scan step lives here, not in the HTTP handler -- it's part of
%% this command's own Chain of Responsibility (upload -> scan ->
%% verdict), a business rule of `upload_video_clip' itself, not a
%% transport-layer concern. See video_clip_scan.erl and
%% plans/EVENT_STORM_HECATE_TUBE.md sec 16.4.
-module(maybe_upload_video_clip).

-export([handle/1, handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    with_command(upload_video_clip_v1:from_map(Payload)).

with_command({ok, Cmd}) -> handle(Cmd);
with_command({error, _} = Error) -> Error.

-spec handle(upload_video_clip_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    UploadedEvent = video_clip_uploaded_v1:from_command(Cmd),
    with_scan(video_clip_scan:probe(upload_video_clip_v1:clip_id(Cmd),
                                    upload_video_clip_v1:local_ref(Cmd),
                                    upload_video_clip_v1:thumbnail_mcid(Cmd)),
              Cmd, UploadedEvent).

%% Scan succeeded: uploaded, scanned (measurements), accepted (verdict)
%% -- three events, one command. Bytes genuinely landed on disk either
%% way, so `uploaded' fires regardless of the verdict below.
with_scan({ok, Scan}, Cmd, UploadedEvent) ->
    ScannedEvent = video_clip_scanned_v1:from_scan(Cmd, Scan),
    AcceptedEvent = video_clip_accepted_v1:from_command(Cmd),
    {ok, [video_clip_uploaded_v1:to_map(UploadedEvent),
          video_clip_scanned_v1:to_map(ScannedEvent),
          video_clip_accepted_v1:to_map(AcceptedEvent)]};
%% Scan failed: uploaded, rejected -- no `scanned' event, since there
%% are no real measurements to record. This is `{ok, Events}', not
%% `{error, _}' -- the command was validly processed, it just resulted
%% in a rejection verdict rather than an acceptance one. Both are
%% legitimate, recorded outcomes.
with_scan({error, Reason}, Cmd, UploadedEvent) ->
    RejectedEvent = video_clip_rejected_v1:from_command(Cmd, Reason),
    {ok, [video_clip_uploaded_v1:to_map(UploadedEvent),
          video_clip_rejected_v1:to_map(RejectedEvent)]}.

-spec dispatch(map()) ->
    {ok, binary(), non_neg_integer(), [map()]} | {error, term()}.
dispatch(Params) ->
    with_new_command(upload_video_clip_v1:new(Params)).

with_new_command({ok, Cmd}) ->
    ClipId = upload_video_clip_v1:clip_id(Cmd),
    EvoqCmd = evoq_command:new(upload_video_clip, video_clip_aggregate,
                               video_clip_aggregate:stream_id(ClipId),
                               upload_video_clip_v1:to_map(Cmd)),
    with_dispatch_result(ClipId, evoq_router:dispatch(EvoqCmd));
with_new_command({error, _} = Error) ->
    Error.

with_dispatch_result(ClipId, {ok, Version, Events}) ->
    {ok, ClipId, Version, Events};
with_dispatch_result(_ClipId, {error, _} = Error) ->
    Error.
