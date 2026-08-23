%% @doc Shared HTML rendering helpers for the owner-facing UI: the page
%% shell (nav + minimal styling, dark/light via prefers-color-scheme),
%% HTML-escaping for every piece of user-supplied text this UI ever
%% interpolates (channel/clip name, description, tags), and the
%% comma-separated tags field both forms that take tags share.
%%
%% Escaping is not optional anywhere in this app: every one of those
%% fields round-trips through this owner's own browser on every page
%% render, so skipping it anywhere is a stored-XSS hole.
-module(tube_html).

-export([escape/1, page/2, flash_banner/1, parse_tags/1, format_tags/1]).

-spec escape(binary() | iodata() | undefined) -> binary().
escape(undefined) ->
    <<>>;
escape(Bin) when is_binary(Bin) ->
    B1 = binary:replace(Bin, <<"&">>, <<"&amp;">>, [global]),
    B2 = binary:replace(B1, <<"<">>, <<"&lt;">>, [global]),
    B3 = binary:replace(B2, <<">">>, <<"&gt;">>, [global]),
    B4 = binary:replace(B3, <<"\"">>, <<"&quot;">>, [global]),
    binary:replace(B4, <<"'">>, <<"&#39;">>, [global]);
escape(IoData) ->
    escape(iolist_to_binary(IoData)).

%% @doc Wraps `Body' (iodata) in the shared page shell.
-spec page(binary(), iodata()) -> iodata().
page(Title, Body) ->
    [<<"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
       "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
       "<title>">>, escape(Title), <<" - hecate-tube</title>"
       "<style>">>, css(), <<"</style></head><body>"
       "<header><a class=\"brand\" href=\"/\">&#9654; hecate-tube</a>"
       "<nav><a href=\"/\">Dashboard</a>"
       "<a href=\"/owner/channel/configure\">Channel</a>"
       "<a href=\"/owner/clips/upload\">Upload</a></nav></header>"
       "<main>">>, Body, <<"</main></body></html>">>].

-spec flash_banner(binary() | undefined) -> iodata().
flash_banner(undefined) -> <<>>;
flash_banner(<<>>) -> <<>>;
flash_banner(Flash) ->
    [<<"<p class=\"flash\">">>, escape(Flash), <<"</p>">>].

%% @doc Comma-separated tags input -> a list of trimmed, non-empty binaries.
-spec parse_tags(binary() | undefined) -> [binary()].
parse_tags(undefined) -> [];
parse_tags(<<>>) -> [];
parse_tags(Bin) ->
    Parts = binary:split(Bin, <<",">>, [global]),
    Trimmed = [string:trim(P) || P <- Parts],
    [T || T <- Trimmed, T =/= <<>>].

-spec format_tags([binary()]) -> binary().
format_tags(Tags) ->
    iolist_to_binary(lists:join(<<", ">>, Tags)).

css() ->
    <<"
:root { color-scheme: light dark; --bg: #fff; --fg: #16181c; --muted: #6b7280;
  --card: #f8f9fb; --border: #e3e5e9; --accent: #3a5ff7; --accent-hover: #2f4fe0;
  --accent-fg: #fff; --danger: #c0392b; --danger-hover: #a8321f; --radius: 12px;
  --shadow: 0 1px 2px rgba(16,24,40,.04), 0 1px 3px rgba(16,24,40,.06); }
@media (prefers-color-scheme: dark) {
  :root { --bg: #121317; --fg: #ececee; --muted: #9a9ea6; --card: #1b1d22; --border: #2c2f36;
    --shadow: 0 1px 2px rgba(0,0,0,.3), 0 2px 8px rgba(0,0,0,.25); }
}
* { box-sizing: border-box; }
body { margin: 0; font: 16px/1.6 -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  background: var(--bg); color: var(--fg); -webkit-font-smoothing: antialiased; }
a { color: inherit; }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
header { display: flex; align-items: center; justify-content: space-between;
  padding: 1rem 1.5rem; border-bottom: 1px solid var(--border); flex-wrap: wrap; gap: .5rem;
  position: sticky; top: 0; background: var(--bg); z-index: 10; }
.brand { font-weight: 700; text-decoration: none; color: var(--fg); font-size: 1.1rem;
  letter-spacing: -.01em; }
nav a { color: var(--muted); text-decoration: none; margin-left: 1.25rem; font-size: .9rem;
  transition: color .15s ease; }
nav a:hover { color: var(--fg); }
main { max-width: 760px; margin: 0 auto; padding: 2rem 1.5rem 4rem; }
h1 { margin-top: 0; letter-spacing: -.01em; }
.card { background: var(--card); border: 1px solid var(--border); border-radius: var(--radius);
  box-shadow: var(--shadow); padding: 1.25rem; margin-bottom: 1.5rem; }
.logo { max-height: 64px; max-width: 64px; border-radius: 8px; object-fit: cover;
  float: right; }
.clip-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 1rem; }
.clip { display: flex; flex-direction: column; gap: .4rem; background: var(--card);
  border: 1px solid var(--border); border-radius: var(--radius); padding: 1rem;
  box-shadow: var(--shadow); transition: transform .15s ease, border-color .15s ease; }
.clip:hover { transform: translateY(-1px); border-color: var(--accent); }
.clip h3 { margin: 0; font-size: 1rem; }
.status { display: inline-block; font-size: .7rem; text-transform: uppercase;
  font-weight: 700; letter-spacing: .05em; padding: .2rem .55rem; border-radius: 999px;
  width: fit-content; }
.status-uploaded { background: #fff3cd; color: #7a5b00; }
.status-published { background: #d4edda; color: #175c2c; }
.status-archived { background: var(--border); color: var(--muted); }
.tag { display: inline-block; background: var(--bg); border: 1px solid var(--border);
  border-radius: 999px; padding: .15rem .65rem; font-size: .78rem; margin: 0 .3rem .3rem 0;
  color: var(--muted); }
.actions { display: flex; gap: .5rem; margin-top: auto; }
.actions form { margin: 0; }
label { display: block; font-weight: 600; margin: 1.25rem 0 .35rem; font-size: .92rem; }
input[type=text], input[type=file], textarea {
  width: 100%; padding: .6rem .75rem; border: 1px solid var(--border); border-radius: 8px;
  background: var(--bg); color: var(--fg); font: inherit; transition: border-color .15s ease; }
input[type=text]:focus, textarea:focus { border-color: var(--accent); outline: none; }
textarea { resize: vertical; min-height: 5rem; }
button, .button, input[type=submit] {
  display: inline-block; background: var(--accent); color: var(--accent-fg); border: none;
  border-radius: 8px; padding: .65rem 1.2rem; font: inherit; font-weight: 600; cursor: pointer;
  text-decoration: none; transition: background .15s ease, transform .1s ease; }
button:hover, .button:hover { background: var(--accent-hover); }
button:active, .button:active { transform: translateY(1px); }
button.danger { background: var(--danger); }
button.danger:hover { background: var(--danger-hover); }
.hint { color: var(--muted); font-size: .85rem; margin-top: .3rem; }
.flash { background: var(--card); border: 1px solid var(--accent); border-radius: 8px;
  padding: .75rem 1rem; margin-bottom: 1.25rem; box-shadow: var(--shadow); }
.empty { color: var(--muted); }
.muted { color: var(--muted); font-size: .85rem; }
form.owner-form { display: flex; flex-direction: column; }
">>.
