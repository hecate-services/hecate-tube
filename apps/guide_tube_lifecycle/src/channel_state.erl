%% @doc The `channel' aggregate's state: identity, metadata, and status.
%% Owns the data shape; the aggregate module owns command validation and
%% business rules.
-module(channel_state).

-behaviour(evoq_state).

-include("tube_channel_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([channel_id/1, name/1, owner/1, status/1]).

-record(channel_state, {
    channel_id  :: binary(),
    name        :: binary() | undefined,
    description :: binary() | undefined,
    owner       :: binary() | undefined,
    tags        :: [binary()],
    logo_mcid   :: binary() | undefined,
    status      :: non_neg_integer()
}).

-opaque t() :: #channel_state{}.
-export_type([t/0]).

-spec new(binary()) -> t().
new(ChannelId) ->
    #channel_state{
        channel_id = ChannelId,
        tags = [],
        status = 0
    }.

-spec apply_event(t(), map()) -> t().
apply_event(State, Event) ->
    do_apply(field(event_type, Event), State, Event).

do_apply(<<"channel_initiated_v1">>, State, Event) ->
    State#channel_state{
        name        = field(name, Event),
        description = field(description, Event),
        owner       = field(owner, Event),
        tags        = field(tags, Event),
        logo_mcid   = field(logo_mcid, Event),
        status      = State#channel_state.status bor ?CHANNEL_INITIATED
    };
do_apply(<<"channel_reconfigured_v1">>, State, Event) ->
    State#channel_state{
        name        = field(name, Event),
        description = field(description, Event),
        tags        = field(tags, Event),
        logo_mcid   = field(logo_mcid, Event)
    };
do_apply(_Other, State, _Event) ->
    State.

-spec to_map(t()) -> map().
to_map(#channel_state{} = S) ->
    #{
        channel_id  => S#channel_state.channel_id,
        name        => S#channel_state.name,
        description => S#channel_state.description,
        owner       => S#channel_state.owner,
        tags        => S#channel_state.tags,
        logo_mcid   => S#channel_state.logo_mcid,
        status      => S#channel_state.status
    }.

channel_id(#channel_state{channel_id = V}) -> V.
name(#channel_state{name = V}) -> V.
owner(#channel_state{owner = V}) -> V.
status(#channel_state{status = V}) -> V.

%% Tolerates atom or binary keys -- events replayed from storage arrive
%% with whatever key shape the adapter round-tripped them as.
field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
