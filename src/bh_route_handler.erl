-module(bh_route_handler).

-export([mk_response/1,
         lat_lon/2, lat_lon/3]).

-callback prepare_conn(epgsql:connection()) -> ok.
-callback handle(elli:http_method(), Path::[binary()], Req::elli:req()) -> elli:result().


mk_response({ok, Json}) ->
    {ok,
     [{<<"Content-Type">>, <<"application/json; charset=utf-8">>}],
     jsone:encode(#{<<"data">> => Json}, [undefined_as_null])}.

lat_lon(Location, Fields) ->
    lat_lon(Location, {<<"lat">>, <<"lng">>}, Fields).

lat_lon(undefined, _, Fields) ->
    Fields;
lat_lon(Location, {LatName, LonName}, Fields) when is_binary(Location) ->
    {Lat, Lon} = h3:to_geo(h3:from_string(binary_to_list(Location))),
    Fields#{
            LatName => Lat,
            LonName => Lon
           }.
