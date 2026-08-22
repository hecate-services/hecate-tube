%% @doc Query: get a channel by id.
%% Route: GET /api/tube/channels/:channel_id
-module(get_channel_by_id_api).

-export([init/2, routes/0]).

routes() -> [{"/api/tube/channels/:channel_id", ?MODULE, []}].

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> method_not_allowed(Req0, State)
    end.

handle_get(Req0, State) ->
    ChannelId = cowboy_req:binding(channel_id, Req0),
    reply_get(project_tube_store:get_channel(ChannelId), Req0, State).

reply_get({ok, Row}, Req0, State) ->
    Body = json:encode(#{ok => true, channel => Row}),
    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req0),
    {ok, Req, State};
reply_get({error, not_found}, Req0, State) ->
    Body = json:encode(#{ok => false, error => <<"channel_not_found">>}),
    Req = cowboy_req:reply(404, #{<<"content-type">> => <<"application/json">>}, Body, Req0),
    {ok, Req, State}.

method_not_allowed(Req0, State) ->
    Req = cowboy_req:reply(405, Req0),
    {ok, Req, State}.
