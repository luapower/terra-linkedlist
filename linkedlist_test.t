
setfenv(1, require'low')
local list = require'linkedlist'

terra test()
	var s = [list(int)](nil)

	s:insert_first(1)
	s:insert_first(2)
	s:insert_first(3)

	--[[
	for i,e in a:backwards() do s:insert_first(e) end
	do var i = 1; for e in s do assert(e.x == i); inc(i) end end
	do var i = 3; for e in s:backwards() do assert(e.x == i); dec(i) end end

	for e in s do s:remove(e) end
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
	assert(s.first.next == s.last)

	s:remove(s.last)
	assert(s.first == s.last)
	assert(s.first.next == nil)
	assert(s.first.prev == nil)

	var e = s.last
	s:remove(s.last)
	assert(s.first == nil)
	assert(s.last == nil)
	assert(e.prev == nil)
	assert(e.next == nil)
	s:remove(e) --allowed, ignored

	s:insert_first(a:at(0))
	s:insert_after(a:at(0), a:at(2))
	s:insert_before(a:at(2), a:at(1))
	do var i = 1; for e in s do assert(e.x == i); inc(i) end end
	]]

end
test()
