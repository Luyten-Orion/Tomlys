import std/[
  unittest,
  sugar
]

import ./tomlys/results

import ./tomlys/combinator

suite "combinator":
  test "accept-match@success":
    let res = accept('a').run(State.init("abc"))
    check res.isOk
    check res.unsafeGet.value == 'a'
    check res.unsafeGet.state.idx == 1

  test "accept-match@failure":
    let res = accept('a').run(State.init("b"))
    check res.isErr
    check res.error.state.idx == 0