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

function _M.cachecontrol(n)
	ngx.header.Cache_Control = n and ("max-age="..n) or "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
end

function _M.thumb(url)
	
	ltn12.sink.file(io.open("copy.png"))


	--local magick = require("magick") 
	--magick.thumb("input.png", "100x100", "output.png")
end

function _M.account(need,need_admin,noredir)
	
	local meta_auth = require'metaauth'
	local auth = meta_auth.new()
	
	if need or need_admin then
		if noredir then
			local steamid,admin,c,d,e = auth:get_user()
			assert(not ngx.headers_sent)
			if not steamid then
				auth:deny("Authentication required",401)
				error"?"
			end
			if need_admin and not admin then
				auth:deny("Admin privileges required")
				error"?"
			end
			return steamid,admin,c,d,e
		end
		
		return auth:need_user(need_admin)
		
	else
		return auth:get_user()
	end
end
function _M.account_need(...)
	return _M.account(true,false,...)
end
function _M.account_need_admin(...)
	return _M.account(true,true,...)
end
return _M