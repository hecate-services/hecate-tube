%% @doc Event: channel_initiated_v1.
-module(channel_initiated_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, from_command/1, to_map/1]).
-export([channel_id/1]).

-record(channel_initiated_v1, {
    channel_id   :: binary(),
    name         :: binary(),
    description  :: binary(),
    owner        :: binary(),
    tags         :: [binary()],
    logo_mcid    :: binary() | undefined,
    initiated_at :: integer()
}).

-opaque t() :: #channel_initiated_v1{}.
-export_type([t/0]).

event_type() -> <<"channel_initiated_v1">>.

-spec new(map()) -> t().
new(#{channel_id := Id, name := Name, description := Description,
      owner := Owner, tags := Tags, logo_mcid := LogoMcid}) ->
    #channel_initiated_v1{
        channel_id = Id,
        name = Name,
        description = Description,
        owner = Owner,
        tags = Tags,
        logo_mcid = LogoMcid,
        initiated_at = erlang:system_time(millisecond)
    }.

-spec from_command(initiate_channel_v1:t()) -> t().
from_command(Cmd) ->
    new(#{
        channel_id  => initiate_channel_v1:channel_id(Cmd),
        name        => initiate_channel_v1:name(Cmd),
        description => initiate_channel_v1:description(Cmd),
        owner       => initiate_channel_v1:owner(Cmd),
        tags        => initiate_channel_v1:tags(Cmd),
        logo_mcid   => initiate_channel_v1:logo_mcid(Cmd)
    }).

-spec to_map(t()) -> map().
to_map(#channel_initiated_v1{} = E) ->
    #{
        event_type   => event_type(),
        channel_id   => E#channel_initiated_v1.channel_id,
        name         => E#channel_initiated_v1.name,
        description  => E#channel_initiated_v1.description,
        owner        => E#channel_initiated_v1.owner,
        tags         => E#channel_initiated_v1.tags,
        logo_mcid    => E#channel_initiated_v1.logo_mcid,
        initiated_at => E#channel_initiated_v1.initiated_at
    }.

channel_id(#channel_initiated_v1{channel_id = V}) -> V.
