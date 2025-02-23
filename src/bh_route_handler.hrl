-include("bh_db_worker.hrl").

-define(JSON_CONTENT, {<<"Content-Type">>, <<"application/json; charset=utf-8">>}).
-define(RESPONSE_404, {404, [?JSON_CONTENT], jiffy:encode(#{error => <<"Not Found">>})}).
-define(RESPONSE_409, {409, [?JSON_CONTENT], jiffy:encode(#{error => <<"Conflict">>})}).
-define(RESPONSE_503, {503, [?JSON_CONTENT], jiffy:encode(#{error => <<"Too Busy">>})}).
-define(RESPONSE_503_SHUTDOWN, {503, [?JSON_CONTENT], jiffy:encode(#{error => <<"Stopping">>})}).
-define(RESPONSE_400, ?RESPONSE_400("Bad Request")).
-define(RESPONSE_400(S), {400, [?JSON_CONTENT], jiffy:encode(#{error => list_to_binary((S))})}).
-define(MAX_LIMIT, 1000).
-define(DEFAULT_ARG_LIMIT, <<"100">>).
-define(GET_ARGS(A, R), bh_route_handler:get_args((A), (R))).
-define(PARSE_INTERVAL(B), bh_route_handler:parse_interval((B))).
-define(PARSE_TIMESPAN(H, L), bh_route_handler:parse_timespan((H), (L))).
-define(PARSE_BUCKETED_TIMESPAN(H, L, B),
    bh_route_handler:parse_bucketed_timespan((H), (L), (B))
).
-define(PARSE_FLOAT(F), bh_route_handler:parse_float((F))).
-define(PARSE_INT(I), bh_route_handler:parse_int((I))).

-define(MK_RESPONSE(R), ?MK_RESPONSE(R, undefined)).
-define(MK_RESPONSE(R, C), bh_route_handler:mk_response((R), (C))).
-define(INSERT_LAT_LON(L, N, F), bh_route_handler:lat_lon((L), (N), (F))).
-define(INSERT_LAT_LON(L, F), bh_route_handler:lat_lon((L), (F))).
-define(CURSOR_ENCODE(M), bh_route_handler:cursor_encode(M)).
-define(CURSOR_DECODE(B), bh_route_handler:cursor_decode(B)).
-define(BIN_TO_B64(B), base64url:encode((B))).
-define(B64_TO_BIN(B), base64url:decode((B))).
-define(BIN_TO_B58(B), list_to_binary(libp2p_crypto:bin_to_b58((B)))).
-define(SELECT_TXN_FIELDS(F), ["select t.block, t.time, t.hash, t.type, ", (F), " "]).
-define(SELECT_TXN_BASE, ?SELECT_TXN_FIELDS("t.fields")).
-define(TXN_LIST_TO_JSON(R), bh_route_txns:txn_list_to_json((R))).
-define(BLOCK_LIST_LIMIT, 100).
-define(BLOCK_TXN_LIST_LIMIT, 50).
-define(SNAPSHOT_LIST_LIMIT, 100).
-define(CHALLENGE_TXN_LIST_LIMIT, 50).
-define(PENDING_TXN_LIST_LIMIT, 100).
-define(TXN_LIST_LIMIT, 100).
