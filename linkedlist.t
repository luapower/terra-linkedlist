
--Doubly-linked list for Terra.
--Written by Cosmin Apreutesei. Public domain.

--Implemented using a dynarray and a freelist, which means that the location
--of the elements in memory is not stable but their indices are.

--[[  API

	local D = linkedlist{item_t=, size_t=int, C=require'low'}
	var d: D = nil -- =nil is imortant!
	d:free()
	d:clear()
	d:preallocate(size) -> ok?
	d:shrink()
	d.count

	d:at(i) -> &v|nil
	d[:get](i[,default]) -> v
	d:set(i,v) -> i|-1
	for i,&v in d do ... end

	d:insert_first([v]) -> i|-1
	d:insert_last([v]) -> i|-1
	d:insert_before(i[,v]) -> i|-1
	d:insert_after(i[,v]) -> i|-1
	d:remove(i) -> i|-1
	d:remove_last() -> i|-1
	d:remove_first() -> i|-1
	d:make_first(i) -> i|-1

	d.first_index -> i|-1
	d.last_index -> i|-1
	d:next_index(i) -> i|-1
	d:prev_index(i) -> i|-1

]]

if not ... then require'linkedlist_test'; return end

local overload = terralib.overloadedfunction

local function list_type(T, size_t, C)

	setfenv(1, C)

	local struct link {
		next: size_t;
		prev: size_t;
		item: T; --TODO: make item optional
	};

	local links = arr{T = link, size_t = size_t, C = C}
	local freelinks = arr{T = size_t, size_t = size_t, C = C}

	local struct list {
		links: links;
		freelinks: freelinks;
		first_index: size_t;
		last_index: size_t;
		count: size_t;
	}

	--memory management

	function list.metamethods.__cast(from, to, exp)
		if from == niltype or from:isunit() then
			return `list {
				links=nil,
				freelinks=nil,
				first_index=-1,
				last_index=-1,
				count=0,
			}
		else
			error'invalid cast'
		end
	end

	terra list:free() --can be reused after free
		self.links:free()
		self.freelinks:free()
		self.first_index = -1
		self.last_index = -1
		self.count = 0
	end

	terra list:clear()
		self.links:clear()
		self.freelinks:clear()
		self.first_index = -1
		self.last_index = -1
		self.count = 0
	end

	terra list:preallocate(size: size_t)
		return self.links:preallocate(size)
			and self.freelinks:preallocate(size)
	end

	--NOTE: shrinking invalidates the indices!
	terra list:shrink(): bool
		assert(false, 'NYI')
		if self.freelinks.len == 0 then return true end
		--TODO: move links over to the empty slots to close the gaps.
		self.links.len = self.count
		self.freelinks:free()
		return self.links:shrink()
	end

	terra list:__memsize(): size_t
		return sizeof(list) + self.links:__memsize() + self.freelinks:__memsize()
	end

	--value access

	list.methods.at = macro(function(self, i)
		return quote
			var link = self.links:at(i)
			in iif(link ~= nil, &link.item, nil)
		end
	end)
	list.methods.get = macro(function(self, i, default)
		if default then
			return quote
				var item = self:at(i)
				in iif(item ~= nil, item, default)
			end
		else
			return quote
				var item = self:at(i)
				return item
			end
		end
	end)
	list.metamethods.__apply = list.methods.get

	terra list:set(i: size_t, v: T)
		var p = self:at(i)
		if p == nil then return -1 end
		@p = v
		return i
	end

	--navigation & traversal

	list.methods.next_index = macro(function(self, i) return `self.links(i).next end)
	list.methods.prev_index = macro(function(self, i) return `self.links(i).prev end)

	list.metamethods.__for = function(self, body)
		return quote
			var i = self.first_index
			while i ~= -1 do
				[ body(`self:at(i)) ]
				i = self:next_index(i)
			end
		end
	end

	--mutation

	local terra grab_link(self: &list): size_t
		if self.freelinks.len > 0 then
			return self.freelinks:pop()
		else
			return iif(self.links:push() ~= nil, self.links.len-1, -1)
		end
	end

	local terra link_first(self: &list, link: &link, link_index: size_t)
		if self.first_index == -1 then
			self.first_index = link_index
			self.last_index = link_index
			link.next = -1
			link.prev = -1
		else
			link.next = self.first_index
			link.prev = -1
			self.links:at(self.first_index).prev = link_index
			self.first_index = link_index
		end
	end

	list.methods.insert_first = overload('insert_first', {})
	list.methods.insert_first:adddefinition(terra(self: &list): size_t
		var link_index = grab_link(self)
		if link_index == -1 then return -1 end
		var link = self.links:at(link_index)
		link_first(self, link, link_index)
		self.count = self.count + 1
		return link_index
	end)
	list.methods.insert_first:adddefinition(terra(self: &list, v: T): size_t
		var i = self:insert_first()
		if i ~= -1 then @self:at(i) = v end
		return i
	end)

	list.methods.insert_after = overload('insert_after', {})
	list.methods.insert_after:adddefinition(terra(self: &list, anchor_index: size_t): size_t
		var link_index = grab_link(self)
		if link_index == -1 then return -1 end
		var anchor = self.links:at(anchor_index)
		var link   = self.links:at(link_index)
		if anchor.next ~= -1 then
			self.links:at(anchor.next).prev = link_index
		else
			self.last_index = link_index
		end
		link.next = anchor.next
		link.prev = anchor_index
		anchor.next = link_index
		self.count = self.count + 1
		return link_index
	end)
	list.methods.insert_after:adddefinition(terra(self: &list, anchor_index: size_t, v: T): size_t
		var i = self:insert_after(anchor_index)
		if i ~= -1 then @self:at(i) = v end
		return i
	end)

	list.methods.insert_last = overload('insert_last', {})
	list.methods.insert_last:adddefinition(terra(self: &list)
		if self.last_index ~= -1 then
			return self:insert_after(self.last_index)
		else
			return self:insert_first()
		end
	end)
	list.methods.insert_last:adddefinition(terra(self: &list, v: T)
		if self.last_index ~= -1 then
			return self:insert_after(self.last_index, v)
		else
			return self:insert_first(v)
		end
	end)

	list.methods.insert_before = overload('insert_before', {})
	list.methods.insert_before:adddefinition(terra(self: &list, anchor_index: size_t, v: T)
		anchor_index = self.links(anchor_index).prev
		if anchor_index ~= -1 then
			return self:insert_after(anchor_index, v)
		else
			return self:insert_first(v)
		end
	end)

	local terra unlink(self: &list, link: &link, link_index: size_t)
		if link.next ~= -1 then
			if link.prev ~= -1 then --in the middle
				self.links:at(link.next).prev = link.prev
				self.links:at(link.prev).next = link.next
			else --the first
				assert(link_index == self.first_index)
				self.links:at(link.next).prev = -1
				self.first_index = link.next
			end
		elseif link.prev ~= -1 then --the last
			assert(link_index == self.last_index)
			self.links:at(link.prev).next = -1
			self.last_index = link.prev
		else --the only
			assert(link_index == self.first_index and link_index == self.last_index)
			self.first_index = -1
			self.last_index = -1
		end
	end

	terra list:remove(link_index: size_t)
		if link_index == -1 then return -1 end
		var link = self.links:at(link_index)
		unlink(self, link, link_index)
		self.freelinks:push(link_index)
		self.count = self.count - 1
		return link_index
	end

	terra list:remove_last()
		return self:remove(self.last_index)
	end

	terra list:remove_first()
		return self:remove(self.first_index)
	end

	terra list:make_first(link_index: size_t)
		if link_index == self.first_index then return end
		var link = self.links:at(link_index)
		unlink(self, link, link_index)
		link_first(self, link, link_index)
	end

	return list
end
list_type = terralib.memoize(list_type)

local list_type = function(T, size_t, C)
	if terralib.type(T) == 'table' then
		T, size_t, C = T.T, T.size_t, T.C
	end
	assert(T)
	return list_type(T, size_t or int, C or require'low')
end

return list_type
