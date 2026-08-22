%% @doc Handler for initiate_channel_v1: builds the resulting event
%% (called from the aggregate's execute/2) and dispatches the command
%% (called from outside, e.g. the owner UI or a test).
-module(maybe_initiate_channel).

-export([handle/1, handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    with_command(initiate_channel_v1:from_map(Payload)).

with_command({ok, Cmd}) -> handle(Cmd);
with_command({error, _} = Error) -> Error.

-spec handle(initiate_channel_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    Event = channel_initiated_v1:from_command(Cmd),
    {ok, [channel_initiated_v1:to_map(Event)]}.

%% @doc Mint + dispatch: builds the command (minting the channel id),
%% wraps it as an #evoq_command{}, and routes it to the aggregate.
%% Returns the minted channel_id alongside the usual dispatch result so
%% the caller can look the new channel up immediately.
-spec dispatch(map()) ->
    {ok, binary(), non_neg_integer(), [map()]} | {error, term()}.
dispatch(Params) ->
    with_new_command(initiate_channel_v1:new(Params)).

with_new_command({ok, Cmd}) ->
    ChannelId = initiate_channel_v1:channel_id(Cmd),
    EvoqCmd = evoq_command:new(initiate_channel, channel_aggregate,
                               channel_aggregate:stream_id(ChannelId),
                               initiate_channel_v1:to_map(Cmd)),
    with_dispatch_result(ChannelId, evoq_router:dispatch(EvoqCmd));
with_new_command({error, _} = Error) ->
    Error.

with_dispatch_result(ChannelId, {ok, Version, Events}) ->
    {ok, ChannelId, Version, Events};
with_dispatch_result(_ChannelId, {error, _} = Error) ->
    Error.
