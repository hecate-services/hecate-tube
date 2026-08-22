%% @doc Event: channel_reconfigured_v1.
-module(channel_reconfigured_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_command/1, to_map/1]).
-export([channel_id/1]).

-record(channel_reconfigured_v1, {
    channel_id      :: binary(),
    name            :: binary(),
    description     :: binary(),
    tags            :: [binary()],
    logo_mcid       :: binary() | undefined,
    reconfigured_at :: integer()
}).

-opaque t() :: #channel_reconfigured_v1{}.
-export_type([t/0]).

event_type() -> <<"channel_reconfigured_v1">>.

-spec new(map()) -> t().
new(#{channel_id := Id, name := Name, description := Description,
      tags := Tags, logo_mcid := LogoMcid}) ->
    #channel_reconfigured_v1{
        channel_id = Id,
        name = Name,
        description = Description,
        tags = Tags,
        logo_mcid = LogoMcid,
        reconfigured_at = erlang:system_time(millisecond)
    }.

-spec from_command(reconfigure_channel_v1:t()) -> t().
from_command(Cmd) ->
    new(#{
        channel_id  => reconfigure_channel_v1:channel_id(Cmd),
        name        => reconfigure_channel_v1:name(Cmd),
        description => reconfigure_channel_v1:description(Cmd),
        tags        => reconfigure_channel_v1:tags(Cmd),
        logo_mcid   => reconfigure_channel_v1:logo_mcid(Cmd)
    }).

-spec to_map(t()) -> map().
to_map(#channel_reconfigured_v1{} = E) ->
    #{
        event_type      => event_type(),
        channel_id      => E#channel_reconfigured_v1.channel_id,
        name            => E#channel_reconfigured_v1.name,
        description     => E#channel_reconfigured_v1.description,
        tags            => E#channel_reconfigured_v1.tags,
        logo_mcid       => E#channel_reconfigured_v1.logo_mcid,
        reconfigured_at => E#channel_reconfigured_v1.reconfigured_at
    }.

channel_id(#channel_reconfigured_v1{channel_id = V}) -> V.
