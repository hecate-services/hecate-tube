%% @doc Handler for retract_video_clip_v1: builds the resulting event
%% (called from the aggregate's execute/2) and dispatches the command.
-module(maybe_retract_video_clip).

-export([handle/1, handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    with_command(retract_video_clip_v1:from_map(Payload)).

with_command({ok, Cmd}) -> handle(Cmd);
with_command({error, _} = Error) -> Error.

-spec handle(retract_video_clip_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    Event = video_clip_retracted_v1:from_command(Cmd),
    {ok, [video_clip_retracted_v1:to_map(Event)]}.

-spec dispatch(map()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Params) ->
    with_command_for_dispatch(retract_video_clip_v1:new(Params)).

with_command_for_dispatch({ok, Cmd}) ->
    ClipId = retract_video_clip_v1:clip_id(Cmd),
    EvoqCmd = evoq_command:new(retract_video_clip, video_clip_aggregate,
                               video_clip_aggregate:stream_id(ClipId),
                               retract_video_clip_v1:to_map(Cmd)),
    evoq_router:dispatch(EvoqCmd);
with_command_for_dispatch({error, _} = Error) ->
    Error.
