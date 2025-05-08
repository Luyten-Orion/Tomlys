import std/[
  options,
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

# `join(char)@success`
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

# `map@failure`
block:
  let res = accept(c => c == 'a')
    .map((c: char) => Result[char, (ParseFailures, string)].err(({}, "Failed")))
    .run(State.init("a"))
  assert res.isErr
  assert res.error.kinds == {MappingFailure}
  assert res.error.state.idx == 0

# `pure@success`
block:
  let res = pure('a').run(State.init(""))
  assert res.isOk
  assert res.unsafeGet.value == 'a'
  assert res.unsafeGet.state.idx == 0

# `corrupt@failure`
block:
  let res = corrupt(char, "Failed").run(State.init(""))
  assert res.isErr
  assert res.error.kinds == {Corruption}
  assert res.error.state.idx == 0

# `then@success`
block:
  let res = accept(c => c == 'a').then(c => pure('b')).run(State.init("a"))
  assert res.isOk
  assert res.unsafeGet.value == 'b'
  assert res.unsafeGet.state.idx == 1

# `then@failure`
block:
  let res = accept(c => c == 'a').then(c => char.corrupt("Failed")).run(State.init("a"))
  assert res.isErr
  assert res.error.kinds == {Corruption}
  # Backtracking has to be implemented by the callback
  assert res.error.state.idx == 1

# `optional[success]@success`
block:
  let res = accept(c => c == 'a').optional.run(State.init("a"))
  assert res.isOk
  assert res.unsafeGet.value.isSome
  assert res.unsafeGet.state.idx == 1

# `optional[success]@failure`
block:
  let res = accept(c => c == 'a').optional.run(State.init("b"))
  assert res.isOk
  assert res.unsafeGet.value.isNone
  assert res.unsafeGet.state.idx == 0

# `delimited[allowEmpty,trailingDelim=true]@success[empty=false]`
block:
  let res = accept(c => c == 'a')
    .delimited(accept(c => c == 'b').ignore)
    .run(State.init("ab"))
  assert res.isOk
  assert res.unsafeGet.value == @['a']
  assert res.unsafeGet.state.idx == 2

# `delimited[allowEmpty=true,trailingDelim=true]@success[empty=true]`
block:
  let res = accept(c => c == 'a')
    .delimited(accept(c => c == 'b').ignore)
    .run(State.init(""))
  assert res.isOk
  assert res.unsafeGet.value == @[]
  assert res.unsafeGet.state.idx == 0

# `delimited[allowEmpty=true,trailingDelim=false]@success`
block:
  let res = accept(c => c == 'a')
    .delimited(accept(c => c == 'b').ignore, true, false)
    .run(State.init("aba"))
  assert res.isOk
  assert res.unsafeGet.value == @['a', 'a']
  assert res.unsafeGet.state.idx == 3

# `delimited[allowEmpty=false,trailingDelim=true]@success`
block:
  let res = accept(c => c == 'a')
    .delimited(accept(c => c == 'b').ignore, false, true)
    .run(State.init("ab"))
  assert res.isOk
  assert res.unsafeGet.value == @['a']
  assert res.unsafeGet.state.idx == 2

# `delimited[allowEmpty,trailingDelim=false]@success`
block:
  let res = accept(c => c == 'a')
    .delimited(accept(c => c == 'b').ignore, false, false)
    .run(State.init("aba"))
  assert res.isOk
  assert res.unsafeGet.value == @['a', 'a']
  assert res.unsafeGet.state.idx == 3

# `delimited[allowEmpty=true,trailingDelim=false]@failure`
block:
  let res = accept(c => c == 'a')
    .delimited(accept(c => c == 'b').ignore, true, false)
    .run(State.init("ab"))
  assert res.isErr
  assert res.error.kinds == {InsufficientValues}
  assert res.error.state.idx == 0

# `delimited[allowEmpty=false,trailingDelim=true]@failure`
block:
  let res = accept(c => c == 'a')
    .delimited(accept(c => c == 'b').ignore, false, true)
    .run(State.init(""))
  assert res.isErr
  assert res.error.kinds == {ConditionFailed, InsufficientValues, Forwarded}
  assert res.error.state.idx == 0

# "encase@success"
block:
  let res = encase(
    accept(c => c == 'a'),
    accept(c => c == '(').ignore,
    accept(c => c == ')').ignore
  ).run(State.init("(a)"))
  assert res.isOk
  assert res.unsafeGet.value == 'a'
  assert res.unsafeGet.state.idx == 3

# "encase@failure[side=left]"
block:
  let res = encase(
    accept(c => c == 'a'),
    accept(c => c == '[').ignore,
    accept(c => c == ')').ignore
  ).run(State.init("(a)"))
  assert res.isErr
  assert res.error.kinds == {ConditionFailed, Forwarded}
  assert res.error.state.idx == 0

# "encase@failure[side=center]"
block:
  let res = encase(
    accept(c => c == 'x'),
    accept(c => c == '(').ignore,
    accept(c => c == ')').ignore
  ).run(State.init("(a)"))
  assert res.isErr
  assert res.error.kinds == {ConditionFailed}
  assert res.error.state.idx == 0

# "encase@failure[side=right]"
block:
  let res = encase(
    accept(c => c == 'a'),
    accept(c => c == '(').ignore,
    accept(c => c == ']').ignore
  ).run(State.init("(a)"))
  assert res.isErr
  assert res.error.kinds == {ConditionFailed, Forwarded}
  assert res.error.state.idx == 0