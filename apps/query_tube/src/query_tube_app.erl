%% @doc OTP application entry for the QRY department.
-module(query_tube_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> query_tube_sup:start_link().

stop(_State) -> ok.
