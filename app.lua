local lapis = require "lapis"
local app = lapis.Application()

package.path = 'scripts/r18/?.lua;' .. 'scripts/?.lua;' .. package.path

require'r18.config'
local utils = require'r18.utils'
local templates = require'r18.templates'

local db = require 'r18.db'

local csrf = require("lapis.csrf")
local app_helpers = require("lapis.application")
local capture_errors_json, yield_error = app_helpers.capture_errors_json, app_helpers.yield_error
local capture_errors, assert_error = app_helpers.capture_errors, app_helpers.assert_error
local respond_to = require("lapis.application").respond_to
local root = "/home/srcds/fastdl/"


local function isverified(usr)
	return usr and usr.verifier1 and usr.verifier2
end

local hmac_sha1
local function mkcode(accountid)
	local hmac = require "resty.hmac"
	
    hmac_sha1 = hmac_sha1 or hmac:new("ijojo435i3dasd=vsdbsdb12", hmac.ALGOS.SHA1)
    if not hmac_sha1 then
        return
    end
	
	local data = tostring(assert(tonumber(accountid)))
    local ok = hmac_sha1:update(data)
    if not ok then
        return
    end

    local mac = hmac_sha1:final()  -- binary mac

    local str = require "resty.string"

    if not hmac_sha1:reset() then
        return
    end
	
	return ("%08x%s"):format(accountid,str.to_hex(mac:sub(1,8)))
	
end

app:get("/r18", capture_errors_json(function(self)
	local accountid,admin,ingame = utils.account_need()
	utils.cachecontrol()
	local sid64 = utils.aid_to_sid64(accountid)
	
	local usr = db.get(accountid)
	local verified = isverified(usr)
	local code
	if not verified then
		code = mkcode(accountid)
	end
	local v1,v2 = usr and usr.verifier1,usr and usr.verifier2
	
	
	local has_verified = db.getby(accountid)
	if has_verified then
		for k,v in next,has_verified do
			v.sid64 = utils.aid_to_sid64(v.accountid)
		end
	end
	
	local myverifications = has_verified and {verifications=has_verified}
	return templates.index{
		accountid=accountid,
		verified=verified,
		unverified=not verified,
		code=code,
		v1=v1 and utils.aid_to_sid64(v1),
		v2=v2 and utils.aid_to_sid64(v2),
		myverifications = myverifications,
		
	}
	
end))

app:get("/r18/test", capture_errors(function(self)

	local t = templates.message{
		msg="test",		
	}
	t.status = 404
	
	return t
	
end))



app:get("/r18/verify/:code", capture_errors(function(self)
	local accountid,admin,ingame = utils.account_need()
	utils.cachecontrol()
	
	local usr = db.get(accountid)
	local verified = isverified(usr)
	
	if not verified and not admin then 
		return {
			layout=false,
			status = 403,
			'This account is not adult verified so you may not verify other accounts. Verify yourself first <a href="/r18">here</a>!',
		}
	end
	
	local code = self.params.code
	
	--local hex = require'hex'
	--local data,err = hex.decode(code)
	local target_accountid = tonumber(code:sub(1,2*4),16)
	if not target_accountid then 
		return {
			json = {
				success = false,
				error = "Invalid code"
			}
		}
	end
	
	local codeverify = mkcode(target_accountid)
	if codeverify ~= code then
		return {
			json = {
				success = false,
				error = "Code did not validate (Invalid or old)"
			}
		}
	end
	
	return templates.verify{accountid=target_accountid,sid64=utils.aid_to_sid64(target_accountid),csrf=csrf.generate_token(self),code=code}

end))

app:post("/r18/verify/:code", capture_errors(function(self)
	local accountid,admin,ingame = utils.account_need()
	utils.cachecontrol()
	csrf.assert_token(self)
	
	local code = self.params.code
	
	local target_accountid = tonumber(code:sub(1,2*4),16)
	if not target_accountid then 
		return "Invalid code"
	end
	
	if accountid == target_accountid then
		return {
			layout=false,
			status = 403,
			'You can not verify yourself! You should give this link to a person who is <b>already verified</b> and can confirm that you are adult.',
		}

	end
	
	local codeverify = mkcode(target_accountid)
	if codeverify ~= code then
		return {
			json = {
				success = false,
				error = "Code did not validate (Invalid or old)"
			},
			status = 400
		}
	end
	
	local usr = db.get(target_accountid)
	
	if not usr then
		db.set(target_accountid,accountid)
	elseif isverified(usr) then
		return "This user is already fully verified"
	else
		
		if usr.verifier1 == accountid or usr.verifier2 == accountid then
			return "You have already verified this person"
		end
		if usr.verifier1 then
			db.set(target_accountid,nil,accountid)
		elseif usr.verifier2 then
			db.set(target_accountid,accountid,nil)
		else
			db.set(target_accountid,accountid)
		end
	end
	
	return {
		layout=false,
		status = 403,
		'Verification confirmed! <br/> View your verifications <a href="/r18">here</a>.',
	}

end))

app:post("/r18/noverify/:accountid", capture_errors(function(self)
	utils.cachecontrol()
	csrf.assert_token(self)
		
	return "Thank you!"

end))

local function to_aid(accountid)
	
	if not accountid or not tonumber(accountid) then
		return
	end
	local tmp = tonumber(accountid)>2^32+1 and utils.sid64_to_accountid(accountid)
	if tmp and tmp>0 then
		accountid = tmp
	end
	return accountid
end

local to_json = require("lapis.util").to_json
app:get("/r18/v/:accountid", capture_errors_json(function(self)
	utils.cachecontrol(2)
	
	
	local accountid = to_aid(self.params.accountid)
	
	if not accountid then
		return {
			json = {
				success = false,
				error = "bad steamid"
			},
			status = 400
		}

	end

	local usr = db.get(accountid)
	local verified = isverified(usr) and true or false
	
	return {
		json = {
			success = true,
			verified = verified
		}
	}
	
end))


app:get("/r18/n/:accountid", capture_errors(function(self)
	utils.cachecontrol(2)
	
	local accountid_root = to_aid(self.params.accountid)
	
	if not accountid_root then
		return {
			json = {
				success = false,
				error = "bad steamid"
			},
			status = 400
		}

	end

	local usr = db.get(accountid_root)
	if not usr then return "no such account" end
	
	local nodes={
	}
	
	local links={
	
		
	}
	
	local visited = {}
	local all_users = {}
	local verifications = {}
	local id=0
	local function new(accountid)
		id = id + 1
		local t={}
		t.id=id
		t.accountid = accountid
		t.sid64=utils.aid_to_sid64(accountid)
		t.shape = 'image'
		t.image = "https://steamsignature.com/status/default/"..t.sid64..".png"
		t.label = tostring(accountid)
		nodes[#nodes+1]=t
		return t
	end
	
	local function new_dummy(parent)
		id = id + 1
		local t={}
		t.id=id
		t.label = "..."
		t.text = "..."
		t.accountid = parent
		t.sid64=utils.aid_to_sid64(parent)
		t.gonetwork = true
		nodes[#nodes+1]=t
		links[#links+1]={from=assert(all_users[parent].id),to=assert(t.id),arrows='to'}
		
		return t
	end
	
	local function verify(from,to)
		local t = verifications[from]
		if not t then t={} verifications[from]=t end
		if t[to] then return end
		t[to]=true
		local tonode = all_users[to]
		if not tonode then
			error(to)
		end
		tonode.verifications = (tonode.verifications or 0) + 1
		if tonode.verifications >=2 then
			tonode.color = {
				border = 'rgb(50,255,10)'
			}
		end
		links[#links+1]={from=assert(all_users[from].id),to=assert(all_users[to].id),arrows='to'}
	end
	
	local visit
	visit = function(accountid,n)
		if visited[accountid] then return end
		visited[accountid]=true
		all_users[accountid]=new(accountid)
		
		local has_verified = db.getby(accountid)
		if not has_verified then return end

		if n<0 then 
			if has_verified and #has_verified>0 then
				new_dummy(accountid)
			end
			return 
		end

		for _,t in next,has_verified do
			local accountid_verified = t.accountid
			visit(accountid_verified,n-1)
			verify(accountid,accountid_verified)
		end
		
	end
	visit(accountid_root,2)
	
	return templates.network{nodes=to_json(nodes),links=to_json(links)}

	
end))


return app