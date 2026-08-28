%% @doc RPC provider: tube.lookup_content. Serves a durably-persisted
%% clip thumbnail or channel logo by its hex-encoded MCID, straight from
%% `tube_content_store' -- see that module for why this exists instead
%% of relying on `macula:get_content/2' (a one-time transfer, not a
%% store, per macula_content_transfer's own docs).
-module(advertise_content_lookup).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

%% `mcid' arrives as an atom key -- same wire round-trip macula's frame
%% decoder does for every other lookup payload in this app (see
%% advertise_video_clip_lookup.erl's note on `clip_id').
handle_request(#{mcid := McidHex}, State) ->
    reply_from(tube_content_store:read(McidHex), State);
handle_request(_Payload, State) ->
    {error, bad_request, State}.

reply_from({ok, Bytes}, State) -> {reply, #{bytes => Bytes}, State};
reply_from({error, not_found}, State) -> {error, not_found, State}.
