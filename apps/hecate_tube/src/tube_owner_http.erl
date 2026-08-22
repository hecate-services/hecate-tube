%% @doc Shared plain-HTTP-reply helpers for the owner UI's page handlers:
%% render an HTML body, redirect with a flash message (PRG pattern -- every
%% write in this UI redirects rather than rendering directly, so a
%% refresh after submit never resubmits the form), and the boring
%% method-not-allowed/error-message boilerplate every page repeats.
-module(tube_owner_http).

-export([reply_html/3, redirect/4, method_not_allowed/2, error_message/2]).

-spec reply_html(iodata(), cowboy_req:req(), State) -> {ok, cowboy_req:req(), State}.
reply_html(Body, Req0, State) ->
    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/html; charset=utf-8">>},
                           Body, Req0),
    {ok, Req, State}.

-spec redirect(binary(), binary(), cowboy_req:req(), State) -> {ok, cowboy_req:req(), State}.
redirect(Location, Message, Req0, State) ->
    Encoded = iolist_to_binary(uri_string:quote(Message)),
    Url = <<Location/binary, "?flash=", Encoded/binary>>,
    Req = cowboy_req:reply(303, #{<<"location">> => Url}, Req0),
    {ok, Req, State}.

-spec method_not_allowed(cowboy_req:req(), State) -> {ok, cowboy_req:req(), State}.
method_not_allowed(Req0, State) ->
    Req = cowboy_req:reply(405, Req0),
    {ok, Req, State}.

-spec error_message(iodata(), term()) -> binary().
error_message(Prefix, Reason) ->
    iolist_to_binary([Prefix, io_lib:format("~p", [Reason])]).
