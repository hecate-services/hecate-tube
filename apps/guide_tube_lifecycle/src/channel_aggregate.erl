%% @doc The `channel' aggregate: routes commands to a desk handler after
%% checking the business rule for that command against current status,
%% mirroring hecate-mpong-bot's bit-flag-guarded aggregate shape.
-module(channel_aggregate).

-behaviour(evoq_aggregate).

-include("tube_channel_status.hrl").

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

state_module() -> channel_state.

init(ChannelId) -> {ok, channel_state:new(ChannelId)}.

apply(State, Event) -> channel_state:apply_event(State, Event).

execute(State, #{command_type := CommandType} = Payload) ->
    do_execute(CommandType, channel_state:status(State), Payload).

do_execute(initiate_channel, Status, Payload)
  when Status band ?CHANNEL_INITIATED =:= 0 ->
    maybe_initiate_channel:handle_from_map(Payload);
do_execute(initiate_channel, _Status, _Payload) ->
    {error, already_initiated};
do_execute(reconfigure_channel, Status, Payload)
  when Status band ?CHANNEL_INITIATED =:= ?CHANNEL_INITIATED ->
    maybe_reconfigure_channel:handle_from_map(Payload);
do_execute(reconfigure_channel, _Status, _Payload) ->
    {error, not_initiated};
do_execute(_Other, _Status, _Payload) ->
    {error, unknown_command}.

%% A channel's id is minted (via reckon_gater_stream_id:new/1, in
%% initiate_channel_v1:new/1) at the same moment it becomes a stream id --
%% no separate derivation needed.
-spec stream_id(binary()) -> binary().
stream_id(ChannelId) -> ChannelId.
