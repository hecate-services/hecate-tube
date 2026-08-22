%% @doc Handler for upload_video_clip_v1: builds the resulting event
%% (called from the aggregate's execute/2) and dispatches the command.
-module(maybe_upload_video_clip).

-export([handle/1, handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    with_command(upload_video_clip_v1:from_map(Payload)).

with_command({ok, Cmd}) -> handle(Cmd);
with_command({error, _} = Error) -> Error.

-spec handle(upload_video_clip_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    Event = video_clip_uploaded_v1:from_command(Cmd),
    {ok, [video_clip_uploaded_v1:to_map(Event)]}.

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
