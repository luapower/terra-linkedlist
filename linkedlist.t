
--Doubly-linked list type for Terra.
--Written by Cosmin Apreutesei. Public domain.
--Implemented using a dynarray and a freelist.

if not ... then require'linkedlist_test'; return end

local arr = require'dynarray'

local function list_type(T, C)

	setfenv(1, C)

	local struct link {
		next: &link;
		prev: &link;
		item: T;
	};

	local links = arr{T = link, C = C}
	local freelinks = arr{T = &link, C = C}

	local struct list {
		links: links;
		freelinks: freelinks;
		count: int;
		first: &link;
		last: &link;
	}

	function list.metamethods.__cast(from, to, exp)
		if from == niltype or from:isunit() then
			return `list {links=nil, freelinks=nil, first=nil, last=nil}
		else
			error'invalid cast'
		end
	end

	terra list:clear()
		self.links:clear()
		self.freelinks:clear()
		self.first = nil
		self.last = nil
	end

	local terra grab_link(self: &list): &link
		if self.freelinks.len > 0 then
			return self.freelinks:pop()
		else
			return self.links:push()
		end
	end

	terra list:insert_first(v: T): &link
		var link = grab_link(self)
		if link == nil then return nil end
		if self.first == nil then
			self.first = link
			self.last = link
			link.next = nil
			link.prev = nil
		else
			link.next = self.first
			link.prev = nil
			self.first.prev = link
			self.first = link
		end
		link.item = v
		self.count = self.count + 1
		return link
	end

	terra list:insert_after(anchor: &link, v: T): &link
		assert(anchor ~= nil)
		var link = grab_link(self)
		if link == nil then return nil end
		if anchor.next ~= nil then
			anchor.next.prev = link
			link.next = anchor.next
		else
			self.last = link
		end
		link.prev = anchor
		anchor.next = link
		link.item = v
		self.count = self.count + 1
		return link
	end

	terra list:insert_last(v: T)
		if self.last ~= nil then
			return self:insert_after(self.last, v)
		else
			return self:insert_first(v)
		end
	end

	terra list:insert_before(anchor: &link, v: T)
		assert(anchor ~= nil)
		anchor = anchor.prev
		if anchor ~= nil then
			return self:insert_after(anchor, v)
		else
			return self:insert_first(v)
		end

	end

	terra list:remove(link: &link)
		if link.next ~= nil then
			if link.prev ~= nil then
				link.next.prev = link.prev
				link.prev.next = link.next
			else
				assert(link == self.first)
				link.next.prev = nil
				self.first = link.next
			end
		elseif link.prev ~= nil then
			assert(link == self.last)
			link.prev.next = nil
			self.last = link.prev
		else
			assert(link == self.first and link == self.last)
			self.first = nil
			self.last = nil
		end
		self.freelinks:push(link)
		self.count = self.count - 1
	end

	terra list:remove_last()
		if self.last == nil then return end
		self:remove(self.last)
	end

	terra list:remove_first()
		if self.first == nil then return end
		self:remove(self.first)
	end

	list.metamethods.__for = function(self, body)
		return quote
			var link = self.first
			while link ~= nil do
				[ body(`link.item) ]
				link = link.next
			end
		end
	end

	terra list:copy()

	end

	return list
end
list_type = terralib.memoize(list_type)

local list_type = function(T, C)
	return list_type(T, C or require'low')
end

return list_type
