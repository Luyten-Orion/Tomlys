import std/[
  sugar
]

import ./tomlys/results

import ./tomlys/combinator

# "accept[c==a]@success"
block:
  let res = accept(c => c == 'a').run(State.init("abc"))
  assert res.isOk
  assert res.unsafeGet.value == 'a'
  assert res.unsafeGet.state.idx == 1

# "accept[c==a]@failure":
block:
  let res = accept(c => c == 'a').run(State.init("b"))
  assert res.isErr
  assert res.error.kinds == {ConditionFailed}
  assert res.error.state.idx == 0

# "consume@success"
block:
  let res = consume().run(State.init("abc"))
  assert res.isOk
  assert res.unsafeGet.state.idx == 1

# "consume@failure"
block:
  let res = consume().run(State.init(""))
  assert res.isErr
  assert res.error.kinds == {UnexpectedEndOfInput}
  assert res.error.state.idx == 0

# "ignore@success"
block:
  let res = consume().ignore().run(State.init("abc"))
  assert res.isOk
  assert res.unsafeGet.state.idx == 1

# "ignore@failure"
block:
  let res = consume().ignore().run(State.init(""))
  assert res.isErr
  assert res.error.kinds == {UnexpectedEndOfInput, Forwarded}
  assert res.error.state.idx == 0

# "ignoreLeft@success"
block:
  let res = accept(c => c == 'a').ignoreLeft(accept(c => c == 'b'))
    .run(State.init("abc"))

  assert res.isOk
  assert res.unsafeGet.value == 'b'
  assert res.unsafeGet.state.idx == 2

# "ignoreLeft@failure[side=right]"
block:
  let res = accept(c => c == 'a').ignoreLeft(accept(c => c == 'b'))
    .run(State.init("ba"))

  assert res.isErr
  assert res.error.kinds == {ConditionFailed, Forwarded}
  assert res.error.state.idx == 0

# "ignoreLeft@failure[side=left]"
block:
  let res = accept(c => c == 'a').ignoreLeft(accept(c => c == 'b'))
    .run(State.init("ac"))

  assert res.isErr
  assert res.error.kinds == {ConditionFailed}
  assert res.error.state.idx == 0

# "ignoreRight@success"
block:
  let res = accept(c => c == 'a').ignoreRight(accept(c => c == 'b'))
    .run(State.init("abc"))

  assert res.isOk
  assert res.unsafeGet.value == 'a'
  assert res.unsafeGet.state.idx == 2

# "ignoreRight@failure[side=left]"
block:
  let res = accept(c => c == 'a').ignoreRight(accept(c => c == 'b'))
    .run(State.init("ba"))

  assert res.isErr
  assert res.error.kinds == {ConditionFailed}
  assert res.error.state.idx == 0

# "ignoreRight@failure[side=right]"
block:
  let res = accept(c => c == 'a').ignoreRight(accept(c => c == 'b'))
    .run(State.init("ac"))

  assert res.isErr
  assert res.error.kinds == {ConditionFailed, Forwarded}
  assert res.error.state.idx == 0

# "repeat[count=3]@success"
block:
  let res = accept(c => c == 'a').repeat(3).run(State.init("aaa"))
  assert res.isOk
  assert res.unsafeGet.value == @['a', 'a', 'a']
  assert res.unsafeGet.state.idx == 3

# "repeat[count=None]@success"
block:
  let res = accept(c => c == 'a').repeat().run(State.init("aaabcda"))
  assert res.isOk
  assert res.unsafeGet.value == @['a', 'a', 'a']
  assert res.unsafeGet.state.idx == 3

# "repeat[count=3]@failure"
block:
  let res = accept(c => c == 'a').repeat(3).run(State.init("aa"))
  assert res.isErr
  assert res.error.kinds == {InsufficientValues}
  assert res.error.state.idx == 0

# "repeat[count=None]@success"
block:
  let res = accept(c => c == 'a').repeat().run(State.init(""))
  assert res.isOk
  assert res.unsafeGet.value == @[]
  assert res.unsafeGet.state.idx == 0

# `alt@success[side=left]`
block:
  let res = accept(c => c == 'a').alt(accept(c => c == 'b')).run(State.init("a"))
  assert res.isOk
  assert res.unsafeGet.value == 'a'
  assert res.unsafeGet.state.idx == 1

# `alt@success[side=right]`
block:
  let res = accept(c => c == 'a').alt(accept(c => c == 'b')).run(State.init("b"))
  assert res.isOk
  assert res.unsafeGet.value == 'b'
  assert res.unsafeGet.state.idx == 1

# `alt@failure[side=both]`
block:
  let res = accept(c => c == 'a').alt(accept(c => c == 'b')).run(State.init("c"))
  assert res.isErr
  assert res.error.kinds == {ConditionFailed}
  assert res.error.state.idx == 0

# `join@success`
block:
  let res = accept(c => c == 'a').join(accept(c => c == 'b')).run(State.init("ab"))
  assert res.isOk
  assert res.unsafeGet.value == @['a', 'b']
  assert res.unsafeGet.state.idx == 2

# `join(char)@failure[side=left]`
block:
  let res = accept(c => c == 'a').join(accept(c => c == 'b')).run(State.init("c"))
  assert res.isErr
  assert res.error.kinds == {ConditionFailed, Forwarded}
  assert res.error.state.idx == 0

# `join(char)@failure[side=right]`
block:
  let res = accept(c => c == 'a').join(accept(c => c == 'b')).run(State.init("ac"))
  assert res.isErr
  assert res.error.kinds == {ConditionFailed, Forwarded}
  assert res.error.state.idx == 0

# `join(void)@success`
block:
  let res = accept(c => c == 'a').ignore.join(accept(c => c == 'b').ignore)
    .run(State.init("ab"))
  assert res.isOk
  assert res.unsafeGet.state.idx == 2

# `join(void)@failure`
block:
  let res = accept(c => c == 'a').ignore.join(accept(c => c == 'b').ignore)
    .run(State.init("ac"))
  assert res.isErr
  assert res.error.kinds == {ConditionFailed, Forwarded}
  assert res.error.state.idx == 0

# `map@success`
block:
  let res = accept(c => c == 'a')
    .map((c: char) => Result[char, (ParseFailures, string)].ok(if c == 'a': 'b' else: 'c'))
    .run(State.init("a"))
  assert res.isOk
  assert res.unsafeGet.value == 'b'
  assert res.unsafeGet.state.idx == 1

