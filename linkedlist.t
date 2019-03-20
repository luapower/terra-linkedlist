--[[

	Self-allocated doubly-linked list for Terra.
	Written by Cosmin Apreutesei. Public domain.

	Implemented using a dynarray and a freelist, which means that the location
	of the elements in memory is not stable unless the list is preallocated
	and doesn't grow.

	local list_type = list(T, [size_t=int])     create a list type
	var list = list_type(nil)                   create a list object
	var list = list(T, [size_t])                create a list object

	list:init()                                 initialize (for struct members)
	list:clear()                                remove items, keep the memory
	list:free()                                 free (items are not freed!)
	list.min_capacity                           (write/only) grow capacity

	list.first -> &e                            first element
	list.last  -> &e                            last element

	list:next(&e) -> &e                         next element
	list:prev(&e) -> &e                         prev element

	for &e in list do ... end                   iterate elements
	for &e in list:backwards() do ... end       iterate backwards

	list:insert_first(&v)                       insert at the front
	list:insert_last(&v)                        insert at the back
	list:insert_after(&e, &v)                   insert v after e
	list:insert_before(&e, &v)                  insert v before e
	list:remove(&e)                             remove element
	list:make_first(&e)                         move element to front

]]

if not ... then require'linkedlist_test'; return end

setfenv(1, require'low')

local function list_type(T, size_t)

	local struct link {
		item: T; --must be the first field!
		_next: size_t;
		_prev: size_t;
	}

	local links = arr{T = link, size_t = size_t}
	local freelinks = arr{T = size_t, size_t = size_t}

	local struct list (gettersandsetters) {
		links: links;
		freelinks: freelinks;
		_first: size_t;
		_last: size_t;
		count: size_t;
	}

	list.empty = `list {
		links = links(nil);
		freelinks = freelinks(nil);
		_first = -1;
		_last = -1;
		count = 0;
	}

	function list.metamethods.__cast(from, to, exp)
		if to == list and from == niltype then
			return list.empty
		end
		assert(false, 'invalid cast from ', from, ' to ', to, ': ', exp)
	end

	list.methods.get_first = macro(function(self)
		return `iif(self._first ~= -1, &self.links:at(self._first).item, nil)
	end)
	list.methods.get_last  = macro(function(self)
		return `iif(self._last ~= -1, &self.links:at(self._last).item, nil)
	end)
	list.methods.next = macro(function(self, e)
		return `[&T](self.links:at([&link](e)._next, nil))
	end)
	list.methods.prev = macro(function(self, e)
		return `[&T](self.links:at([&link](e)._prev, nil))
	end)

	list.metamethods.__for = function(self, body)
		return quote
			var i = self._first
			while i ~= -1 do
				var link = self.links:at(i)
				[ body(`[&T](link)) ]
				i = link._next
			end
		end
	end

	local struct backwards {list: &list}
	backwards.metamethods.__for = function(self, body)
		return quote
			var i = self.list._last
			while i ~= -1 do
				var link = self.links:at(i)
				[ body(`[&T](link)) ]
				i = link._prev
			end
		end
	end
	terra list:backwards() return backwards{list = self} end

	terra list:init()
		@self = [list.empty]
	end

	terra list:clear()
		self.links.len = 0
		self.freelinks.len = 0
		self._first = -1
		self._last = -1
		self.count = 0
	end

	terra list:free()
		self:clear()
		self.links:free()
		self.freelinks:free()
	end

	terra list:set_min_capacity(size: size_t)
		self.links.min_capacity = size
		self.freelinks.min_capacity = size
	end

	terra list:__memsize()
		return sizeof(list)
			- sizeof(links) + memsize(self.links)
			- sizeof(freelinks) + memsize(self.freelinks)
	end

	terra list:_newlink()
		self.count = self.count + 1
		if self.freelinks.len > 0 then
			return self.freelinks:pop()
		else
			self.links:add()
			return self.links.len-1
		end
	end

	terra	list:_freelink(i: size_t)
		self.count = self.count - 1
		self.freelinks:push(i)
		return i
	end

	terra list:_link_after(pe: &link, i: size_t, e: &link)
		var p = iif(pe ~= nil, self.links:index(pe), self._last)
		if p == self._last then
			if self._last ~= -1 then
				self.links:at(self._last)._next = i
				e._prev = self._last
				e._next = -1
				self._last = i
			else
				self._first = i
				self._last = i
				e._next = -1
				e._prev = -1
			end
		else
			var n = pe._next
			if n ~= -1 then
				self.links:at(n)._prev = i
			end
			pe._next = i
			e._prev = p
			e._next = n
		end
	end

	terra list:_link_before(ne: &link, i: size_t, e: &link)
		var n = iif(ne ~= nil, self.links:index(ne), self._first)
		if n == self._first then
			if self._first ~= -1 then
				self.links:at(self._first)._prev = i
				e._next = self._first
				e._prev = -1
				self._first = i
			else
				self._first = i
				self._last = i
				e._next = -1
				e._prev = -1
			end
		else
			var p = self.links:index(ne._prev)
			var pe = self.links:at(p)
			self:_link_after(pe, i, e)
		end
	end

	terra list:_unlink(e: &link)
		if e == nil then return -1 end --so list:remove(list.first) always works
		if e._next == -1 and e._prev == -1 then return -1 end --already removed
		var i = self.links:index(e)
		var p = e._prev
		var n = e._next
		if p ~= -1 then self.links:at(p)._next = n else self._first = n end
		if n ~= -1 then self.links:at(n)._prev = p else self._last  = p end
		e._next = -1
		e._prev = -1
		return i
	end

	list.methods.insert_after = overload'insert_after'
	list.methods.insert_after:adddefinition(terra(self: &list, pe: &T)
		var i = self:_newlink()
		var e = self.links:at(i)
		self:_link_after([&link](pe), i, e)
		return &e.item
	end)
	list.methods.insert_after:adddefinition(terra(self: &list, pe: &T, v: T)
		var e = self:insert_after(pe); @e = v; return e
	end)

	list.methods.insert_before = overload'insert_before'
	list.methods.insert_before:adddefinition(terra(self: &list, ne: &T)
		var i = self:_newlink()
		var e = self.links:at(i)
		self:_link_before([&link](ne), i, e)
		return &e.item
	end)
	list.methods.insert_before:adddefinition(terra(self: &list, pe: &T, v: T)
		var e = self:insert_before(pe); @e = v; return e
	end)

	list.methods.insert_first = overload('insert_first', {
		terra(self: &list) return self:insert_before(nil) end,
		terra(self: &list, v: T) return self:insert_before(nil, v) end,
	})
	list.methods.insert_last = overload('insert_last', {
		terra(self: &list) return self:insert_after(nil) end,
		terra(self: &list, v: T) return self:insert_after(nil, v) end,
	})

	terra list:remove(e: &T)
		var i = self:_unlink([&link](e))
		if i ~= -1 then
			self:_freelink(i)
		end
	end

	terra list:make_first(e: &T)
		var e = [&link](e)
		var i = self:_unlink(e)
		if i ~= -1 then
			self:_link_before(nil, i, e)
		end
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
