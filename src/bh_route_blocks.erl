-module(bh_route_blocks).

-behavior(bh_route_handler).
-behavior(bh_db_worker).

-include("bh_route_handler.hrl").

-export([prepare_conn/1, handle/3]).
%% Utilities
-export([
    get_block_height/0,
    get_block_list/1,
    get_block_list_cache_time/1,
    get_block/1,
    get_block_txn_list/2
]).

-define(S_BLOCK_HEIGHT, "block_height").

-define(S_BLOCK_LIST_BEFORE, "block_list_before").

-define(S_BLOCK_BY_HASH, "block_by_hash").
-define(S_BLOCK_BY_HEIGHT, "block_by_height").
-define(S_BLOCK_HEIGHT_TXN_LIST, "block_height_txn_list").
-define(S_BLOCK_HEIGHT_TXN_LIST_BEFORE, "block_height_txn_list_before").
-define(S_BLOCK_HASH_TXN_LIST, "block_hash_txn_list_list").
-define(S_BLOCK_HASH_TXN_LIST_BEFORE, "block_hash_txn_list_before").

-define(SELECT_BLOCK_BASE,
    "select b.height, b.time, b.block_hash, b.prev_hash, b.transaction_count, b.snapshot_hash from blocks b "
).
-define(SELECT_BLOCK_HEIGHT_TXN_LIST_BASE, [
    ?SELECT_TXN_BASE,
    "from (select * from transactions where block = $1 order by hash) t "
]).

-define(SELECT_BLOCK_HASH_TXN_LIST_BASE, [
    ?SELECT_TXN_BASE,
    "from (select * from transactions where block = (select height from blocks where block_hash = $1) order by hash) t "
]).

prepare_conn(Conn) ->
    {ok, S1} = epgsql:parse(
        Conn,
        ?S_BLOCK_HEIGHT,
        "select max(height) from blocks",
        []
    ),

    {ok, S3} = epgsql:parse(
        Conn,
        ?S_BLOCK_LIST_BEFORE,
        [
            ?SELECT_BLOCK_BASE,
            "where b.height < $1 order by height DESC limit $2"
        ],
        []
    ),

    {ok, S4} = epgsql:parse(
        Conn,
        ?S_BLOCK_BY_HEIGHT,
        [
            ?SELECT_BLOCK_BASE,
            "where b.height = $1"
        ],
        []
    ),

    {ok, S5} = epgsql:parse(
        Conn,
        ?S_BLOCK_BY_HASH,
        [
            ?SELECT_BLOCK_BASE,
            "where b.block_hash = $1"
        ],
        []
    ),

    {ok, S6} = epgsql:parse(
        Conn,
        ?S_BLOCK_HEIGHT_TXN_LIST,
        [
            ?SELECT_BLOCK_HEIGHT_TXN_LIST_BASE,
            "limit ",
            integer_to_list(?BLOCK_TXN_LIST_LIMIT)
        ],
        []
    ),

    {ok, S7} = epgsql:parse(
        Conn,
        ?S_BLOCK_HEIGHT_TXN_LIST_BEFORE,
        [
            ?SELECT_BLOCK_HEIGHT_TXN_LIST_BASE,
            "where t.hash > $2",
            "limit ",
            integer_to_list(?BLOCK_TXN_LIST_LIMIT)
        ],
        []
    ),

    {ok, S8} = epgsql:parse(
        Conn,
        ?S_BLOCK_HASH_TXN_LIST,
        [
            ?SELECT_BLOCK_HASH_TXN_LIST_BASE,
            "limit ",
            integer_to_list(?BLOCK_TXN_LIST_LIMIT)
        ],
        []
    ),

    {ok, S9} = epgsql:parse(
        Conn,
        ?S_BLOCK_HASH_TXN_LIST_BEFORE,
        [
            ?SELECT_BLOCK_HASH_TXN_LIST_BASE,
            "where t.hash > $2",
            "limit ",
            integer_to_list(?BLOCK_TXN_LIST_LIMIT)
        ],
        []
    ),

    #{
        ?S_BLOCK_HEIGHT => S1,
        ?S_BLOCK_LIST_BEFORE => S3,
        ?S_BLOCK_BY_HEIGHT => S4,
        ?S_BLOCK_BY_HASH => S5,
        ?S_BLOCK_HEIGHT_TXN_LIST => S6,
        ?S_BLOCK_HEIGHT_TXN_LIST_BEFORE => S7,
        ?S_BLOCK_HASH_TXN_LIST => S8,
        ?S_BLOCK_HASH_TXN_LIST_BEFORE => S9
    }.

handle('GET', [], Req) ->
    Args = ?GET_ARGS([cursor], Req),
    Result = get_block_list(Args),
    CacheTime = get_block_list_cache_time(Result),
    ?MK_RESPONSE(Result, CacheTime);
handle('GET', [<<"height">>], _Req) ->
    ?MK_RESPONSE(get_block_height(), block_time);
handle('GET', [<<"hash">>, BlockHash], _Req) ->
    ?MK_RESPONSE(get_block({hash, BlockHash}), infinity);
handle('GET', [<<"hash">>, BlockHash, <<"transactions">>], Req) ->
    Args = ?GET_ARGS([cursor], Req),
    ?MK_RESPONSE(get_block_txn_list({hash, BlockHash}, Args), infinity);
handle('GET', [BlockId], _Req) ->
    bh_route_handler:try_or_else(
        fun() -> binary_to_integer(BlockId) end,
        fun(Height) ->
            ?MK_RESPONSE(get_block({height, Height}), infinity)
        end,
        ?RESPONSE_400
    );
handle('GET', [BlockId, <<"transactions">>], Req) ->
    Args = ?GET_ARGS([cursor], Req),
    bh_route_handler:try_or_else(
        fun() -> binary_to_integer(BlockId) end,
        fun(Height) ->
            ?MK_RESPONSE(get_block_txn_list({height, Height}, Args), infinity)
        end,
        ?RESPONSE_400
    );
handle(_Method, _Path, _Req) ->
    ?RESPONSE_404.

get_block_list([{cursor, undefined}]) ->
    {ok, #{height := Height}} = get_block_height(),
    case Height rem ?BLOCK_LIST_LIMIT of
        0 ->
            %% Handle the perfect block aligned height by returning an empty
            %% response with a cursor that can be used as the cache key.
            {ok, [], mk_block_list_cursor(Height + 1)};
        Limit ->
            {ok, _, Results} = ?PREPARED_QUERY(?S_BLOCK_LIST_BEFORE, [Height + 1, Limit]),
            {ok, block_list_to_json(Results), mk_block_list_cursor(Height + 1 - length(Results))}
    end;
get_block_list([{cursor, Cursor}]) ->
    case ?CURSOR_DECODE(Cursor) of
        {ok, #{<<"before">> := Before}} ->
            {ok, _, Results} = ?PREPARED_QUERY(?S_BLOCK_LIST_BEFORE, [Before, ?BLOCK_LIST_LIMIT]),
            {ok, block_list_to_json(Results), mk_block_list_cursor(Before - length(Results))};
        _ ->
            {error, badarg}
    end.

get_block_list_cache_time({ok, Results, _}) when length(Results) == ?BLOCK_LIST_LIMIT ->
    %% This is a proper page, cursor and a full list of entries. This reliies on
    %% the result of a block list aligned height to have 0 results.
    infinity;
get_block_list_cache_time({ok, Results, _}) when length(Results) < ?BLOCK_LIST_LIMIT ->
    %% This is a partial result. Shoudl only happen on the first result
    block_time;
get_block_list_cache_time(_) ->
    never.

mk_block_list_cursor(Before) when Before =< 1 ->
    undefined;
mk_block_list_cursor(Before) ->
    #{before => Before}.

get_block_height() ->
    {ok, _, [{Height}]} = ?PREPARED_QUERY(?S_BLOCK_HEIGHT, []),
    {ok, #{height => Height}}.

get_block({height, Height}) ->
    Result = ?PREPARED_QUERY(?S_BLOCK_BY_HEIGHT, [Height]),
    mk_block_from_result(Result);
get_block({hash, Hash}) ->
    Result = ?PREPARED_QUERY(?S_BLOCK_BY_HASH, [Hash]),
    mk_block_from_result(Result).

mk_block_from_result({ok, _, [Result]}) ->
    {ok, block_to_json(Result)};
mk_block_from_result(_) ->
    {error, not_found}.

get_block_txn_list({height, Height}, Args) ->
    case get_block({height, Height}) of
        {ok, _} ->
            get_block_txn_list(
                Height,
                {?S_BLOCK_HEIGHT_TXN_LIST, ?S_BLOCK_HEIGHT_TXN_LIST_BEFORE},
                Args
            );
        Error ->
            Error
    end;
get_block_txn_list({hash, Hash}, Args) ->
    case get_block({hash, Hash}) of
        {ok, _} ->
            get_block_txn_list(Hash, {?S_BLOCK_HASH_TXN_LIST, ?S_BLOCK_HASH_TXN_LIST_BEFORE}, Args);
        Error ->
            Error
    end.

get_block_txn_list(Block, {StartQuery, _CursorQuery}, [{cursor, undefined}]) ->
    Result = ?PREPARED_QUERY(StartQuery, [Block]),
    mk_txn_list_from_result(Result);
get_block_txn_list(Block, {_StartQuery, CursorQuery}, [{cursor, Cursor}]) ->
    case ?CURSOR_DECODE(Cursor) of
        {ok, #{<<"hash">> := Hash}} ->
            Result = ?PREPARED_QUERY(CursorQuery, [Block, Hash]),
            mk_txn_list_from_result(Result)
    end.

mk_txn_list_from_result({ok, _, Results}) ->
    {ok, ?TXN_LIST_TO_JSON(Results), mk_txn_list_cursor(Results)}.

mk_txn_list_cursor(Results) ->
    case length(Results) < ?BLOCK_TXN_LIST_LIMIT of
        true ->
            undefined;
        false ->
            {_Height, _Time, Hash, _Type, _Fields} = lists:last(Results),
            #{hash => Hash}
    end.

block_list_to_json(Results) ->
    lists:map(fun block_to_json/1, Results).

block_to_json({Height, Time, Hash, PrevHash, TxnCount, SnapshotHash}) ->
    NullToStr = fun
        (null) -> <<"">>;
        (Bin) -> Bin
    end,
    #{
        height => Height,
        time => Time,
        hash => Hash,
        prev_hash => PrevHash,
        transaction_count => TxnCount,
        snapshot_hash => NullToStr(SnapshotHash)
    }.
