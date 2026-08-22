%% @doc Query: list channels (owner's own view -- normally exactly one
%% per hecate-tube instance today, but the read model doesn't assume
%% that).
%% Route: GET /api/tube/channels
-module(get_channels_page_api).

-export([init/2, routes/0]).

routes() -> [{"/api/tube/channels", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    Channels = project_tube_store:list_channels(),
    Body = json:encode(#{ok => true, channels => Channels}),
    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req0),
    {ok, Req, State}.

method_not_allowed(Req0, State) ->
    Req = cowboy_req:reply(405, Req0),
    {ok, Req, State}.
