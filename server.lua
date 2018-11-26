local origins={
	['https://loadingscreen.metastruct.net'] = true,
	['https://lvh.me:3000'] = true,
	['http://lvh.me:3000'] = true,
	['http://localhost:3000'] = true,
	['http://loadingscreen2.metastruct.net:3000'] = true,
}

local origin = ngx.req.get_headers()["Origin"]
local ok = origins[origin]
ngx.header.Access_Control_Allow_Origin = ok and origin or ""
ngx.header.Access_Control_Allow_Methods = 'GET, POST, OPTIONS'
ngx.header.Access_Control_Allow_Headers = 'DNT,User-Agent,X-Requested-With,X-Has-ACookie,If-Modified-Since,Cache-Control,Content-Type,Range'
ngx.header.Access_Control_Expose_Headers = 'Content-Length,Content-Range'
ngx.header.Access_Control_Allow_Credentials = 'true'

if ngx.req.get_method() == 'OPTIONS' then
	ngx.header['Access-Control-Max-Age'] = 1728000
	ngx.header['Content-Type'] = 'text/plain; charset=utf-8'
	ngx.header['Content-Length'] = 0
	ngx.status = 204
	ngx.exit(204)
	return
end

local function escape(s)
  return s:gsub("[<>]",
    function(x)
      if x == '<' then
        return '&lt;'
      elseif x == '>' then
        return '&gt;'
      else
        return x
      end
    end)
end

local function errprint(ok,err)
	if not ok then
		ngx.status = 500
		
		ngx.header.Cache_Control = "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
		
		ngx.say(("<pre>%s</pre>"):format(escape(err)))
		return ngx.exit(500)
	end
	return err
end

package.path = 'scripts/lsapi/?.lua;' .. package.path
return errprint(xpcall(function()
	require("lapis").serve("app")
end,debug.traceback))
