:- module(msgpack, [msgpack//1]).
/** <module> Prolog MessagePack library

This module contains DCGs for packing & unpacking MessagePack data.

@author James Cash
@license GPLv3
*/
:- use_module(library(clpfd)).

% See https://github.com/msgpack/msgpack/blob/master/spec.md

% helper predicates
int_bytes(0, R, R).
int_bytes(I, Bs, R) :-
    Bl is I /\ 0xff,
    In is I >> 8,
    int_bytes(In, [Bl|Bs], R).

int_bytes(I, B) :- int_bytes(I, [], B).

pad_bytes([B], [B]).
pad_bytes([B1, B2], [B1, B2]).
pad_bytes([B1, B2, B3], [0, B1, B2, B3]).
pad_bytes([B1, B2, B3, B4], [B1, B2, B3, B4]).

%% DCGs

nil --> [0xc0].

bool(false)--> [0xc2].
bool(true) --> [0xc3].

% positive fixnum stores 7-bit positive integer
fixnum(N) -->
    [N],
    { N #=< 0b01111111,
      N #>= 0, ! }.
% negative fixnum stores 5-bit negative integer
fixnum(N) -->
    [X],
    { X in 224..255,
      N #< 0,
      N #>= -0b00011111,
      X #= 0b11100000 \/ V,
      V in 0..31,
      Inv #= 0b11111 - V,
      N #= -Inv - 1 }.
% uint8 stores an 8-bit unsigned integer
uint8(N) -->
    [0xcc, N],
    { N in 0..255 }.
%uint16 stores a 16-bit big-endian unsigned integer
uint16(N) -->
    { integer(N), N >= 0, N < 1<<17, ! },
    [0xcd, A, B],
    { B is N /\ 0xff,
      A is (N /\ 0xff00) >> 8 }.
uint16(N) -->
    [0xcd, A, B],
    { N #> 0, N #< 1 << 17,
      N #= A<<8 + B,
      [A, B] ins 0..255 }.
% uint32 stores a 32-bit big-endian unsigned integer
uint32(N) -->
    % special-case for when given an integer; we can be much faster
    % about how we pack it than the brute-force search that clp(fd)
    % would take
    { integer(N), N >= 1>>17, N < 1<<33, ! },
    [0xce, A, B, C, D],
    { D is N /\ 0xff,
      C is (N /\ 0xff00) >> 8,
      B is (N /\ 0xff0000) >> 16,
      A is (N /\ 0xff000000) >> 24 }.
uint32(N) -->
    [0xce, A, B, C, D],
    { [A,B,C,D] ins 0..255,
      N #> 0, N #< 1 << 33,
      N #= D + C << 8 + B << 16 + A << 24 }.
% uint64 stores a 64-bit big-endian unsigned integer
uint64(N) -->
    % special-case for when given an integer; we can be much faster
    % about how we pack it than the brute-force search that clp(fd)
    % would take
    { integer(N), N >= 1>>33, N < 1<<65, ! },
    [0xcf, A, B, C, D, E, F, G, H],
    { H is N /\ 0xff,
      G is (N /\ 0xff00) >> 8,
      F is (N /\ 0xff0000) >> 16,
      E is (N /\ 0xff000000) >> 24,
      D is (N /\ 0xff00000000) >> 32,
      C is (N /\ 0xff0000000000) >> 40,
      B is (N /\ 0xff000000000000) >> 48,
      A is (N /\ 0xff00000000000000) >> 56 }.
uint64(N) -->
    [0xcf, A, B, C, D, E, F, G, H],
    { [A,B,C,D,E,F,G,H] ins 0..255,
      N #> 0, N #< 1 << 65,
      N #= H + G<<8 + F<<16 + E<<24 + D<<32 + C<<40 + B<<48 + A<<56 }.
% int8 stores an 8-bit signed integer
% argument bytes are always unsigned, so need to convert
% NB. 0x80 = 0b1000 0000
int8(N) --> % neg int8
    { N in (-128)..(-1) },
    [0xd0, A],
    { A in 0..255,
      A #>= 0x80,
      Inv #= 0xff - A,
      N #= -Inv - 1 }.
int8(N) --> % pos int8
    [0xd0, N],
    { N in 0..127 }.
% int16
% TODO: add integer(N) case
int16(N) --> % neg int16
    { N in (-0x8000)..(-1) },
    [0xd1, A, B],
    { [A,B] ins 0..255,
      X #= A<<8 + B,
      A #>= 0x80,
      Inv #= 0xffff - X,
      N #= -Inv - 1,
      label([A,B]) }.
int16(N) --> % pos int16
    [0xd1, A, B],
    { [A,B] ins 0..255,
      N in 0..0x7fff,
      N #= A<<8 + B }.
% int32
int32(N) -->
    { integer(N), N >= -0x8000_0000, N =< -1, ! },
    [0xd2, A, B, C, D],
    { Inv is -(N + 1),
      X is 0xffff_ffff - Inv,
      D is X /\ 0xff,
      C is (X /\ 0xff00) >> 8,
      B is (X /\ 0xff0000) >> 16,
      A is (X /\ 0xff000000) >> 24 }.
int32(N) -->
    { integer(N), N =< 0x8000_0000, N >= 0, ! },
    [0xd2, A, B, C, D],
    { D is N /\ 0xff,
      C is (N /\ 0xff00) >> 8,
      B is (N /\ 0xff0000) >> 16,
      A is (N /\ 0xff000000) >> 24 }.
int32(N) --> % neg int32
    { N in (-0x8000_0000)..(-1) },
    [0xd2, A, B, C, D],
    { [A,B,C,D] ins 0..255,
      A #>= 0x80,
      X #= A<<24 + B<<16 + C<<8 + D,
      Inv #= 0xffff_ffff - X,
      N #= -Inv - 1 }.
int32(N) --> % pos int32
    [0xd2, A, B, C, D],
    { [A,B,C,D] ins 0..255,
      N in 0..(0x7fff_ffff),
      N #= A<<24 + B<<16 + C<<8 + D }.
% int64
int64(N) -->
    { integer(N), N >= -0x8000_0000_0000_0000, N =< -1, ! },
    [0xd3, A, B, C, D, E, F, G, H],
    { Inv is -(N + 1),
      X is 0xffff_ffff_ffff_ffff - Inv,
      H is X /\ 0xff,
      G is (X /\ 0xff00) >> 8,
      F is (X /\ 0xff0000) >> 16,
      E is (X /\ 0xff000000) >> 24,
      D is (X /\ 0xff00000000) >> 32,
      C is (X /\ 0xff0000000000) >> 40,
      B is (X /\ 0xff000000000000) >> 48,
      A is (X /\ 0xff00000000000000) >> 56 }.
int64(N) -->
    { integer(N), N >= 0x8000_0000_0000_0000, N >= 0, ! },
    [0xd3, A, B, C, D, E, F, G, H],
    { H is N /\ 0xff,
      G is (N /\ 0xff00) >> 8,
      F is (N /\ 0xff0000) >> 16,
      E is (N /\ 0xff000000) >> 24,
      D is (N /\ 0xff00000000) >> 32,
      C is (N /\ 0xff0000000000) >> 40,
      B is (N /\ 0xff000000000000) >> 48,
      A is (N /\ 0xff00000000000000) >> 56 }.
int64(N) --> % neg int64
    { N in (-0x8000_0000_0000_0000)..(-1) },
    [0xd3, A, B, C, D, E, F, G, H],
    { [A,B,C,D,E,F,G,H] ins 0..255,
      A #>= 0x80,
      X #= A<<56 + B<<48 + C<<40 + D<<32 + E<<24 + F<<16 + G<<8 + H,
      Inv #= 0xffff_ffff_ffff_ffff - X,
      N #= -Inv - 1 }.
int64(N) --> % pos int64
    [0xd3, A, B, C, D, E, F, G, H],
    { [A,B,C,D,E,F,G,H] ins 0..255,
      N in 0..(0x7fff_ffff_ffff_ffff),
      N #= A<<56 + B<<48 + C<<40 + D<<32 + E<<24 + F<<16 + G<<8 + H }.

int(N) --> fixnum(N).
int(N) --> uint8(N).
int(N) --> uint16(N).
int(N) --> uint32(N).
int(N) --> uint64(N).
int(N) --> int8(N).
int(N) --> int16(N).
int(N) --> int32(N).
int(N) --> int64(N).

%%% TODO: floats & doubles in Prolog seems painful
%% float(float(N)) -->
%%     [0xca, A, B, C, D],
%%     { [A,B,C,D] ins 0..255 }.
%% float(double(N)) -->
%%     [0xcb, A, B, C, D, E, F, G, H],
%%     { [A,B,C,D,E,F,G,H] ins 0..255 }.

str_header(N, 0xd9) :- N < 1<<8.
str_header(N, 0xda) :- N < 1<<16.
str_header(N, 0xdb) :- N < 1<<32.

str(str(S)) -->
    { string(S), string_length(S, L), L =< 31, ! },
    [H|Bytes],
    { H is 0b10100000 \/ L,
      string_codes(S, Bytes) }.
str(str(S)) -->
    { string(S), string_length(S, L), L > 31, L < 1<<32, !,
      str_header(L, H),
      int_bytes(L, LenBytes_),
      pad_bytes(LenBytes_, LenBytes),
      !,
      string_codes(S, Bytes),
      append(LenBytes, Bytes, Packed) },
    [H|Packed].
str(str(S)) -->
    [H|T],
    { H in 0b10100000..0b10111111,
      H #= 0b10100000 \/ L,
      L in 0..31,
      prefix(Bytes, T),
      length(Bytes, L),
      string_codes(S, Bytes) }.
str(str(S)) -->
    [0xd9,L|T],
    { prefix(Bytes, T),
      length(Bytes, L),
      string_codes(S, Bytes) }.
str(str(S)) -->
    [0xda,A,B|T],
    { prefix(Bytes, T),
      length(Bytes, L),
      L is A<<8 + B,
      string_codes(S, Bytes) }.
str(str(S)) -->
    [0xdb,A,B,C,D|T],
    { prefix(Bytes, T),
      length(Bytes, L),
      L is A<<24 + B<<16 + C<<8 + D,
      string_codes(S, Bytes) }.

bin(bin(Data)) -->
    [0xc4, Len|Data],
    { length(Data, Len) }.
bin(bin(Data)) -->
    [0xc5, A, B|Data],
    { Len #= A<<8 + B,
      length(Data, Len) }.
bin(bin(Data)) -->
    [0xc6, A, B, C, D|Data],
    { Len #= A<<24 + B<<16 + C<<8 + D,
      length(Data, Len) }.

% Array helper predicates
consume_msgpack_list([], [], 0) :- !.
consume_msgpack_list([A|As], Bs, N) :-
    msgpack(A, Bs, Rst),
    !,
    Nn is N - 1,
    consume_msgpack_list(As, Rst, Nn).

array_header(L, 0xdc) :- L < 1<<16.
array_header(L, 0xdd) :- L < 1<<32.

array_pad_bytes([B], [0, B]).
array_pad_bytes([A, B], [A, B]).
array_pad_bytes([A,B,C], [0,A,B,C]).
array_pad_bytes([A,B,C,D], [A,B,C,D]).

array(list(List)) -->
    { is_list(List), length(List, Len), Len < 15,
      !,
      H is 0b10010000 + Len,
      consume_msgpack_list(List, T, Len) },
    [H|T].
array(list(List)) -->
    { is_list(List), length(List, Len), Len < 1<<32,
      !,
      array_header(Len, H),
      int_bytes(Len, LenBytes_),
      array_pad_bytes(LenBytes_, LenBytes),
      !,
      consume_msgpack_list(List, Packed, Len),
      append(LenBytes, Packed, T) },
    [H|T].
array(list(List)) -->
    [H|T],
    { H in 0b10010000..0b10011111,
      H #= 0b10010000 + L,
      L in 0..15,
      consume_msgpack_list(List, T, L), ! }.
array(list(List)) -->
    [0xdc,A,B|T],
    { Len is A <<8 + B,
      consume_msgpack_list(List, T, Len) }.
array(list(List)) -->
    [0xdd,A,B,C,D|T],
    { Len is A <<24 + B<<16 + C<<8 + D,
      consume_msgpack_list(List, T, Len) }.

% Need to use pairs insead of dicts, because dicts only support atom
% or integer keys
consume_msgpack_dict([], [], 0) :- !.
consume_msgpack_dict([K-V|KVs], Bs, N) :-
    msgpack(K, Bs, Rst_),
    msgpack(V, Rst_, Rst),
    !,
    Nn is N - 1,
    consume_msgpack_dict(KVs, Rst, Nn).

map(dict(D)) -->
    { is_list(D), length(D, L), L < 15, !,
      H is 0b10000000 + L,
      consume_msgpack_dict(D, T, L) },
    [H|T].
map(dict(D)) -->
    [H|T],
    { H in 0b10000000..0b10001111,
      H #= 0b10000000 + L,
      consume_msgpack_dict(D, T, L) }.

% NB. Type is supposed to be signed, with <0 reserved
ext(ext(Type, [Data])) -->
    [0xd4, Type, Data].
ext(ext(Type, [A,B])) -->
    [0xd5, Type, A, B].
ext(ext(Type, [A,B,C,D])) -->
    [0xd6, Type, A, B, C, D].
ext(ext(Type, Data)) -->
    [0xd7, Type|Data],
    { length(Data, 8) }.
ext(ext(Type, Data)) -->
    [0xd8, Type|Data],
    { length(Data, 16) }.

msgpack(none) --> nil, !.
msgpack(str(S)) --> str(str(S)), !.
msgpack(list(L)) --> array(list(L)), !.
msgpack(dict(D)) --> map(dict(D)), !.
msgpack(bin(X)) --> bin(bin(X)), !.
msgpack(B) --> bool(B), !.
% TODO: should integers be wrapped in some way?
% should different-sized numbers be wrapped? e.g. int8(N), uint16(N)?
msgpack(N) --> int(N), !.
%% msgpack(float(N)) --> float(float(N)), !.

:- use_module(library(plunit)).
?- load_test_files([]), run_tests.