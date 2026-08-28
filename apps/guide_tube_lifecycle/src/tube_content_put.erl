%% @doc Mints an MCID for the owner UI's logo/thumbnail uploads and
%% persists the bytes locally via `tube_content_store' -- no mesh
%% round trip. The MCID is just `<<1, 16#55, Blake3Hash/binary>>'
%% (macula_manifest.erl's own single-block construction), a pure local
%% computation -- macula:put_content/2 was never buying anything here
%% except a network dependency an upload has no reason to have: uploads
%% run over the owner's own LAN to this box, and nothing durable ever
%% depended on the mesh push (macula:put_content/2 is a one-time
%% peer-to-peer transfer, not storage, so no other party could read it
%% back regardless -- see tube_content_store.erl). Removing it means an
%% upload no longer fails, hangs, or silently loses the image if this
%% box's own path to the mesh happens to be down at that moment.
-module(tube_content_put).

-export([put/1]).

-spec put(binary()) -> {ok, binary()} | {error, term()}.
put(Bytes) when is_binary(Bytes) ->
    Mcid = <<1, 16#55, (macula_blake3_nif:hash(Bytes))/binary>>,
    persist_result(tube_content_store:persist(binary:encode_hex(Mcid, lowercase), Bytes), Mcid).

persist_result(ok, Mcid) -> {ok, Mcid};
persist_result({error, _} = Error, _Mcid) -> Error.
