
setfenv(1, require'low')
local list = require'linkedlist'

local intlist = list(int)

terra f()
	var list: intlist = nil
	var i1 = list:insert_first(12)
	var i2 = list:insert_after(i1, 14)
	var i3 = list:insert_before(i2, 13)
	print() for v in list do print(@v) end
	list:remove(i3)
	print() for v in list do print(@v) end
	list:remove_last()
	print() for v in list do print(@v) end
	list:remove_first()
	print() for v in list do print(@v) end
	print'done'
end
f()
