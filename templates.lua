local mustache = require'mustache'

local t={}
local _M

local function get(name)
	local f = assert(io.open("scripts/r18/templates/"..name..'.html','rb'))
	if f then
		local template = f:read("*all")
		f:close()
		template = mustache.compile(template)
		return template
	end
end

_M=setmetatable({},{__index=function(self,k)
	local cached = t[k]
	if cached~=nil then assert(cached) return cached end
	
	local template = get(k)
	if template then
		
		local function renderer(ctx_stack, getpartial, write, d1, d2, escape)
			local getpartial_ = getpartial
			getpartial = function(name)
				if getpartial_ then
					local ret = getpartial_(name) 
					if ret then return ret end
				end
				return get(name)
			end
			return {
				layout = false,
				mustache.render(template, ctx_stack, getpartial, write, d1, d2, escape)
			}
		end
		
		cached = renderer
		
	else
		cached=false
	end
	
	t[k]=cached
	
	return cached
	
end})


return _M