local config = require("lapis.config").get()
local util = require("lapis.util")
local app_helpers = require("lapis.application")
local capture_errors_json, yield_error = app_helpers.capture_errors_json, app_helpers.yield_error
local capture_errors, assert_error = app_helpers.capture_errors, app_helpers.assert_error

local csrf = require("lapis.csrf")

local _M={}

do -- debug
	function table.val_to_str ( v )
	  if "string" == type( v ) then
		v = string.gsub( v, "\n", "\\n" )
		if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
		  return "'" .. v .. "'"
		end
		return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
	  else
		return "table" == type( v ) and table.tostring( v ) or
		  tostring( v )
	  end
	end

	function table.key_to_str ( k )
	  if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
		return k
	  else
		return "[" .. table.val_to_str( k ) .. "]"
	  end
	end

	function table.tostring( tbl )
	  local result, done = {}, {}
	  for k, v in ipairs( tbl ) do
		table.insert( result, table.val_to_str( v ) )
		done[ k ] = true
	  end
	  for k, v in pairs( tbl ) do
		if not done[ k ] then
		  table.insert( result,
			table.key_to_str( k ) .. "=" .. table.val_to_str( v ) )
		end
	  end
	  return "{" .. table.concat( result, "," ) .. "}"
	end
end



function _M.wilson(positiveScore, total)

    if total == 0 then
        return 0,0
    end

    -- phat is the proportion of successes
    -- in a Bernoulli trial process
    local phat = positiveScore / total

    -- z is 1-alpha/2 percentile of a standard
    -- normal distribution for error alpha=5%
    local z = 1.96

    -- implement the algorithm
    -- (http://goo.gl/kgmV3g)
    local a = phat + z * z / (2 * total)
    local b = z * math.sqrt((phat * (1 - phat) + z * z / (4 * total)) / total)
    local c = 1 + z * z / total

    return (a - b) / c,
    	   (a + b) / c
end

function _M.forbidden(r,code)
	return {
		status = code or 403,
		json = {
			success = false,
			reason = r or "Access denied"
		}
	}
end

local bn = require'bc'
function _M.sid64_to_accountid(sid64)
	sid64 = bn.number(sid64) 
	local aid = sid64 - (sid64/2^32)*(2^32) 
	return tonumber(tostring(aid))
end
local sidto64= bn.number"76561197960265728"
function _M.aid_to_sid64(accountid)
	accountid = bn.number(accountid)
	local sid64 = accountid + sidto64
	return tostring(sid64)
end

function _M.cachecontrol(n)
	ngx.header.Cache_Control = n and ("max-age="..n) or "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
end

function _M.cors(options)
	-- obsolete
end

local function _sidfix(sid64,...)
	local aid = _M.sid64_to_accountid(sid64)
	return aid,...
end

function _M.do_csrf(self)

	if ngx.req.get_headers()['X-API-Key'] then return end

	csrf.assert_token(self, function(data)
		if os.time() > (data.expires or 0) then
		return nil, "token is expired"
		end

		return true
	end)
end

function _M.RateLimit(accountid)

end

function _M.validate_imageurl(url)
	if url:match'^https?://i.imgur.com/[^%.%/]+.png$' then return true end
	if url:match'^https?://i.imgur.com/[^%.%/]+.jpg$' then return true end
	if url:match'^https?://steamuserimages%-a%.akamaihd.net/ugc/.*$' then return true end
	if url:match'^https?://images.akamai%.steamusercontent%.com/ugc/.*$' then return true end
	return false
end

function _M.Uncached_GetPlayerSummaries(sid64)
	local url = ("http://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s&format=json"):format(config.steamapi,sid64)
	
	local http = require("lapis.nginx.http")
	local ltn12 = require("ltn12")
	
	local respbody={}
	local ret = table.tostring{http.request{ 
		url = url,
		sink = ltn12.sink.table(respbody)
	}}
	assert_error(ret,"download from origin failed")
	local t = assert_error(util.from_json(table.concat(respbody)))
	return t and t.response and t.response.players and t.response.players[1]
end

function _M.account(need,need_admin,noredir,apikey_ok)
	
	local meta_auth = require'metaauth'
	local auth = meta_auth.new()
	
	if need or need_admin then
		if noredir then
			local steamid,admin,c,d,e = auth:get_user(apikey_ok)
			assert(not ngx.headers_sent)
			if not steamid then
				--ngx.say(table.tostring{ngx.req.get_headers()})
				--ngx.exit(404)
				auth:deny("Authentication required!",401)
				error"?"
			end
			if need_admin and not admin then
				auth:deny("Admin privileges required")
				error"?"
			end
			return _sidfix(steamid),admin,c,d,e
		end
		
		return _sidfix(auth:need_user(need_admin,false,apikey_ok))
		
	else
		return _sidfix(auth:get_user(apikey_ok))
	end
end
function _M.account_need(...)
	return _M.account(true,false,...)
end
function _M.account_need_admin(...)
	return _M.account(true,true,...)
end

return _M