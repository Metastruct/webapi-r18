local lapis = require("lapis")

local app = lapis.Application()
require'config'
local Model = require("lapis.db.model").Model
local db = require("lapis.db")

local r18 = Model:extend("r18", {
  primary_key = { "accountid" }
})
local _M={
	r18=r18
}

function _M.getby(accountid)
	local res = r18:select("where verifier1 = ? or verifier2 = ? limit 1000", accountid,accountid, { fields = 'accountid' })
	return res
end
function _M.get(accountid)
	local res = r18:find(accountid)
	return res
end

function _M.delete(accountid,children)
	assert(not children,"WIP")
	local res = r18:find(accountid)
	return res:delete()
end

function _M.set(accountid,v1,v2)

	local usr = _M.get(accountid)
	if usr then
		local t={}
		if v1~=nil then
			if not v1 then v1=nil end
			usr.verifier1 = v1
			t[#t+1]="verifier1"
		end
		if v2~=nil then
			if not v2 then v2=nil end
			usr.verifier2 = v2
			t[#t+1]="verifier2"
		end
		return usr:update(unpack(t))
	end
	
	return _M.r18:create{
		accountid = accountid,
		verifier1 = v1,
		verifier2 = v2
	}
	
end

_M.transaction = function(cb,...)
	assert(db.query"begin")
	local ok,err = pcall(cb,...)
	assert(db.query"commit")
	if not ok then error(err) end
	return err
end

return _M