%% @doc Handler for record_video_clip_view_v1: builds the resulting event
%% (called from the aggregate's execute/2) and dispatches the command.
-module(maybe_record_video_clip_view).

-export([handle/1, handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    with_command(record_video_clip_view_v1:from_map(Payload)).

with_command({ok, Cmd}) -> handle(Cmd);
with_command({error, _} = Error) -> Error.

-spec handle(record_video_clip_view_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    Event = video_clip_viewed_v1:from_command(Cmd),
    {ok, [video_clip_viewed_v1:to_map(Event)]}.

-spec dispatch(map()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Params) ->
    with_command_for_dispatch(record_video_clip_view_v1:new(Params)).

with_command_for_dispatch({ok, Cmd}) ->
    ClipId = record_video_clip_view_v1:clip_id(Cmd),
    EvoqCmd = evoq_command:new(record_video_clip_view, video_clip_aggregate,
                               video_clip_aggregate:stream_id(ClipId),
                               record_video_clip_view_v1:to_map(Cmd)),
    evoq_router:dispatch(EvoqCmd);
with_command_for_dispatch({error, _} = Error) ->
    Error.
