%% gen server caches results
-module(bh_cache).
-behaviour(gen_server).

-define(TBL_NAME, '__bh_cache_table').
-define(ETS_OPTS, [named_table, {keypos, 2}, {read_concurrency, true}]).
-define(DEFAULT_TTL, 60). % seconds
-define(TIMER_INTERVAL, 15000). % milliseconds

-record(entry = {
          key = undefined :: term(),
          value = undefined :: term(),
          expire_ts = 0 :: non_neg_integer() }).

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
          tid = undefined :: ets:tid(),
          tref = undefined :: reference()
         }).

start_link() ->
    gen_server:start_link(?MODULE, {local, ?MODULE}, []).

-spec get( Key :: term() ) -> not_found | {ok, Value :: term() }.
get(Key) ->
    case ets:lookup(?TBL_NAME, Key) of
        [[]] -> not_found;
        [Entry] -> maybe_expired(Entry#entry.value, erlang:system_time(seconds), Entry#entry.expire_ts)
    end.

-spec put( Key :: term(),
           Value :: term() ) -> {ok, Value :: term()}.
put(Key, Value) ->
    put(Key, Value, #{}).

-spec put( Key :: term(),
           Value :: term(),
           Options :: map() ) -> {ok, Value :: term()}.
put(Key, Value, Opts) ->
    gen_server:call(?MODULE, {put, Key, Value, Opts}).

%% gen server callbacks

init([]) ->
    Tid = ets:new(?TBL_NAME, ?ETS_OPTS),
    Tref = schedule_new_tick(),
    {ok, #state{tid = Tid, tref=Tref}}.

handle_call({put, Key, Value, Opts}, _From, State) ->
    TTL = maps:get(ttl, Opts, ?DEFAULT_TTL),
    ExpireTime = erlang:system_time(seconds) + TTL,
    true = ets:insert(?TBL_NAME,
                      #entry{key = Key,
                             value = Value,
                             expire_ts = ExpireTime}),
    {reply, {ok, Value}, State};
handle_call(Call, From, State) ->
    lager:warn("Unexpected call ~p from ~p", [Call, From]),
    {reply, diediedie, State}.

handle_cast(Cast, State) ->
    lager:warn("Unexpected cast ~p", [Cast]),
    {noreply, State}.

handle_info(bh_cache_tick, State) ->
    ok = expire_cache(),
    Tref = schedule_new_tick(),
    {noreply, State#state{tref=Tref}};
handle_info(Info, State) ->
    lager:warn("Unexpected info ~p", [Info]),
    {noreply, State}.

%% internal functions
-spec maybe_expired( Value :: term(),
                     Current :: non_neg_integer(),
                     Expire :: non_neg_integer() ) -> not_found | {ok, Value :: term()}.
maybe_expired(_Value, Current, Expire) when Current >= Expire -> not_found;
maybe_expired(Value, _Current, _Expire) -> {ok, Value}.

-spec schedule_new_tick() -> reference().
schedule_new_tick() ->
    erlang:send_after(?TICK_INTERVAL, self(), bh_cache_tick).

-spec expire_cache() -> ok.
expire_cache() ->
    Current = erlang:system_time(seconds),
    Removed = ets:foldl(fun(#entry{key = K, expire_ts = E }, Acc) when Current >= Expire ->
                                true = ets:delete(?TBL_NAME, K),
                                Acc + 1;
                           (_Entry, Acc) -> Acc
                        end,
                        0,
                        ?TBL_NAME),
    lager:info("Removed ~p cache entries this tick.", [Removed]),
    ok.
