local lapis = require("lapis")

local app = lapis.Application()
require'config'
local Model = require("lapis.db.model").Model
local db = require("lapis.db")

local loadingscreens = Model:extend("loadingscreen", {
  primary_key = { "id" }
})
local votes = Model:extend("loadingscreen_votes", {
  primary_key = { "accountid", "id" }
})
local _M={
	loadingscreens=loadingscreens,
	votes = votes
}

function _M.all()
	return loadingscreens:select({ 
		fields = [[extract(epoch from created)::numeric::integer as created, 
					id, confsort, accountid, up, approver, url, approval, down]] 
	})
end

function _M.loadingscreen_new(accountid,url)
	local loadingscreen = _M.loadingscreens:find{ url = url }
	if loadingscreen then
		return loadingscreen,true
	end

	return _M.loadingscreens:create{
		url = url,
		accountid = accountid
	}
	
end

function _M.loadingscreen_update_summary(id)
	return db.query([[UPDATE loadingscreen 
	SET 
		up   = (SELECT count(*) FROM loadingscreen_votes WHERE id = ? and vote=true),
		down = (SELECT count(*) FROM loadingscreen_votes WHERE id = ? AND vote=false)
	WHERE id = ?]],id,id,id)
end

_M.transaction = function(cb,...)
	assert(db.query"begin")
	local ok,err = pcall(cb,...)
	assert(db.query"commit")
	if not ok then error(err) end
	return err
end
return _M