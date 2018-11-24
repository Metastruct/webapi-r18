local lapis = require "lapis"
local app = lapis.Application()

package.path = 'scripts/lsapi/?.lua;' .. 'scripts/?.lua;' .. package.path

require'config'
local utils = require'utils'

local db = require 'lsapidb'

local app_helpers = require("lapis.application")
local capture_errors_json, yield_error = app_helpers.capture_errors_json, app_helpers.yield_error
local capture_errors, assert_error = app_helpers.capture_errors, app_helpers.assert_error

	
app:get("/lsapi/thumb/:id", capture_errors_json(function(self)
	utils.cachecontrol()
	
	local id = self.params.id
	local loadingscreen, err = db.loadingscreens:find(id)
	if not loadingscreen and err then yield_error(err) end
	if not loadingscreen then yield_error("No such id") end
	local url = loadingscreen.url
	if not url:find"^http" then url="http://"..url end
	
	local io = require("io")
	local http = require("lapis.nginx.http")
	local ltn12 = require("ltn12")

	local fd = io.open("/tmp/wot.png",'wb')
	local ret = table.tostring{http.request{ 
		url = "https://i.imgur.com/rKaqpdO.png", 
		sink = ltn12.sink.file(fd)
	}}
	
	return url
	
end))

app:get("/lsapi", capture_errors_json(function(self)
	utils.cachecontrol(10)
	
	local t = assert_error(db.all())

	return {
		json = {
			success = true,
			result = t
		}
	}
end))

local accountid



--app:get("/lsapi/secure", capture_errors(function(self) 
--	local steamid,admin,ingame = utils.account_need(true)
--	return ("steamid: "..tostring(steamid)..' admin: '..tostring(admin))
--end))
--

app:get("/lsapi/auth", capture_errors(function(self) 
	utils.cachecontrol()
	
	local steamid,admin,ingame = utils.account_need()
	return {
		json = {
			success = true,
			steamid = steamid,
			admin = admin,
			ingame = ingame and true or false
		}
	}
end))

app:post("/lsapi", capture_errors_json(function(self)
	utils.cachecontrol()
	
	local accountid,admin = utils.account_need(true)
	
	local url = self.params.url
	
	local loadingscreen,already = assert_error(db.loadingscreen_new(accountid,url))
	if loadingscreen and already then
		return {
			status = 409, -- conflict
			json = {
				success = false,
				already = true,
				id 		= loadingscreen.id
			}
		}		
	end
	
	return {
		status = 201, -- created
		json = {
			success = true,
			id = loadingscreen.id
		}
	}
end))

local function set_approved(approve,self)
	utils.cachecontrol()
	
	local accountid = utils.account_need_admin(true)
	
	local loadingscreen = assert_error(db.loadingscreens:find(self.params.id))
	assert_error(loadingscreen:update{approval=approve,approver=accountid})
	return {
		status = 200,
		json = {
			success = true,
		}
	}
end

app:post("/lsapi/approve/:id", capture_errors_json(function(...) return set_approved(true,...) end))
app:post("/lsapi/deny/:id",    capture_errors_json(function(...) return set_approved(false,...) end))


app:post("/lsapi/vote/:id/:dir", capture_errors_json(function(self)
	utils.cachecontrol()
	
	local accountid = utils.account_need(true)
	
	local id = assert_error(tonumber(self.params.id), "invalid id")
	
	-- :dir
	local dir = self.params.dir
	assert_error(dir == 'up' or dir == 'down' or dir == 'delete', "bad vote direction")
	dir = dir == 'delete' and 'delete' or dir == 'up' and true or false
	
	-- does loadingscreen id exist
	local loadingscreen, err = db.loadingscreens:find(id)
	if not loadingscreen and err then yield_error(err) end
	if not loadingscreen then yield_error("No such id") end

	-- find existing votes
	local vote, err = db.votes:find(accountid, id)
	if not vote and err then yield_error(err) end

	if dir == 'delete' then
		assert_error(vote, "no vote to delete")
		vote:delete()
	else
		if vote then
			vote:update({ vote = dir })
		else
			db.votes:create{	accountid = accountid,
								id = id,
								vote = dir	}
		end
	end

	db.loadingscreen_update_summary(id)

	return {
		json = {
			success = true
		}
	}
end))



return app