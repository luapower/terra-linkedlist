
setfenv(1, require'low')
local list = require'linkedlist'

local struct S {x: int}
terra test()
	var a = arr(S)
	a:add(S{1})
	a:add(S{2})
	a:add(S{3})

	var s = [list(S)](nil)

	for i,e in a:backwards() do s:insert_first(@e) end
	do var i = 1; for _,e in s do assert(e.item.x == i); inc(i) end end
	do var i = 3; for _,e in s:backwards() do assert(e.item.x == i); dec(i) end end

	for i,e in s do s:remove(i) end
	assert(s.count == 0)
	assert(s.first == -1)
	assert(s.last == -1)

	for i,e in a do s:insert_last(@e) end
	do var i = 1; for _,e in s do assert(e.item.x == i); inc(i) end end
	do var i = 3; for _,e in s:backwards() do assert(e.item.x == i); dec(i) end end

	for i,e in s do s:remove(i) end
	assert(s.first == -1)
	assert(s.last == -1)

	for i,e in a do s:insert_last(@e) end
	s:remove(s.first)
	assert(s.count == 2)

	s:remove(s.last)
	assert(s.first == s.last)
	assert(s:link(s.first).next == -1)
	assert(s:link(s.first).prev == -1)
	assert(s.count == 1)

	var e = s.last
	s:remove(s.last)
	assert(s.first == -1)
	assert(s.last == -1)
	assert(s.count == 0)

	var i0, e0 = s:insert_first(a(0))
	var i2, e2 = s:insert_after(i0, a(2))
	var i1, e1 = s:insert_before(i2, a(1))
	do var i = 1; for _,e in s do assert(e.item.x == i); inc(i) end end

end
test()
