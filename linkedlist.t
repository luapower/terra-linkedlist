--[[

	Self-allocated doubly-linked list for Terra.
	Written by Cosmin Apreutesei. Public domain.

	Implemented using a dynarray and a freelist, which means that the location
	of the links in memory is not stable between inserts unless the list is
	preallocated and doesn't grow. Indices are stable though and can be used
	to retrieve the same link after any number of mutations.

	local list_type = list(T,[size_t=int])      create a list type
	var list = list_type(nil)                   create a list object
	var list = list(T,[size_t])                 create a list object

	list:init()                                 initialize (for struct members)
	list:clear()                                remove items, keep the memory
	list:free()                                 free (items are not freed!)
	list:setcapacity(size) -> ok?               set capacity with error checking
	list.capacity                               (write/only) set capacity
	list.min_capacity                           (write/only) grow capacity

	list:link(i) -> &e                          link at index
	e.item -> &t                                link's payload (element)
	e.next -> i                                 (read/only) next link's index
	e.prev -> i                                 (read/only) prev link's index

	list.first -> i                             (read/write) index of first link
	list.last -> i                              (read/write) index of last link

	for i,&e in list do ... end                 iterate links (remove() works inside)
	for i,&e in list:backwards() do ... end     iterate backwards (remove() works inside)

	list:insert_before(i[,v]) -> i              insert v before i
	list:insert_after(i[,v]) -> i               insert v after i
	list:remove(i)                              remove link

	list:move_before(di,i)                      move link at i before link at di
	list:move_after(di,i)                       move link at i after link at di

]]

if not ... then require'linkedlist_test'; return end

setfenv(1, require'low')

local function list_type(T, size_t)

	local struct link {
		item: T; --must be the first field!
		next: size_t;
		prev: size_t;
	}

	local links_arr   = arr{T = link, size_t = size_t}
	local indices_arr = arr{T = size_t, size_t = size_t}

	local struct list (gettersandsetters) {
		links        : links_arr;
		free_indices : indices_arr;
		first        : size_t;
		last         : size_t;
		count        : size_t;
	}

	list.T = T
	list.size_t = size_t
	list.link = link

	list.empty = `list {
		links        = links_arr(nil);
		free_indices = indices_arr(nil);
		first        = -1;
		last         = -1;
		count        =  0;
	}

	function list.metamethods.__cast(from, to, exp)
		if to == list and from == niltype then
			return list.empty
		end
		assert(false, 'invalid cast from ', from, ' to ', to, ': ', exp)
	end

	terra list:link(i: size_t)
		var e = self.links:at(i)
		--assert that the link is valid, i.e. is in range and is not deleted.
		assert(e.next ~= -1 or e.prev ~= -1 or i == self.first)
		return e
	end

	terra list:anchorlink(i: size_t)
		var e: &link
		if i == -1 then
			assert(self.last == -1)
			return nil
		else
			return self:link(i)
		end
	end

	list.metamethods.__for = function(self, body)
		return quote
			var i = self.first
			while i ~= -1 do
				var e = self.links:at(i)
				var n = e.next --allow self:remove(e) in body
				[ body(i, e) ]
				i = n
			end
		end
	end

	local struct backwards {list: &list}
	backwards.metamethods.__for = function(self, body)
		return quote
			var i = self.list.last
			while i ~= -1 do
				var e = self.list.links:at(i)
				var p = e.prev --allow self:remove(e) in body
				[ body(i, e) ]
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
		self.first = -1
		self.last = -1
		self.count = 0
	end

	terra list:free()
		self:clear()
		self.links:free()
		self.free_indices:free()
	end

	terra list:setcapacity(size: size_t)
		return self.links:setcapacity(size)
			and self.free_indices:setcapacity(size)
	end

	terra list:set_capacity(size: size_t)
		self.links.capacity = size
		self.free_indices.capacity = size
	end

	terra list:set_min_capacity(size: size_t)
		self.links.min_capacity = size
		self.free_indices.min_capacity = size
	end

	terra list:__memsize()
		return sizeof(@self)
			- sizeof(self.links) + memsize(self.links)
			- sizeof(self.free_indices) + memsize(self.free_indices)
	end

	terra list:_newlink()
		self.count = self.count + 1
		if self.free_indices.len > 0 then
			var i = self.free_indices(self.free_indices.len-1)
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
		if pe ~= nil then pe.next = i else self.first = i end
		ce.prev = p
		ce.next = n
		if ne ~= nil then ne.prev = i else self.last = i end
	end

	terra list:_link_after(p: size_t, pe: &link, i: size_t, ce: &link)
		var n  = iif(p ~= -1, pe.next, -1)
		var ne = iif(n ~= -1, self.links:at(n), nil)
		self:_link_between(p, pe, n, ne, i, ce)
	end

	terra list:_link_before(n: size_t, ne: &link, i: size_t, ce: &link)
		var p  = iif(n ~= -1, ne.prev, -1)
		var pe = iif(p ~= -1, self.links:at(p), nil)
		self:_link_between(p, pe, n, ne, i, ce)
	end

	terra list:_unlink(i: size_t, e: &link)
		var p = e.prev
		var n = e.next
		if p ~= -1 then self.links:at(p).next = n else self.first = n end
		if n ~= -1 then self.links:at(n).prev = p else self.last  = p end
		e.next = -1
		e.prev = -1
	end

	list.methods.insert_after = overload'insert_after'
	list.methods.insert_after:adddefinition(terra(self: &list, p: size_t)
		var i = self:_newlink()
		--NOTE: must get these pointers _after_ the link was created.
		var e = self.links:at(i)
		var pe = self:anchorlink(p)
		self:_link_after(p, pe, i, e)
		return i, e
	end)
	list.methods.insert_after:adddefinition(terra(self: &list, p: size_t, v: T)
		var i, e = self:insert_after(p)
		e.item = v
		return i, e
	end)

	list.methods.insert_before = overload'insert_before'
	list.methods.insert_before:adddefinition(terra(self: &list, n: size_t)
		var i = self:_newlink() --this can grow and thus invalidate the list!
		--NOTE: must get these pointers _after_ the link was created.
		var e = self.links:at(i)
		var ne = self:anchorlink(n)
		self:_link_before(n, ne, i, e)
		return i, e
	end)
	list.methods.insert_before:adddefinition(terra(self: &list, p: size_t, v: T)
		var i, e = self:insert_before(p)
		e.item = v
		return i, e
	end)

	terra list:remove(i: size_t)
		var e = self:link(i)
		self:_unlink(i, e)
		self:_freelink(i)
	end

	terra list:move_before(n: size_t, i: size_t)
		if i == n then return end
		var e = self:link(i)
		var ne = self:anchorlink(n)
		self:_unlink(i, e)
		self:_link_before(n, ne, i, e)
	end

	terra list:move_after(p: size_t, i: size_t)
		if i == p then return end
		var e = self:link(i)
		var pe = self:anchorlink(p)
		self:_unlink(i, e)
		self:_link_after(p, pe, i, e)
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
