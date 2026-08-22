%% @doc Handler for reconfigure_channel_v1: builds the resulting event
%% (called from the aggregate's execute/2) and dispatches the command.
-module(maybe_reconfigure_channel).

-export([handle/1, handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    with_command(reconfigure_channel_v1:from_map(Payload)).

with_command({ok, Cmd}) -> handle(Cmd);
with_command({error, _} = Error) -> Error.

-spec handle(reconfigure_channel_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    Event = channel_reconfigured_v1:from_command(Cmd),
    {ok, [channel_reconfigured_v1:to_map(Event)]}.

-spec dispatch(map()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Params) ->
    with_command_for_dispatch(reconfigure_channel_v1:new(Params)).

with_command_for_dispatch({ok, Cmd}) ->
    ChannelId = reconfigure_channel_v1:channel_id(Cmd),
    EvoqCmd = evoq_command:new(reconfigure_channel, channel_aggregate,
                               channel_aggregate:stream_id(ChannelId),
                               reconfigure_channel_v1:to_map(Cmd)),
    evoq_router:dispatch(EvoqCmd);
with_command_for_dispatch({error, _} = Error) ->
    Error.
