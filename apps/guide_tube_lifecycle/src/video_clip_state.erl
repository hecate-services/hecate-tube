%% @doc The `video_clip' aggregate's state: identity, metadata, the
%% edge-local file reference, and status. Owns the data shape; the
%% aggregate module owns command validation and business rules.
%%
%% `local_ref' is the edge-node-only file handle the streaming provider
%% desks read from. It must never leave this aggregate's own state -- no
%% mesh fact, no RPC response ever carries it (the spec's privacy
%% boundary depends on this).
%%
%% View count is deliberately NOT tracked here -- it doesn't gate any
%% business rule, so it belongs in the read model (project_tube_store),
%% not in aggregate state.
-module(video_clip_state).

-behaviour(evoq_state).

-include("tube_video_clip_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([clip_id/1, channel_id/1, status/1, local_ref/1]).

-record(video_clip_state, {
    clip_id        :: binary(),
    channel_id     :: binary() | undefined,
    name           :: binary() | undefined,
    description    :: binary() | undefined,
    tags           :: [binary()],
    thumbnail_mcid :: binary() | undefined,
    local_ref      :: binary() | undefined,
    source         :: binary() | undefined,
    status         :: non_neg_integer()
}).

-opaque t() :: #video_clip_state{}.
-export_type([t/0]).

-spec new(binary()) -> t().
new(ClipId) ->
    #video_clip_state{
        clip_id = ClipId,
        tags = [],
        status = 0
    }.

-spec apply_event(t(), map()) -> t().
apply_event(State, Event) ->
    do_apply(field(event_type, Event), State, Event).

do_apply(<<"video_clip_uploaded_v1">>, State, Event) ->
    State#video_clip_state{
        channel_id     = field(channel_id, Event),
        name           = field(name, Event),
        description    = field(description, Event),
        tags           = field(tags, Event),
        thumbnail_mcid = field(thumbnail_mcid, Event),
        local_ref      = field(local_ref, Event),
        source         = field(source, Event),
        status = State#video_clip_state.status bor ?VIDEO_CLIP_UPLOADED
    };
do_apply(<<"video_clip_published_v1">>, State, _Event) ->
    State#video_clip_state{
        status = State#video_clip_state.status bor ?VIDEO_CLIP_PUBLISHED
    };
do_apply(<<"video_clip_retracted_v1">>, State, _Event) ->
    State#video_clip_state{
        status = State#video_clip_state.status band (bnot ?VIDEO_CLIP_PUBLISHED)
    };
do_apply(<<"video_clip_archived_v1">>, State, _Event) ->
    State#video_clip_state{
        status = State#video_clip_state.status bor ?VIDEO_CLIP_ARCHIVED
    };
do_apply(_Other, State, _Event) ->
    State.

-spec to_map(t()) -> map().
to_map(#video_clip_state{} = S) ->
    #{
        clip_id        => S#video_clip_state.clip_id,
        channel_id     => S#video_clip_state.channel_id,
        name           => S#video_clip_state.name,
        description    => S#video_clip_state.description,
        tags           => S#video_clip_state.tags,
        thumbnail_mcid => S#video_clip_state.thumbnail_mcid,
        local_ref      => S#video_clip_state.local_ref,
        source         => S#video_clip_state.source,
        status         => S#video_clip_state.status
    }.

clip_id(#video_clip_state{clip_id = V}) -> V.
channel_id(#video_clip_state{channel_id = V}) -> V.
status(#video_clip_state{status = V}) -> V.
local_ref(#video_clip_state{local_ref = V}) -> V.

%% Tolerates atom or binary keys -- events replayed from storage arrive
%% with whatever key shape the adapter round-tripped them as.
field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
