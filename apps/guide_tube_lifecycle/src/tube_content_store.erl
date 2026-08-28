%% @doc Durable local content-address cache for hecate-tube's own clip
%% thumbnails / channel logos, keyed by the hex-encoded MCID
%% `tube_content_put' already mints.
%%
%% Exists because `macula:put_content/2' (which `tube_content_put' drives
%% via `macula_feeder') is a one-time peer-to-peer transfer, not storage:
%% "pick a link, open a dedicated content stream, run the transfer, close
%% the stream" (macula_content_transfer's own module doc). Nothing else
%% answers a LATER, unrelated caller's request for the same bytes.
%% Confirmed live 2026-08-28: a direct dial to the exact station that
%% received the original put still returned `not_found'. `tube.lookup_content'
%% (advertise_content_lookup) serves from this local copy instead.
-module(tube_content_store).

-export([persist/2, read/1]).

-spec persist(binary(), binary()) -> ok | {error, term()}.
persist(McidHex, Bytes) when is_binary(McidHex), is_binary(Bytes) ->
    ok = filelib:ensure_dir(filename:join(dir(), "placeholder")),
    file:write_file(path(McidHex), Bytes).

-spec read(binary()) -> {ok, binary()} | {error, not_found}.
read(McidHex) when is_binary(McidHex) ->
    as_not_found(file:read_file(path(McidHex))).

as_not_found({ok, Bytes}) -> {ok, Bytes};
as_not_found({error, _Reason}) -> {error, not_found}.

path(McidHex) -> filename:join(dir(), <<McidHex/binary, ".bin">>).

%% Same env var + default as hecate_tube_service:data_dir/0 -- this app
%% doesn't depend on the hecate_tube (top) app, so read directly rather
%% than introduce a dependency for one string.
dir() -> filename:join(os:getenv("HECATE_DATA_DIR", "/var/lib/hecate-tube"), "thumbnails").
