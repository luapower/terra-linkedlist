
setfenv(1, require'low')
local list = require'linkedlist'

local struct S {x: int}
terra test()
	var a = arr(S)
	a:add(S{1})
	a:add(S{2})
	a:add(S{3})

	var s = [list(S)](nil)

	for i,e in a:backwards() do s:insert_first(e) end
	do var i = 1; for e in s do assert(e.x == i); inc(i) end end
	do var i = 3; for e in s:backwards() do assert(e.x == i); dec(i) end end

	for e in s do s:remove(e) end
	assert(s.count == 0)
	assert(s.first == nil)
	assert(s.last == nil)

	for i,e in a do s:insert_last(e) end
	do var i = 1; for e in s do assert(e.x == i); inc(i) end end
	do var i = 3; for e in s:backwards() do assert(e.x == i); dec(i) end end

	for e in s do s:remove(e) end
	assert(s.first == nil)
	assert(s.last == nil)

	for i,e in a do s:insert_last(e) end
	s:remove(s.first)
	assert(s:next(s.first) == s.last)
	assert(s.count == 2)

	s:remove(s.last)
	assert(s.first == s.last)
	assert(s:next(s.first) == nil)
	assert(s:prev(s.first) == nil)
	assert(s.count == 1)

	var e = s.last
	s:remove(s.last)
	assert(s.first == nil)
	assert(s.last == nil)
	assert(s:prev(e) == nil)
	assert(s:next(e) == nil)
	assert(s.count == 0)
	s:remove(e) --allowed, ignored
	assert(s.count == 0)

	var e0 = s:insert_first(a:at(0))
	var e2 = s:insert_after(e0, a:at(2))
	var e1 = s:insert_before(e2, a:at(1))
	do var i = 1; for e in s do assert(e.x == i); inc(i) end end

end
test()
