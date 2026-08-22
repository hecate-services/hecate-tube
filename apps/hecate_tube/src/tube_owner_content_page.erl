%% @doc Owner UI: serves a mesh Content MCID back over plain HTTP, so a
%% channel logo can sit behind a normal <img src="..."> instead of the
%% owner's browser needing to speak macula itself. `Mcid' arrives
%% hex-encoded in the path (the SDK's raw content-address digest isn't
%% URL-safe as-is -- same reason macula-realm's ProjectTubeCatalog hex-
%% encodes it for storage). Content is content-addressed and therefore
%% immutable under a given MCID, so the response is cached aggressively.
%% Route: GET /owner/content/:mcid_hex
-module(tube_owner_content_page).

-export([init/2, routes/0]).

routes() -> [{"/owner/content/:mcid_hex", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> tube_owner_http:method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    McidHex = cowboy_req:binding(mcid_hex, Req0),
    with_mcid(decode_hex(McidHex), Req0, State).

decode_hex(Hex) ->
    try {ok, binary:decode_hex(Hex)}
    catch _:_ -> {error, invalid_mcid}
    end.

with_mcid({ok, Mcid}, Req0, State) ->
    reply_content(tube_content_get:get(Mcid), Req0, State);
with_mcid({error, _}, Req0, State) ->
    reply_not_found(Req0, State).

reply_content({ok, Bytes}, Req0, State) ->
    Headers = #{
        <<"content-type">> => sniff_content_type(Bytes),
        <<"cache-control">> => <<"public, max-age=31536000, immutable">>
    },
    Req = cowboy_req:reply(200, Headers, Bytes, Req0),
    {ok, Req, State};
reply_content({error, _}, Req0, State) ->
    reply_not_found(Req0, State).

reply_not_found(Req0, State) ->
    Req = cowboy_req:reply(404, #{}, <<>>, Req0),
    {ok, Req, State}.

%% No content-type travels with a Content blob (it's a raw byte store,
%% see macula_download's own moduledoc) -- sniff the common `image/*'
%% formats this UI's own upload forms accept, default to a generic
%% type otherwise (still renders in most browsers via their own
%% sniffing, just not guaranteed).
sniff_content_type(<<16#FF, 16#D8, 16#FF, _/binary>>) -> <<"image/jpeg">>;
sniff_content_type(<<16#89, "PNG", 13, 10, 26, 10, _/binary>>) -> <<"image/png">>;
sniff_content_type(<<"GIF87a", _/binary>>) -> <<"image/gif">>;
sniff_content_type(<<"GIF89a", _/binary>>) -> <<"image/gif">>;
sniff_content_type(<<"RIFF", _Size:32/little, "WEBP", _/binary>>) -> <<"image/webp">>;
sniff_content_type(_Other) -> <<"application/octet-stream">>.
