local mustache = require'mustache'

local t={}
local _M=setmetatable({},{__index=function(self,k)
	local cached = t[k]
	if cached~=nil then assert(cached) return cached end
	
	local f = assert(io.open("scripts/r18/templates/"..k..'.html','rb'))
	if f then
		local template = f:read("*all")
		f:close()
		template = mustache.compile(template)
		
		local function renderer(...)
			return {
				layout = false,
				mustache.render(template,...)
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