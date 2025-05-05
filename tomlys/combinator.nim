when not defined(noCallOp):
  {.experimental: "callOperator".}

import std/[
  strutils,
  options,
  sugar
]

import ./results

# TODO: Look into using SoA instead of AoS and compare perf diffs
# TODO: Improve error message reporting

type
  State* = ref object
    name*, src*: string
    idx*: int

  ParseSuccess*[T] = object
    state*: State
    when T isnot void:
      value*: T

  ParseFailureKind* = enum
    UnexpectedEndOfInput, ConditionFailed, MinCountViolation,
    NoValuesFound, InsufficientValues, Corruption, MappingFailure,
    Forwarded, Other

  ParseFailures* = set[ParseFailureKind]

  ParseFailure* = object
    state*: State
    kinds*: ParseFailures
    msg*: string

  ParseResult*[T] = Result[ParseSuccess[T], ParseFailure]

  ParseFn*[T] = proc(state: State): ParseResult[T]
  Parser*[T] = object
    fn*: ParseFn[T]

# Helpers
proc `$`*(state: State): string = (if state == nil: "nil" else: $state[])

proc construct*[T](fn: ParseFn[T]): Parser[T] = result.fn = fn

proc success*[T: not void](state: State, value: T): ParseResult[T] = typeof(result).ok ParseSuccess[T](state: state, value: value)
proc success*(state: State): ParseResult[void] = typeof(result).ok ParseSuccess[void](state: state)

proc failure*[T](state: State, failures: ParseFailures, msg: string): ParseResult[T] =
  ParseResult[T].err(ParseFailure(state: state, kinds: failures, msg: msg))

proc forward*[A, B](a: ParseResult[A], _: typedesc[B]): ParseResult[B] =
  assert a.isErr, "Forward can only be called on failures."
  result = failure[B](a.error.state, a.error.msg)
  result.incl Forwarded

proc run*[T](parser: Parser[T], state: State): ParseResult[T] = parser.fn(state)

when not defined(noCallOp):
  proc `()`*[T](parser: Parser[T], state: State): ParseResult[T] = parser.run(state)

# Constructors
proc `init`*(_: typedesc[State], src: string, name = "<string>"): State = State(src: src, name: name, idx: 0)

# Parsers
proc pure*[T: not void](value: T): Parser[T] = result.fn = (state: State) => success(state, value)
proc pure*(): Parser[void] = result.fn = (state: State) => success(state)

proc corrupt*[T](typ: typedesc[T], msg: string): Parser[T] = result.fn = (state: State) => failure[T](state, msg)

# Conditional parsers
proc consume*(): Parser[char] = construct (state: State) => (
  if state.idx < state.src.len: (inc state.idx; success(state, state.src[state.idx - 1]))
  else: failure[char](state, {UnexpectedEndOfInput}, "Unexpected end of input.")
)

# Composition
proc map*[A, B](a: Parser[A], f: A -> Result[B, (ParseFailures, string)]): Parser[B] = construct (state: State) => (
  let
    lastIdx = state.idx
    res = a.run(state)

  if res.isErr:
    res.error.state.idx = lastIdx
    return res.forward(B)

  let
    s = res.take
    mapVal = f(s.value)

  if mapVal.isErr:
    mapVal.error.state.idx = lastIdx
    var errVal = mapVal.takeErr
    errVal[0].incl MappingFailure
    return failure[B](s.state, errVal[0], errVal[1])
  success[B](s.state, mapVal.take)
)


proc then*[A, B](a: Parser[A], f: A -> Parser[B]): Parser[B] = construct (state: State) => (
  var
    lastIdx = state.idx
    res = a(state)

  if res.isErr:
    return res.forward(B)

  let s = res.take

  f(s.value).run(s.state)
)


# TODO: Return multiple failures
proc alt*[T](a: Parser[T], b: Parser[T]): Parser[T] = construct (state: State) => (
  var
    startIdx = state.idx
    res = a.run(state)

  if res.isOk: return res
  res.error.state.idx = startIdx

  startIdx = res.error.state.idx
  res = b.run(state)

  if res.isErr: res.error.state.idx = startIdx
  res
)


proc ignore*[T](p: Parser[T]): Parser[void] = construct (state: State) => (
  let
    start = state.idx
    res = p.run(state)

  if res.isOk: return success(state)
  res.error.state.idx = start
  res.forward(void)
)


proc ignoreLeft*[A, B](a: Parser[A], b: Parser[B]): Parser[B] = construct (state: State) => (
  let
    startIdx = state.idx
    res = a.run(state)
  if res.isOk: return b.run(res.take.state)
  res.error.state.idx = startIdx
  res.forward(B)
)

proc ignoreRight*[A, B](a: Parser[A], b: Parser[B]): Parser[A] = construct (state: State) => (
  var
    lastIdx = state.idx
    res = a.run(state)

  if res.isErr:
    res.error.state.idx = lastIdx
    return res

  lastIdx = res.unsafeGet.state.idx
  var bRes = b.run(res.take.state)
  if bRes.isErr:
    bRes.error.state.idx = lastIdx
    return bRes.forward(A)
  res.unsafeGet.state = bRes.take.state

  success[A](res.unsafeGet.state, res.unsafeGet.value)
)


proc repeat*[T: not void](p: Parser[T], count = none(int)): Parser[seq[T]] = construct (state: State) => (
  if count.isSome and count.unsafeGet <= 0:
    return failure[seq[T]](state, MinCountViolation, "Expected at least one value.")

  var
    lastIdx = state.idx
    res = p.run(state)

  if count.isSome:
    if res.isErr:
      res.error.state.idx = lastIdx
      return failure[seq[T]](res.takeErr.state, InsufficientValues, "Expected $1 values but failed to find any." %
        [$count.unsafeGet])

    if count.unsafeGet == 1:
      return success[seq[T]](res.takeErr.state, @[])

  var values = newSeqOfCap[T](count.get(1))
  values.add res.unsafeGet.value

  while res.isOk and (count.isNone or count.unsafeGet > values.len):
    lastIdx = res.unsafeGet.state.idx
    res = p.run(res.unsafeGet.state)
    if res.isErr: res.error.state.idx = lastIdx
    if res.isOk: values.add res.unsafeGet.value
    continue

  if count.isSome and values.len < count.unsafeGet:
    return failure[seq[T]](state, InsufficientValues,
      "Expected $1 values but only found $2." %  [$count.unsafeGet, $values.len])

  success[seq[T]](state, values)
)

proc repeat*(p: Parser[void], count = none(int)): Parser[void] = construct (state: State) => (
  if count.isSome and count.unsafeGet <= 0:
    return failure[void](state, {MinCountViolation}, "Expected at least one value.")

  var
    lastIdx = state.idx
    counter = 1
    res = p.run(state)

  if count.isSome:
    if res.isErr:
      res.error.state.idx = lastIdx
      return failure[void](res.takeErr.state, {InsufficientValues}, "Expected $1 values but failed to find any." %
        [$count.unsafeGet])

    if count.unsafeGet == 1:
      return success(res.takeErr.state)

  while res.isOk and (count.isNone or counter < count.unsafeGet):
    lastIdx = res.unsafeGet.state.idx
    res = p.run(res.unsafeGet.state)
    if res.isErr: res.error.state.idx = lastIdx
    continue

  if count.isSome and counter < count.unsafeGet:
    return failure[void](state, {InsufficientValues}, "Expected $1 values but only found $2." % 
      [$count.unsafeGet, $counter])

  success(state)
)

proc repeat*[T: not void](p: Parser[T], count: int): Parser[seq[T]] {.inline.} = p.repeat(some(count))
proc repeat*[T: void](p: Parser[T], count: int): Parser[T] {.inline.} = p.repeat(some(count))


proc accept*(cond: char -> bool): Parser[char] = construct (state: State) => (
  if state.idx < state.src.len and cond(state.src[state.idx]):
    inc state.idx
    return success(state, state.src[state.idx - 1])
  failure[char](state, {ConditionFailed}, "Failed to satisfy condition.")
)


proc optional*[T](p: Parser[T]): Parser[Option[T]] = construct (state: State) => (
  let res = p.run(state)
  if res.isOk: return success[Option[T]](res.unsafeGet.state, some(res.unsafeGet.value))
  success[Option[T]](state, none[T]())
)


proc delimited*[T: not void](p: Parser[T], delimiter: Parser[void], allowEmpty = true): Parser[seq[T]] =
  construct (state: State) => (
    var
      lastIdx = state.idx
      res = p.run(state)

    if res.isErr:
      res.error.state.idx = lastIdx
      if allowEmpty:
        return success[seq[T]](res.takeErr.state, @[])
      return res.forward(seq[T])

    var values = newSeqOfCap[T](1)
    values.add res.unsafeGet.value

    while res.isOk:
      lastIdx = res.unsafeGet.state.idx
      res = delimiter.run(res.unsafeGet.state)
      if res.isErr:
        res.error.state.idx = lastIdx
        continue

      lastIdx = res.unsafeGet.state.idx
      res = p.run(res.unsafeGet.state)
      if res.isErr:
        res.error.state.idx = lastIdx
        continue

      values.add res.unsafeGet.value

    success[seq[T]](state, values)
  )


proc delimited*[T: void](p: Parser[void], delimiter: Parser[void], allowEmpty, trailingDelim = true): Parser[void] =
  construct (state: State) => (
    var
      lastIdx = state.idx
      res = p.run(state)

    if res.isErr:
      res.error.state.idx = lastIdx
      if allowEmpty:
        return success(res.takeErr.state)
      return res

    while res.isOk:
      lastIdx = res.unsafeGet.state.idx
      res = delimiter.run(res.unsafeGet.state)
      if res.isErr:
        res.error.state.idx = lastIdx
        continue

      lastIdx = res.unsafeGet.state.idx
      res = p.run(res.unsafeGet.state)
      if res.isErr:
        res.error.state.idx = lastIdx
        if not trailingDelim:
          return failure[void](res.takeErr.state, "Expected delimiter.")
        continue

    success(state)
  )


proc encase*[T](p: Parser[T], left, right: Parser[void]): Parser[T] = construct (state: State) => (
  let startIdx = state.idx
  var res = left.run(state)

  if res.isErr:
    res.error.state.idx = startIdx
    return res.forward(T)

  res = p.run(res.unsafeGet.state)
  if res.isErr:
    res.error.state.idx = startIdx
    return res

  when T isnot void:
    let value = res.unsafeGet.value

  res = right.run(res.unsafeGet.state)
  if res.isErr:
    res.error.state.idx = startIdx
    return res.forward(T)

  when T isnot void:
    return success(res.unsafeGet.state, value)
  success(res.unsafeGet.state)
)