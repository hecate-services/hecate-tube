%% @doc RPC provider: tube.lookup_video_clip. Returns clip metadata
%% including its current view count -- only for PUBLISHED clips. Never
%% confirms the existence of an unpublished or archived clip over RPC,
%% same privacy discipline as the streaming provider.
-module(advertise_video_clip_lookup).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

%% `clip_id' is read through hecate_om_wire:field/2, not matched as an
%% atom key -- see advertise_channel_lookup:handle_request/2 for why.
handle_request(Args, State) ->
    lookup_clip(hecate_om_wire:field(clip_id, Args), State).

lookup_clip(ClipId, State) when is_binary(ClipId) ->
    reply_from(project_tube_store:get_clip(ClipId), State);
lookup_clip(_Missing, State) ->
    {error, bad_request, State}.

%% Text fields go out as `{text, Bin}', a CBOR text string. A bare binary
%% is a CBOR byte string, which non-BEAM callers receive as bytes. Ids and
%% mcids stay bytes.
reply_from({ok, #{status := <<"published">>} = Row}, State) ->
    {reply, #{
        clip_id        => maps:get(clip_id, Row, undefined),
        channel_id     => maps:get(channel_id, Row, undefined),
        name           => text(maps:get(name, Row, undefined)),
        description    => text(maps:get(description, Row, undefined)),
        tags           => [text(Tag) || Tag <- maps:get(tags, Row, [])],
        thumbnail_mcid => maps:get(thumbnail_mcid, Row, undefined),
        view_count     => maps:get(view_count, Row, 0)
    }, State};
reply_from({ok, _NotPublished}, State) ->
    {error, not_found, State};
reply_from({error, not_found}, State) ->
    {error, not_found, State}.

text(undefined) -> undefined;
text(Bin) when is_binary(Bin) -> {text, Bin}.
