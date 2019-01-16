
setfenv(1, require'low')
local list = require'linkedlist'

local intlist = list(int)

terra f()
	var list: intlist = nil
	var link1 = list:insert_first(12)
	var link2 = list:insert_after(link1, 13)
	print(link1, link2-link1)
	var link3 = list:insert_last(14)
	print(list.first, list.last)
	print(link1, link2-link1, link3-link2)
	--for v in list do
	--	print(v)
	--end
end
f()
