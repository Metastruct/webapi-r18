local lapis = require "lapis"
local app = lapis.Application()

package.path = 'scripts/lsapi/?.lua;' .. 'scripts/?.lua;' .. package.path

require'config'
local utils = require'utils'

local db = require 'lsapidb'

local app_helpers = require("lapis.application")
local capture_errors_json, yield_error = app_helpers.capture_errors_json, app_helpers.yield_error
local capture_errors, assert_error = app_helpers.capture_errors, app_helpers.assert_error
local root = "/home/srcds/fastdl/"
app:get("/lsapi/i/:id", capture_errors_json(function(self)
	utils.cachecontrol()
	
	
	local id = self.params.id
	id = id:match("^(%d+)%.jpg$")
	assert_error(tonumber(id),"invalid id")
	
	local loadingscreen, err = db.loadingscreens:find(id)
	if not loadingscreen and err then yield_error(err) end
	if not loadingscreen then yield_error("No such id") end
	
	local url = loadingscreen.url
	if not url:find"^http" then url="http://"..url end
	
	local io = require("io")
	local http = require("lapis.nginx.http")
	local ltn12 = require("ltn12")
	
	local img_in =  (root.."lsapi/images/%d.jpg"):format(tonumber(id))
	local img_out = (root.."lsapi/cache/%d.jpg"):format(tonumber(id))
	
	local fd = io.open(img_in,'wb')
	local ret = table.tostring{http.request{ 
		url = url,
		sink = ltn12.sink.file(fd)
	}}
	assert_error(ret,"download from origin failed")
	
	local magick = require("magick") 
	magick.thumb(img_in, "480x270", img_out)
	
	ngx.exec(ngx.var.request_uri)
	assert(false)
end))

	
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
	utils.cachecontrol(20)
	
	if next(self.params) then
		local url = "/lsapi"
		ngx.redirect(url, ngx.HTTP_MOVED_TEMPORARILY)
		return
	end

	local t = assert_error(db.all())

	return {
		json = {
			success = true,
			result = t
		}
	}
end))

local accountid


app:get("/lsapi/auth", capture_errors(function(self) 
	utils.cachecontrol()
	
	local steamid,admin,ingame = utils.account_need(true)
	
	return {
		json = {
			success = true,
			steamid = steamid,
			admin = admin,
			ingame = ingame and true or false,
			csrf_token = csrf.generate_token(self, {
				expires = os.time() + 60*60*4
			})
		}
	}
end))


app:get("/lsapi/login", capture_errors(function(self) 
	utils.cachecontrol()
	
	utils.account_need()
	
	local url = "https://loadingscreen.metastruct.net#authed"
	ngx.redirect(url, ngx.HTTP_MOVED_TEMPORARILY)
	error"no"
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
	
	csrf.assert_token(self, function(data)
		if os.time() > (data.expires or 0) then
		return nil, "token is expired"
		end

		return true
	end)

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
	
	csrf.assert_token(self, function(data)
		if os.time() > (data.expires or 0) then
		return nil, "token is expired"
		end

		return true
	end)

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