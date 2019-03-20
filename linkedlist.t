--[[

	Self-allocated doubly-linked list for Terra.
	Written by Cosmin Apreutesei. Public domain.

	Implemented using a dynarray and a freelist, which means that the location
	of the elements in memory is not stable between inserts unless the list is
	preallocated and doesn't grow. Indices are stable though and can be used
	to retrieve the same element after any number of mutations.

	local list_type = list(T,[size_t=int])      create a list type
	var list = list_type(nil)                   create a list object
	var list = list(T,[size_t])                 create a list object

	list:init()                                 initialize (for struct members)
	list:clear()                                remove items, keep the memory
	list:free()                                 free (items are not freed!)
	list.min_capacity                           (write/only) grow capacity

	list:index(i|&e) -> i                       index of valid element
	list:at(i) -> &e                            element at valid index

	list.first_index <-> i                      (read/write) index of first element
	list.last_index  <-> i                      (read/write) index of last element
	list:next_index(i|&e) -> i                  index of next element
	list:prev_index(i|&e) -> i                  index of prev element

	list.first <-> &e                           (read/write) first element
	list.last  <-> &e                           (read/write) last element
	list:next(i|&e) -> &e                       next element
	list:prev(i|&e) -> &e                       prev element

	for i,&e in list do ... end                 iterate elements (remove() works inside)
	for i,&e in list:backwards() do ... end     iterate backwards (remove() works inside)

	list:insert_before(i[,v|&v]) -> &e          insert v before i|first
	list:insert_after(i[,v|&v]) -> &e           insert v after i|last
	list:insert_first([v|&v]) -> &e             insert at the front
	list:insert_last([v|&v]) -> &e              insert at the back
	list:remove(i|&e)                           remove element

]]

if not ... then require'linkedlist_test'; return end

setfenv(1, require'low')

local function list_type(T, size_t)

	local struct link {
		item: T; --must be the first field!
		next_index: size_t;
		prev_index: size_t;
	}

	local links = arr{T = link, size_t = size_t}
	local free_indices = arr{T = size_t, size_t = size_t}

	local struct list (gettersandsetters) {
		links: links;
		free_indices: free_indices;
		first_index: size_t;
		last_index: size_t;
		count: size_t;
	}

	list.empty = `list {
		links = links(nil);
		free_indices = free_indices(nil);
		first_index = -1;
		last_index = -1;
		count = 0;
	}

	function list.metamethods.__cast(from, to, exp)
		if to == list and from == niltype then
			return list.empty
		end
		assert(false, 'invalid cast from ', from, ' to ', to, ': ', exp)
	end

	--assert that the link is valid, i.e. is within range and has not been deleted
	local assert_valid = macro(function(self, i, e)
		return quote
			assert(e.next_index ~= -1 or e.prev_index ~= -1 or i == self.first_index)
			in e
		end
	end)

	list.methods.index = overload'index'
	list.methods.index:adddefinition(terra(self: &list, i: size_t)
		assert_valid(self, i, self.links:at(i))
		return i
	end)
	list.methods.index:adddefinition(terra(self: &list, e: &T)
		var i = self.links:index([&link](e))
		assert_valid(self, i, [&link](e))
		return i
	end)

	list.methods.at = macro(function(self, i)
		return `[&T](assert_valid(self, i, self.links:at(i)))
	end)

	list.methods.get_first = macro(function(self)
		return `iif(self.first_index ~= -1, [&T](self.links:at(self.first_index)), nil)
	end)
	list.methods.get_last = macro(function(self)
		return `iif(self.last_index ~= -1, [&T](self.links:at(self.last_index)), nil)
	end)

	list.methods.next_index = macro(function(self, x)
		return `self.links.elements[self:index(x)].next_index
	end)
	list.methods.prev_index = macro(function(self, x)
		return `self.links.elements[self:index(x)].prev_index
	end)

	list.methods.next = macro(function(self, x)
		return quote
			var n = self:next_index(x)
			in iif(n ~= -1, [&T](self.links:at(n)), nil)
		end
	end)
	list.methods.prev = macro(function(self, x)
		return quote
			var n = self:prev_index(x)
			in iif(n ~= -1, [&T](self.links:at(n)), nil)
		end
	end)

	list.metamethods.__for = function(self, body)
		return quote
			var i = self.first_index
			while i ~= -1 do
				var e = self.links:at(i)
				var n = e.next_index --allow self:remove(e) in body
				[ body(i, `[&T](e)) ]
				i = n
			end
		end
	end

	local struct backwards {list: &list}
	backwards.metamethods.__for = function(self, body)
		return quote
			var i = self.list.last_index
			while i ~= -1 do
				var e = self.list.links:at(i)
				var p = e.prev_index --allow self:remove(e) in body
				[ body(i, `[&T](e)) ]
				i = p
			end
		end
	end
	terra list:backwards() return backwards{list = self} end

	terra list:init()
		@self = [list.empty]
	end

	terra list:clear()
		self.links.len = 0
		self.free_indices.len = 0
		self.first_index = -1
		self.last_index = -1
		self.count = 0
	end

	terra list:free()
		self:clear()
		self.links:free()
		self.free_indices:free()
	end

	terra list:set_min_capacity(size: size_t)
		self.links.min_capacity = size
		self.free_indices.min_capacity = size
	end

	terra list:__memsize()
		return sizeof(list)
			- sizeof(links) + memsize(self.links)
			- sizeof(free_indices) + memsize(self.free_indices)
	end

	terra list:_newlink()
		self.count = self.count + 1
		if self.free_indices.len > 0 then
			return self.free_indices:pop()
		else
			self.links:add()
			return self.links.len-1
		end
	end

	terra	list:_freelink(i: size_t)
		self.count = self.count - 1
		self.free_indices:push(i)
		return i
	end

	terra list:_link_between(
		p: size_t, pe: &link,
		n: size_t, ne: &link,
		i: size_t, ce: &link
	)
		if pe ~= nil then pe.next_index = i else self.first_index = i end
		ce.prev_index = p
		ce.next_index = n
		if ne ~= nil then ne.prev_index = i else self.last_index = i end
	end

	terra list:_link_after(p: size_t, pe: &link, i: size_t, ce: &link)
		var n  = iif(p ~= -1, pe.next_index, -1)
		var ne = iif(n ~= -1, self.links:at(n), nil)
		self:_link_between(p, pe, n, ne, i, ce)
	end

	terra list:_link_before(n: size_t, ne: &link, i: size_t, ce: &link)
		var p  = iif(n ~= -1, ne.prev_index, -1)
		var pe = iif(p ~= -1, self.links:at(p), nil)
		self:_link_between(p, pe, n, ne, i, ce)
	end

	terra list:_unlink(i: size_t, e: &link)
		var p = e.prev_index
		var n = e.next_index
		if p ~= -1 then self.links:at(p).next_index = n else self.first_index = n end
		if n ~= -1 then self.links:at(n).prev_index = p else self.last_index  = p end
		e.next_index = -1
		e.prev_index = -1
	end

	list.methods.insert_after = overload'insert_after'
	list.methods.insert_after:adddefinition(terra(self: &list, p: size_t)
		if p == -1 then
			--allow self:insert_after(self.last_index) even when empty
			assert(self.last_index == -1)
		end
		var pe = iif(p ~= -1, assert_valid(self, p, self.links:at(p)), nil)
		var i = self:_newlink()
		var e = self.links:at(i)
		self:_link_after(p, pe, i, e)
		return &e.item
	end)
	list.methods.insert_after:adddefinition(terra(self: &list, pe: &T)
		return self:insert_after(iif(pe ~= nil, self.links:index([&link](pe)), -1))
	end)
	list.methods.insert_after:adddefinition(terra(self: &list, p: size_t, v: T)
		var e = self:insert_after(p); @e = v; return e
	end)
	list.methods.insert_after:adddefinition(terra(self: &list, pe: &T, v: T)
		var e = self:insert_after(pe); @e = v; return e
	end)

	list.methods.insert_before = overload'insert_before'
	list.methods.insert_before:adddefinition(terra(self: &list, n: size_t)
		if n == -1 then
			--allow self:insert_before(self.first_index) even when empty
			assert(self.first_index == -1)
		end
		var ne = iif(n ~= -1, assert_valid(self, n, self.links:at(n)), nil)
		var i = self:_newlink()
		var e = self.links:at(i)
		self:_link_before(n, ne, i, e)
		return &e.item
	end)
	list.methods.insert_before:adddefinition(terra(self: &list, pe: &T)
		return self:insert_before(iif(pe ~= nil, self.links:index([&link](pe)), -1))
	end)
	list.methods.insert_before:adddefinition(terra(self: &list, p: size_t, v: T)
		var e = self:insert_before(p); @e = v; return e
	end)
	list.methods.insert_before:adddefinition(terra(self: &list, pe: &T, v: T)
		var e = self:insert_before(pe); @e = v; return e
	end)

	list.methods.insert_first = overload('insert_first', {
		terra(self: &list) return self:insert_before(self.first_index) end,
		terra(self: &list, v: T) return self:insert_before(self.first_index, v) end,
	})
	list.methods.insert_last = overload('insert_last', {
		terra(self: &list) return self:insert_after(self.last_index) end,
		terra(self: &list, v: T) return self:insert_after(self.last_index, v) end,
	})

	list.methods.remove = overload'remove'
	list.methods.remove:adddefinition(terra(self: &list, i: size_t)
		var e = assert_valid(self, i, self.links:at(i))
		self:_unlink(i, e)
		self:_freelink(i)
	end)
	list.methods.remove:adddefinition(terra(self: &list, e: &T)
		self:remove(self.links:index([&link](e)))
	end)

	terra list:set_first_index(i: size_t)
		var e = assert_valid(self, i, self.links:at(i))
		var p = self.first_index
		if i == p then return end
		var pe = self.links:at(p)
		self:_link_before(p, pe, i, e)
		self:_unlink(p, pe)
	end

	terra list:set_last_index(i: size_t)
		var e = assert_valid(self, i, self.links:at(i))
		var n = self.last_index
		if i == n then return end
		var ne = self.links:at(n)
		self:_link_after(n, ne, i, e)
		self:_unlink(n, ne)
	end

	terra list:set_first(e: &T)
		self:set_first_index(self.links:index([&link](e)))
	end
	terra list:set_last(e: &T)
		self:set_last_index(self.links:index([&link](e)))
	end

	setinlined(list.methods)

	return list
end
list_type = terralib.memoize(list_type)

local list_type = function(T, size_t)
	if type(T) == 'table' then
		T, size_t = T.T, T.size_t
	end
	assert(T)
	return list_type(T, size_t or int)
end

return macro(function(T, size_t)
	local list = list_type(T, size_t)
	return `list(nil)
end, list_type)
