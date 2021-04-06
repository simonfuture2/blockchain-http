%% gen server caches results
-module(bh_cache).
-behaviour(gen_server).

-define(TBL_NAME, '__bh_cache_table').
-define(ETS_OPTS, [named_table]).
-define(DEFAULT_TTL, 60). % seconds

%% public API
-export([start_link/0,
         get/1,
         put/2,
         put/3]).

%% required callbacks
-export([init/2,
         handle_cast/2,
         handle_call/3,
         handle_info/2
        ]).

-record(state, {
          tid = undefined :: ets:tid()
         }).

start_link() ->
    gen_server:start_link(?MODULE, {local, ?MODULE}, []).

get(Key) ->
    case ets:lookup(?TBL_NAME, Key) of
        [[]] -> not_found;
        [{Value, ExpireTime}] -> maybe_expired(Value, erlang:system_time(seconds), ExpireTime)
    end.

put(Key, Value) ->
    put(Key, Value, []).

put(Key, Value, Opts) ->
    gen_server:call(?MODULE, {put, Key, Value, Opts}).

%% gen server callbacks

init([]) ->
    Tid = ets:new(?TBL_NAME, ?ETS_OPTS),
    {ok, #state{tid = Tid}}.

handle_call({put, Key, Value, Opts}, _From, State) ->
    TTL = maps:get(ttl, Opts, ?DEFAULT_TTL),
    ExpireTime = erlang:system_time(seconds) + TTL,
    true = ets:insert(?TBL_NAME, {Key, Value, ExpireTime}),
    {reply, {ok, Value}, State};
handle_call(Call, From, State) ->
    error_logger:warning_msg("Unexpected call ~p from ~p", [Call, From]),
    {reply, diediedie, State}.

handle_cast(Cast, State) ->
    error_logger:warning_msg("Unexpected cast ~p", [Cast]),
    {noreply, State}.

handle_info(Info, State) ->
    error_logger:warning_msg("Unexpected info ~p", [Info]),
    {noreply, State}.

maybe_expired(_Value, Current, Expire) when Current >= Expire -> not_found;
maybe_expired(Value, _Current, _Expire) -> {ok, Value}.
