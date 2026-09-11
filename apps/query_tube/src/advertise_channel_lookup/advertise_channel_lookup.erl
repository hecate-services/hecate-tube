%% @doc RPC provider: tube.lookup_channel. Returns the current channel
%% snapshot plus a summary of its published clips -- the on-demand
%% refresh path for when a consumer's cached channel_announced_v1 fact
%% is suspected stale. Never confirms the existence of a channel id that
%% doesn't exist any more than the heartbeat already does.
-module(advertise_channel_lookup).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

%% `channel_id' is read through hecate_om_wire:field/2, not matched as an
%% atom key: macula's frame decoder makes a key an atom only when that
%% atom already exists in this VM, and leaves it as sent otherwise.
%% field/2 is the one place that knows the forms a key can take, and it
%% also unwraps a text value.
handle_request(Args, State) ->
    lookup_channel(hecate_om_wire:field(channel_id, Args), State).

lookup_channel(ChannelId, State) when is_binary(ChannelId) ->
    reply_from(project_tube_store:get_channel(ChannelId), ChannelId, State);
lookup_channel(_Missing, State) ->
    {error, bad_request, State}.

%% Text fields go out as `{text, Bin}', a CBOR text string. A bare binary
%% is a CBOR byte string, which non-BEAM callers receive as bytes. Ids and
%% mcids stay bytes.
reply_from({ok, Row}, ChannelId, State) ->
    {reply, #{
        channel_id  => ChannelId,
        name        => text(maps:get(name, Row, undefined)),
        description => text(maps:get(description, Row, undefined)),
        owner       => text(maps:get(owner, Row, undefined)),
        tags        => [text(Tag) || Tag <- maps:get(tags, Row, [])],
        logo_mcid   => maps:get(logo_mcid, Row, undefined),
        clips       => published_clip_summaries(ChannelId)
    }, State};
reply_from({error, not_found}, _ChannelId, State) ->
    {error, not_found, State}.

published_clip_summaries(ChannelId) ->
    [summary(C) || C <- project_tube_store:list_clips_by_channel(ChannelId),
                  maps:get(status, C, undefined) =:= <<"published">>].

summary(C) ->
    #{
        clip_id        => maps:get(clip_id, C, undefined),
        name           => text(maps:get(name, C, undefined)),
        thumbnail_mcid => maps:get(thumbnail_mcid, C, undefined),
        view_count     => maps:get(view_count, C, 0)
    }.

text(undefined) -> undefined;
text(Bin) when is_binary(Bin) -> {text, Bin}.
