local lapis = require "lapis"
local app = lapis.Application()

package.path = 'scripts/lsapi/?.lua;' .. 'scripts/?.lua;' .. package.path

require'config'
local utils = require'utils'

local db = require 'lsapidb'

local csrf = require("lapis.csrf")
local app_helpers = require("lapis.application")
local capture_errors_json, yield_error = app_helpers.capture_errors_json, app_helpers.yield_error
local capture_errors, assert_error = app_helpers.capture_errors, app_helpers.assert_error
local respond_to = require("lapis.application").respond_to
local root = "/home/srcds/fastdl/"

app:get("/lsapi/i/:id", capture_errors_json(function(self)
	utils.cachecontrol()

	
	local id = self.params.id
	id = id:match("^(%d+)%.jpg$")
	assert_error(tonumber(id),"invalid id")
	
	local img_in =  (root.."lsapi/images/%d.jpg"):format(tonumber(id))
	local img_out = (root.."lsapi/cache/%d.jpg"):format(tonumber(id))
	local fd = io.open(img_in,'rb')
	if fd then
		fd:close()
		ngx.redirect("/not-found-1770320_640.jpg", ngx.HTTP_MOVED_TEMPORARILY)
	end
	
	local loadingscreen, err = db.loadingscreens:find(id)
	if not loadingscreen and err then yield_error(err) end
	if not loadingscreen then yield_error("No such id") end
	
	local url = loadingscreen.url
	if not url:find"^http" then url="http://"..url end
	
	local io = require("io")
	local http = require("lapis.nginx.http")
	local ltn12 = require("ltn12")
	
	local fd = io.open(img_in,'wb')
	local ret = http.request{ 
		url = url,
		sink = ltn12.sink.file(fd)
	}
	assert_error(ret,"download from origin failed")
	
	local magick = require("magick") 
	magick.thumb(img_in, "480x270", img_out)
	
	ngx.exec(ngx.var.request_uri)
	assert(false)
end))

app:get("/lsapi/myaccount", capture_errors_json(function(self)
	utils.cachecontrol()

	local accountid,admin,ingame = utils.account_need(true)
	local sid64 = utils.aid_to_sid64(accountid)
	
	return {
		json = {
			success = true,
			result = utils.GetPlayerSummaries(sid64)
		}
	}
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

for _,meth in next,{"get","post"} do
	app[meth](app,"/lsapi/auth", capture_errors(function(self) 
		utils.cachecontrol()

		
		local accountid,admin,ingame = utils.account_need(true)
		local sid64 = utils.aid_to_sid64(accountid)
		assert(utils.sid64_to_accountid(sid64)==accountid)
		return {
			json = {
				success = true,
				steamid = sid64,
				accountid = accountid,
				admin = admin and true or false,
				ingame = ingame and true or false,
				csrf_token = csrf.generate_token(self, {
					expires = os.time() + 60*60*4
				})
			}
		}
	end))
end

app:get("/lsapi/testb64", capture_errors(function(self) 
	utils.cachecontrol()
	local bad = [[L9MoOXC\\\/Gb1osk1bb0eF3an4oyQ=]]
	ngx.say("org: "..bad)
	ngx.say("ngx: "..(ngx.encode_base64(ngx.decode_base64(bad) or "") or "<none>"))
	ngx.say("b64: "..require'mime'.b64(require'mime'.unb64(bad)))
	
end))

app:get("/lsapi/login", capture_errors(function(self) 
	utils.cachecontrol()
	utils.account_need()
	
	local url = "https://loadingscreen.metastruct.net#authed"
	ngx.redirect(url, ngx.HTTP_MOVED_TEMPORARILY)
	error"no"
end))

app:delete("/lsapi", capture_errors_json(function(self)
	utils.cachecontrol()
	--utils.do_csrf(self)

	local accountid = utils.account_need_admin(true)

	local loadingscreen = assert_error(db.loadingscreens:find(self.params.id))	
	return {
		status = 200,
		json = {
			success = true,
			res = loadingscreen:delete()
		}
	}
	
end))


app:post("/lsapi", capture_errors_json(function(self)
	utils.cachecontrol()
	--utils.do_csrf(self)

	local accountid,admin = utils.account_need(true)
		
	local last = db.last_created(accountid)
	if last and os.time()-last<60 then
		return {
			status = 429, -- rate limited
			json = {
				success = false,
				ratelimit = true,
			}
		}
	end
	
	local url = self.params.url
	if not utils.validate_imageurl(url) then
		return {
			status = 400, -- conflict
			json = {
				success = false,
				reason = "Not whitelisted URL or bad format"
			}
		}		
	end
	
	-- not accurate?
	local fsize=0
	local t=setmetatable({},{__newindex=function(t,k,v)
		fsize = fsize + #v
		if fsize>1 then
			yield_error("download too big: "..tostring(fsize))
			error"download too big"
		end
	end})
	
	local io = require("io")
	local http = require("lapis.nginx.http")
	local ltn12 = require("ltn12")
	
	local ret,code,hdr,statusline = http.request{ 
		url = url,
		sink = ltn12.sink.table(t)
	}
	assert_error(ret,"Unable to download image: "..tostring(code))
	assert_error(code==200,"Unable to download image: Server returned "..tostring(code)..' '..tostring(statusline))
	
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
	
	local sid64 = utils.aid_to_sid64(accountid)
	local personaname
	if loadingscreen and not already then
		local prof = utils.Uncached_GetPlayerSummaries(sid64)
		if prof and prof.personaname then
			loadingscreen:update{comment=prof and prof.personaname}
			personaname = prof.personaname
		end
	end
	
	return {
		status = 201, -- created
		json = {
			success = true,
			id = loadingscreen.id,
			name = personaname,
			profile = prof
		}
	}
end))


app:get("/lsapi/last_created", capture_errors_json(function(self)
	utils.cachecontrol()

	
	local accountid,admin = utils.account_need(true)
	
	local url = self.params.url

	local last = db.last_created(accountid)
	
	return {
		json = {
			success = true,
			created = last
		}
	}
end))

local function set_approved(approve,self)
	utils.cachecontrol()
	--utils.do_csrf(self)
	
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

app:get("/lsapi/myvotes", capture_errors_json(function(self)
	utils.cachecontrol()
	local json = require'cjson'

	local accountid = utils.account_need(true)
	
	-- find existing votes
	local vote, err = db.votes:select("WHERE accountid=?",accountid, { fields = "vote, id" })
	local up,down = {},{}
	if not vote and err then yield_error(err) end
	for k,v in next,vote do
		if v.vote then
			up[#up+1] = v.id
		else
			down[#down+1] = v.id		
		end
	end
	if not up[1] then
		up = json.empty_array
	end
	if not down[1] then
		down = json.empty_array
	end
	return {
		json = {
			success = true,
			up = up,
			down = down
		}
	}
end))


app:post("/lsapi/vote/:id/:dir", capture_errors_json(function(self)
	utils.cachecontrol()
	
	utils.do_csrf(self)
	
	local accountid = utils.account_need(true,true)
	
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
	local old_dir 
	
	if vote then old_dir = vote.vote else old_dir = "NULL" end
	
	if dir == 'delete' then
		if not vote then
			return {
				status = 304, -- not modified
				json = {
					success = true,
					dir = "NULL",
					dir_old = "NULL"
				}
			}			
		end
		assert_error(vote, "no vote to delete")
		vote:delete()
	else
		if vote then
			if vote.vote == dir then
				return {
					status = 304, -- not modified
					json = {
						success = true,
						dir = dir
					}
				}
			end
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
			success = true,
			dir = dir,
			dir_old = old_dir
		}
	}
end))



return app