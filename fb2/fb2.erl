-module(fb2).
-compile(export_all).

%-mode(compile).
%-compile( [ native, { hipe, o3 } ] ).
%-compile( [ inline, { inline_size, 100 } ] ).

-include("fb2_info.hrl").

% convert xml from Encoding to UTF-8
decode(Encoding, Xml) ->
  case string:to_lower(Encoding) of
    "windows-1251" ->
      %io:format("decode: ~s~n", [Encoding]),
      win1251:decode(Xml);
    "windows-1252" ->
      win1252:decode(Xml);
    "utf-8" ->
      Xml;
    "iso-8859-1" ->
      iso88591:decode(Xml);
    "koi8-r" ->
      koi8r:decode(Xml);
    "UTF-8" ->
      Xml
  end.

extract(Match, String) ->
  {Start, Length}=lists:nth(2,Match),
  string:substr(String, Start+1, Length).

cut_re(String, Re, Options, Default) ->
  case re:run(String, Re, Options) of
    {match, Match} ->
      extract(Match, String);
    nomatch ->
      Default
  end.

parse_authors(Xml, Matches, Encoding) ->
  M=lists:map(fun(X) -> extract(X, Xml) end, Matches),
  %io:format("M ~p~n", [M]),

  Authors=lists:foldl(fun(A, Acc) ->
        FirstName=cut_re( A, "<first-name>(.*?)</first-name>", [dotall], ""),
        LastName=cut_re( A, "<last-name>(.*?)</last-name>", [dotall], ""),
        Acc ++ [{decode(Encoding,FirstName), decode(Encoding,LastName)}]
    end, [], M),

  %io:format("authors: ~p~n", [Authors]),
  {ok, Authors}.

read_file(File, Size) ->
  Result = file:read(File, Size),
  case Result of
    {ok, Xml} -> Xml;
    _ -> ""
  end.

parse_fb2(Filename, Acc) ->
  %io:format("parse ~p~n", [Filename]),
  {ok, XmlFile}=file:open(Filename, [read]),
  Xml=read_file(XmlFile, 4096),
  ok=file:close(XmlFile),

  %% determine encoding
  Encoding=cut_re(Xml, "<\?.*encoding=\"(.+?)\".*\?>", [], "utf-8"),
  %io:format("encoding = ~p~n", [Encoding]),

  TitleInfo=cut_re(Xml, "<title-info>(.*?)</title-info>", [dotall], ""),
  %io:format("title info: ~p~n", [TitleInfo]),

  %% find <author></author>
  case re:run(TitleInfo, "<author>(.*?)</author>", [ global | [dotall] ]) of
    {match, Match} ->
      {ok, Authors}=parse_authors(TitleInfo, Match, Encoding);
    nomatch ->
      Authors=[]
  end,
  Title=decode(Encoding, cut_re(TitleInfo, "<book-title>(.*?)</book-title>", [dotall], "")),
  Annotation=decode(Encoding, cut_re(TitleInfo, "<annotation>(.*?)</annotation>", [dotall], "")),

  [#fb2_info{encoding=Encoding, filename=Filename, authors=Authors, title=Title, annotation=Annotation}]++Acc.

dump_info(Book) ->
  io:format("~n~nfilename: ~s~n", [Book#fb2_info.filename]),
  io:format("title: ~s~n", [Book#fb2_info.title]),
  io:format("annotation: ~s~n", [Book#fb2_info.annotation]),

  lists:map(fun(A) ->
        io:format("author: ~s ~s~n", [element(1,A), element(2,A)]) end,
        Book#fb2_info.authors
      ),
  ok.

start() ->
  process_flag(trap_exit,true),

  io:format("parsing books..."),
  {Time,Results}=timer:tc(filelib, fold_files, [".", ".*\.fb2$", true, fun(F,A) -> parse_fb2(F, A) end, []]),
  %lists:map(fun dump_info/1, Results),
  io:format("ok, ~p books parsed in ~p sec~n", [length(Results), Time/1000000]),

  io:format("start db..."),
  fb2_db:start(),
  ok=fb2_db:cleanup(),
  io:format("ok~n"),

  io:format("populate books info..."),
  ok=fb2_db:insert(Results),
  io:format("ok~n"),

  io:format("starting web server..."),
  spawn_link(fb2_web, start, []),
  io:format("ok~n"),
  ok.
