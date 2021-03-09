--[[
     LuaLua
     Copyright (c) 2020 Jan Gabrielsson
     Email: jan@gabrielsson.com
     MIT License
--]]

-- requires json.encode

Toolbox_Module = Toolbox_Module or {}

Toolbox_Module.LuaCompiler ={
  name = "Lua compiler",
  author = "jan@gabrielsson.com",
  version = "0.3"
}

function Toolbox_Module.LuaCompiler.init(self,args)
  if Toolbox_Module.LuaCompiler.inited then return Toolbox_Module.LuaCompiler.inited end
  Toolbox_Module.LuaCompiler.inited = true
  
  local EVENTSCRIPT = args.EventScript
  local luc = {}
  local compile,evaluate,coroutine
  local lastFunCalled,lastEnv
  local LL,LC = 0,0
  local format = string.format 

  if not self then -- replacements
    self = {}
    local function conv(...) 
      local arr = {...}
      for i=1,#arr do arr[i]=type(arr[i])=='table' and json.encode(arr[i]) or tostring(arr[i]) end 
      return unpack(arr)
    end
    function self:debugf(fmt,...) print("DEBUG: "..format(fmt,conv(...))) end
    function self:errorf(fmt,...) print("ERROR: "..format(fmt,conv(...))) end
    function self:tracef(fmt,...) print("TRACE: "..format(fmt,conv(...))) end
  end

  local function wait(...)
    error({type='wait',args={...}})
  end

  local function isSystemThrow(err) return type(err)=='table' and err.type=='yield' or err.type=='wait' end -- Only have 2!

  local function makeCode()
    local self,instructions = {},{}
    self.code = instructions
    function self:add(...) local c = {...} instructions[#instructions+1]=c return c end
    function self:pos() return #instructions end
    return self
  end

  local function makeStack()
    local self,p,st = {},0,{}
    self.st = st
    function self.push(v) p=p+1 st[p]=v end
    function self.pushArr(v) for i=1,#v do p=p+1 st[p]=v[i] end end
    function self.pop() local v = st[p]; st[p]=nil; p=p-1; return v end
    function self.peek(n) return st[p-(n or 0)] end
    function self.p() return p end
    function self.setPos(n) assert(p==n,"Stack problems") p=n  end
    function self.setPos2(n) p=n  end
    function self.put(n,v) st[p+n]=v end
    function self.popn(n) 
      local res = {}
      for i=1,n do local ii=p-n+i res[i]=st[ii] st[ii]=nil end
      p=p-n
      return res
    end
    return self
  end

  local function isConst(v) return type(v)~='table' end
  local function isVar(v) return type(v)=='table' and v[1]=='var' end
  local function isGlob(v) return type(v)=='table' and v[1]=='glob' end
  local function isVarGlob(v) return isVar(v) or isGlob(v) end
  local function eqf(a,b)
    if type(a) == type(b) and type(a)=='table' and #a==#b then
      for i=1,#a do if not eqf(a[i],b[i]) then return false end end
      return true
    end
    return a==b
  end

  local opers = {
    ['+'] = function(a,b) return a+b end,
    ['-'] = function(a,b) return a-b end,
    ['*'] = function(a,b) return a*b end,
    ['/'] = function(a,b) return a/b end,
    ['..'] = function(a,b) return a..b end,
  }

  local optFun = {
    ['+'] = function(e) return isConst(e[2]) and isConst(e[3]) and e[2]+e[3] or e end,   -- constant folding
    ['-'] = function(e) return isConst(e[2]) and isConst(e[3]) and e[2]-e[3] or e end,
    ['*'] = function(e) return isConst(e[2]) and isConst(e[3]) and e[2]*e[3] or e end,
    ['/'] = function(e) return isConst(e[2]) and isConst(e[3]) and e[2]/e[3] or e end,
    ['assign'] = function(e)
      if #e[2]==1 then
        local var = e[2][1]
        local val,pfix = e[3][1],""
        if var[1]=='aref' then pfix="_aref" end
        if isConst(val) then return {'assign_const'..pfix,var,val}
        elseif opers[val[1]] and eqf(val[2],var) then
          if isConst(val[3]) then
            return {'inc_var_const'..pfix,val[1],var,val[3]}
          else
            return {'inc_var'..pfix,val[1],var,val[3]}
          end
        else return {'assign_var'..pfix,var,val} end
      end
      return e
    end
  }

  local function optTree(e)
    if type(e)=='table' then
      for i=1,#e do e[i]=optTree(e[i]) end
      if optFun[e[1]] then return optFun[e[1]](e)
      else return e end
    end
    return e
  end

  local function compileArgs(n,args,code)
    if n==1 then compile(args[1],code)
    elseif n>1 then
      for i=1,n-1 do compile(args[i],code) end
      code:add("clear_mv")
      compile(args[n],code)
    end
  end

  local blockFuns = { ['local']='true', foridx=true, forlist=true }
  local compExpr = {
    ['block'] = function(expr,code)
      local locals = false
      for _,e in ipairs(expr[2]) do
        if blockFuns[e[1]] then locals = true break; end -- These need enterblock/exitblock
      end
      if locals then code:add("enterblock") end
      for _,e in ipairs(expr[2]) do
        if not compile(e,code) then code:add("pop") end
      end
      if locals then code:add("exitblock") end
    end,
    ['local'] = function(e,code)
      local vars = {} for _,v in ipairs(e[2]) do vars[#vars+1]=v[2] end
      local vals,nv,n = e[3],#vars,#e[3]
      compileArgs(n,vals,code)
      code:add('locals',vars,n)
      return true
    end,     
    ['assign'] = function(e,code)
      local vars,vals,nv,n = e[2],e[3],#e[2],#e[3] -- x,y,z = 1,2
      for i=1,nv do
        if vars[i][1]=='aref' then
          compile(vars[i][2],code)          -- push obj, key
          compile(vars[i][3],code)
        end
      end
      compileArgs(n,vals,code)    -- push all values      
      code:add('passign',vars,n)
      return true
    end,

    ['inc_var'] = function(e,code) compile(e[4],code) code:add("inc_"..e[3][1],e[3][2],e[2]) return true end,
    ['inc_var_const'] = function(e,code) code:add("inc_"..e[3][1].."_const",e[3][2],e[2],e[4]) return true end,
    ['assign_var'] = function(e,code) compile(e[3],code) code:add("assign_"..e[2][1],e[2][2]) return true end,
    ['assign_const'] = function(e,code) code:add("assign_"..e[2][1].."_const",e[2][2],e[3]) return true end,
    ['assign_var_aref'] = function(e,code) 
      local obj = e[2]
      compile(e[3],code)
      compile(obj[2],code)
      compile(obj[3],code)
      code:add("assign_aref",e[2]) 
      return true 
    end,    
    ['inc_var_aref'] = function(e,code) 
      local obj = e[3]
      compile(e[4],code)
      compile(obj[2],code)
      compile(obj[3],code)
      code:add("inc_aref",e[2]) 
      return true 
    end,
    ['inc_var_const_aref'] = function(e,code) 
      local obj = e[3]
      compile(obj[2],code)
      compile(obj[3],code)
      code:add("inc_aref_const",e[2],e[4]) 
      return true 
    end,
    ['assign_const_aref'] = function(e,code) 
      local obj = e[2]
      compile(obj[2],code)
      compile(obj[3],code)
      code:add("assign_aref_const",e[3]) 
      return true 
    end,
    ['var'] = function(e,code) code:add("var",e[2]) end,
    ['callobj'] = function(e,code)
      local vals,n=e[4],#e[4]
      compile(e[2],code)
      compileArgs(n,vals,code)
      code:add("callobj",e[3],n)
    end,
    ['return0'] = function(e,code) code:add('return',0) end,
    ['return1'] = function(e,code) compile(e[2][1],code) code:add('return',1) end,
    ['returnn'] = function(e,code) 
      local vals,n = e[2],#e[2]
      compileArgs(n,vals,code)
      code:add('return',n) 
    end,
    ['aref'] = function(e,code) 
      if type(e[3])=='table' then
        compile(e[2],code) compile(e[3],code)  code:add('aref2') 
      else
        compile(e[2],code) code:add('aref1',e[3]) 
      end
    end,
    ['glob'] = function(e,code) code:add('glob',e[2]) end,
    ['+'] = function(e,code) compile(e[2],code) compile(e[3],code) code:add('add') end,
    ['-'] = function(e,code) compile(e[2],code) compile(e[3],code) code:add('sub') end,
    ['*'] = function(e,code) compile(e[2],code) compile(e[3],code) code:add('mul') end,
    ['/'] = function(e,code) compile(e[2],code) compile(e[3],code) code:add('div') end,
    ['%'] = function(e,code) compile(e[2],code) compile(e[3],code) code:add('mod') end,
    ['^'] = function(e,code) compile(e[2],code) compile(e[3],code) code:add('pow') end,
    ['==']= function(e,code) compile(e[2],code) compile(e[3],code) code:add('eq') end,
    ['~=']= function(e,code) compile(e[2],code) compile(e[3],code) code:add('neq') end,
    ['>'] = function(e,code) compile(e[2],code) compile(e[3],code) code:add('gt') end,
    ['>=']= function(e,code) compile(e[2],code) compile(e[3],code) code:add('gte') end,
    ['<'] = function(e,code) compile(e[2],code) compile(e[3],code) code:add('lt') end,
    ['<=']= function(e,code) compile(e[2],code) compile(e[3],code) code:add('lte') end,
    ['not']=function(e,code) compile(e[2],code) code:add('not') end,
    ['#']  =function(e,code) compile(e[2],code) code:add('len') end,
    ['%neg']=function(e,code) compile(e[2],code) code:add('neg') end,
    ['..'] =function(e,code) compile(e[2],code) compile(e[3],code) code:add('concat') end,
    ['nop']  =function(e,code) compile(e[2],code) end,
    ['quote']=function(e,code) code:add('quote',e[2]) end,
    ['and']  = function(e,code) 
      compile(e[2],code)
      local p = code:pos()
      local i = code:add("ifnskip")
      compile(e[3],code)
      i[2]=code:pos()-p
    end,
    ['or'] = function(e,code) 
      compile(e[2],code)
      local p = code:pos()
      local i = code:add("ifskip")
      compile(e[3],code)
      i[2]=code:pos()-p
    end,
    ['table'] = function(e,code) 
      local n,v,args = #e[2],e[2],{}
      for i=1,n do compile(v[i][2] or i,code) args[i]=v[i][1] end
      compileArgs(n,args,code)
      code:add('table',n)
    end,
    ['call'] = function(e,code)
      local args,n=e[3],#e[3]
      compileArgs(n,args,code)
      compile(e[2],code)
      code:add("call",n,e[2])
    end,
    ['break'] = function(e,code) code:add("break") return true end,
    ['vararg'] = function(e,code) code:add("vararg") return true end,
    ['if'] = function(e,code)
      local t,et,ei,ee,gto=e[2],e[3],e[4],e[5],{}  -- test ifnskip A <then> goto B, A <else> B
      ei = ei or {}
      table.insert(ei,1,{t,et})
      for i,fi in ipairs(ei) do
        compile(fi[1],code)
        local skip,p1 = code:add("ifnskip3"),code:pos()
        compile(fi[2],code)
        if i < #ei or ee then
          gto[#gto+1] = {code:add("goto"),code:pos()}
        end
        skip[2]=code:pos()-p1+1
      end
      if ee then
        compile(ee,code)
      end
      for _,gt in ipairs(gto) do
        gt[1][2]=code:pos()-gt[2]+1
      end
      return true
    end,
    ['while'] = function(e,code)  -- A <test> ifnskip B <body> goto A, B
      local ea=code:add("exit_address")
      local p1 = code:pos()
      compile(e[2],code)
      local skip,p2 = code:add("ifnskip3"),code:pos()
      compile(e[3],code)
      code:add("goto",p1-code:pos())
      skip[2]=code:pos()-p2+1
      ea[2]=code:pos()+1
      return true
    end,  
    ['repeat'] = function(e,code)  -- A <body> <test> ifskip goto A
      local ea=code:add("exit_address")
      local p1 = code:pos()
      compile(e[3],code)
      compile(e[2],code)
      code:add("ifnskip3",p1-code:pos())
      ea[2]=code:pos()+1
      return true
    end,  
    ['foridx'] = function(e,code)  -- 
      local v,start,stop,step = e[2],e[3],e[4],e[5]
      local ea=code:add("exit_address")
      compile(stop,code)
      compile(step,code)
      compile(start,code)
      code:add("locals",{v},1)
      local f,p = code:add("foridx_entry",v),code:pos()
      compile(e[6],code)
      code:add("foridx_inc",v,p-code:pos())
      f[3]=code:pos()-p+1
      ea[2]=code:pos()+1
      return true
    end,  
    ['forlist'] = function(e,code)  -- A <test> ifnskip B <body> goto A, B
      local v1,v2,fun,body = e[2],e[3],e[4][1],e[5]
      local ea=code:add("exit_address")
      compile(fun,code)
      code:add('locals',{'I','L',v1,v2},1)
      local p = code:pos()
      compile({"call",{'var','I'},{{'var','L'},{'var',v1}}},code)
      code:add("passign",{{'var',v1},{'var',v2}},1)
      code:add("var",v1)
      local skip,ep = code:add("ifnskip"),code:pos()
      compile(body,code)
      code:add("goto",p-code:pos())
      skip[2]=code:pos()-ep+1
      ea[2]=code:pos()+1
      return true
    end,
    ['function'] = function(e,code)  
      local typ,obj,name,params,varg,body = e[2],e[3],e[4],e[5],e[6],e[7]
      local fcode = makeCode()
      if obj=='obj' then table.insert(params,1,'self') end
      compile(body,fcode)
      fcode.code[#fcode.code+1]={'return',0}
      if obj=='obj' then
        compile(name[3],code)
        compile(name[2],code)
      end
      code:add("function",params,varg,typ,obj,name,fcode.code)
    end,
  }

  if EVENTSCRIPT then
    compExpr['$'] = function(expr,code)
      code:add("fibglobal")
    end
  end

  function compile(expr,code)
    if type(expr) == 'table' and #expr>0 then
      if not compExpr[expr[1]] then 
        error("Missing:"..expr[1]) 
      end
      return compExpr[expr[1]](expr,code)
    else 
      code:add('push',expr)
    end
  end

  luc.compile = compile 

  local function lookupVar(var,vars) 
    while vars do 
      if vars[var] then return vars[var] else vars=vars._next end 
    end 
  end

--[[ meta table support
__index     V
__newindex  V
__call 
__metatable 
__tostring
__len
__pairs
__ipairs
__unm 
__add
__sub
__mul
__div
__idiv 
__mod
__pow
__concat 
__eq      
__lt 
__le
--]] 

  local function assignTable(tab,key,val)  -- metatable hooks
    local m = tab.__META
    if not m then tab[key]=val return
    elseif tab[key]==nil then 
      if type(m.__newindex)=='function' then return m.__newindex(tab,key,val)
      elseif type(m.__newindex)=='table' then m.__newindex[key]=val return end
    end
    tab[key]=val
  end

  local function getTable(tab,key)     -- metatable hooks
    local m = tab.__META
    if not m then return tab[key]
    elseif tab[key] == nil then
      if type(m.__index)=='function' then return m.__index(tab,key)
      elseif type(m.__index)=='table' then return m.__index[key] end
    end
    return tab[key] 
  end

  local assignPassign = {
    ['var'] = function(v,value,env,st)
      local ve = lookupVar(v[2],env.vars)
      if ve then ve[1]=value else _G[v[2]]=value end
    end,
    ['glob'] = function(v,value,env,st) _G[v[2]]=value end,
    ['aref'] = function(v,value,env,st) local k,o = st.pop(),st.pop() assignTable(o,k,value) end,
  }

  local function popArguments(n,st,env)
    local args,s,p = {},st.st,st.p()
    for i=1,n do args[n+1-i]=s[p+1-i] end 
    st.setPos2(p-n)
    if env.mv then for i=2,#env.mv do args[#args+1] = env.mv[i] end end
    env.mv = nil
    return args
  end

  local function callRes(res,st,env) -- return from call/callobj
    if res[1]=="<%%RUNME%%>" then    -- Magic marker signaling it was a LuaLua function
      LL = LL+1
      res[2].cont = function(res) LL=LL-1 st.push(res[1]) if #res > 1 then env.mv = res else env.mv=nil end end -- cont to push res
      env.stat = function(e) return true,res[2] end        -- tell loop to continue with LuaLua code
    else
      st.push(res[1]) if #res > 1 then env.mv = res else env.mv=nil end -- non-LuaLua code, just push result directly
    end
  end

  local eval = {
    ['enterblock'] = function(i,st,env) env.vars,env.stp = {_next=env.vars},st.p() end,
    ['exitblock'] = function(i,st,env) st.setPos(env.stp); env.vars = env.vars._next end,
    ['locals'] = function(i,st,env)
      local locals,vars,n = env.vars,i[2],i[3]
      local vals = popArguments(n,st,env)
      for i=1,#vars do locals[vars[i]]= {vals[i]} end 
    end,
    ['passign'] = function(i,st,env)
      local vars,n = i[2],i[3]
      local vals = popArguments(n,st,env)
      for i=1,#vars do assignPassign[vars[i][1]](vars[i],vals[i],env,st) end
    end,
    ['clear_mv'] = function(i,st,env) env.mv = nil end,
    ['exit_address'] = function(i,st,env) env.exit = i[2] end,
    ['break'] = function(i,st,env) return env.exit-env.p end,
    ['inc_var'] = function(i,st,env)       local vref = lookupVar(i[2],env.vars) vref[1]=opers[i[3]](vref[1],st.pop())  end,
    ['inc_var_const'] = function(i,st,env) local vref = lookupVar(i[2],env.vars) vref[1]=opers[i[3]](vref[1],i[4]) end,
    ['assign_var'] = function(i,st,env)    local vref = lookupVar(i[2],env.vars) vref[1]=st.pop() end,
    ['assign_var_const'] = function(i,st,env) local vref = lookupVar(i[2],env.vars) vref[1]=i[3] end,
    ['inc_glob'] = function(i,st)          local v=i[2] _G[v]=opers[i[3]](_G[v],st.pop()) end,
    ['inc_glob_const'] = function(i,st)    local v=i[2] _G[v]=opers[i[3]](_G[v],i[4]) end,
    ['assign_glob'] = function(i,st)       local v=i[2] _G[v]=st.pop() end, -- inc, + var val
    ['assign_glob_const'] = function(i,st) local v=i[2] _G[v]=i[3] end, -- inc, + var val

    ['inc_aref'] = function(i,st) local k,o,val = st.pop(),st.pop(),st.pop() assignTable(o,k,opers[i[2]](o[k],val)) end,
    ['inc_aref_const'] = function(i,st) local k,o = st.pop(),st.pop() assignTable(o,k,opers[i[2]](o[k],i[3])) end,
    ['assign_aref_const'] = function(i,st) local k,o = st.pop(),st.pop() assignTable(o,k,i[2]) end,
    ['assign_aref'] = function(i,st) local k,o = st.pop(),st.pop() assignTable(o,k,st.pop()) end,

    ['var']  = function(i,st,env) local v = lookupVar(i[2],env.vars) st.push(v and v[1]) end,
    ['push'] = function(i,st) st.push(i[2]) end,
    ['pop'] = function(i,st) st.pop() end,
    ['nop'] = function(i,st) end,
    ['aref2'] = function(i,st) local k,t = st.pop(),st.pop(); st.push(getTable(t,k)) end,
    ['aref1'] = function(i,st) local t = st.pop(); st.push(getTable(t,i[2])) end,
    ['return'] = function(i,st,env)
      local res = popArguments(i[2],st,env)
      if env.cont then
        env.cont(res)
        env.stat = function(e) return true,env.parent end
      else
        env.stat = function(st) return false,res end 
      end
    end,
    ['add'] = function(i,st) local b,a = st.pop(),st.pop() st.push(a+b) end,
    ['sub'] = function(i,st) local b,a = st.pop(),st.pop() st.push(a-b) end,
    ['mul'] = function(i,st) local b,a = st.pop(),st.pop() st.push(a*b) end,
    ['div'] = function(i,st) local b,a = st.pop(),st.pop() st.push(a/b) end,
    ['mod'] = function(i,st) local b,a = st.pop(),st.pop() st.push(a%b) end,
    ['pow'] = function(i,st) local b,a = st.pop(),st.pop() st.push(a^b) end,
    ['eq']= function(i,st) local b,a = st.pop(),st.pop() st.push(a==b) end,
    ['neq']= function(i,st) local b,a = st.pop(),st.pop() st.push(a~=b) end,
    ['gt'] = function(i,st) local b,a = st.pop(),st.pop() st.push(a>b) end,
    ['gte']= function(i,st) local b,a = st.pop(),st.pop() st.push(a>=b) end,
    ['lt'] = function(i,st) local b,a = st.pop(),st.pop() st.push(a<b) end,
    ['lte']= function(i,st) local b,a = st.pop(),st.pop() st.push(a<=b) end,
    ['not']= function(i,st) local a = st.pop(); st.push(not a) end,
    ['len']  = function(i,st) local a = st.pop(); st.push(#a) end,
    ['neg']= function(i,st) local a = st.pop(); st.push(-a) end,
    ['concat'] = function(i,st) local b,a = st.pop(),st.pop() st.push(a..b) end,
    ['quote']= function(i,st) st.push(i[2]) end,
    ['glob'] = function(i,st,env) local v = i[2]; if env.senv[v]~=nil then st.push(env.senv[v]) else st.push(env.genv[v]) end end,
    ['ifnskip'] = function(i,st) local t = st.peek() return not t and i[2] or st.pop() and nil end,
    ['ifnskip2'] = function(i,st) local t = st.peek() if not t then st.pop() return i[2] else return nil end end,
    ['ifnskip3'] = function(i,st) local t = st.pop() return not t and i[2] end,
    ['ifskip'] = function(i,st) local t = st.peek() return t and i[2] or st.pop() and nil end,
    ['table'] = function(i,st,env)
      local n,res = i[2],{}
      local vals = popArguments(n,st,env)         -- Optimize to one loop?
      for j=1,n do res[st.pop()]=vals[n+1-j] end
      for j=n+1,#vals do res[j]=vals[j] end
      st.push(res)
    end,
    ['call'] = function(i,st,env)
      local fun,args = st.pop(),popArguments(i[2],st,env)                   
      lastFunCalled,lastEnv,LuaLua = fun,env,false
      LC=LC+1
      callRes({fun(table.unpack(args))},st,env)
      LC=LC-1
    end,
    ['callobj'] = function(i,st,env)
      local args,method,obj = popArguments(i[3],st,env),i[2],st.pop()
      local fun = obj[method]
      lastFunCalled,lastEnv,LuaLua = fun,env,false
      LC=LC+1
      callRes({fun(obj,table.unpack(args))},st,env)
      LC=LC-1
    end,
    ['goto'] = function(i,st,env) return i[2] end,
    ['foridx_entry'] = function(i,st)
      local step,stop,x = st.peek(0),st.peek(1),st.peek(-1)
      if step >= 0 and x > stop or step < 0 and x < stop then st.pop() st.pop() return i[3] end
    end,
    ['foridx_inc'] = function(i,st,env)
      local step,stop,xref = st.peek(0),st.peek(1),lookupVar(i[2],env.vars)
      local x = xref[1]
      x=x+step
      if step >= 0 and x <= stop or step < 0 and x > stop then
        xref[1]=x
        st.put(1,x)
        return i[3]
      end
      st.pop(); st.pop();
    end,
    ['forlist_entry'] = function(i,st)
      local step,stop,x = st.peek(0),st.peek(1),st.peek(-1)
      if step >= 0 and x > stop or step < 0 and x < stop then st.pop(); st.pop() return i[3] end
    end,
    ['forlist_inc'] = function(i,st,env)
      local step,stop,xref = st.peek(0),st.peek(1),lookupVar(i[2],env.vars)
      local x = xref[1]
      x=x+step
      if step >= 0 and x <= stop or step < 0 and x > stop then
        xref[1]=x
        st.put(1,x)
        return i[3]
      end
      st.pop(); st.pop()
    end,
    ['vararg'] = function(i,st,env)
      local ref = lookupVar('...',env.vars)
      env.mv = ref and ref[1]
      st.push(env.mv[1])
    end,
    ['function'] = function(i,st,env) --"function",params,varg,typ,obj,name,fcode.code)
      local params,varg,typ,obj,name,code,vars = i[2],i[3],i[4],i[5],i[6],i[7],env.vars
      local function fun(...)
        local args,locals = {...},{}
        for i=1,#params do locals[params[i]]={args[i]} end -- bind args to params, check varargs
        if varg then
          local rest={}
          for i=#params+1,#args do rest[#rest+1]=args[i] end
          locals['...']={rest}
        end
        locals._next=vars
        local env = {
          p=1, code=code, stack=makeStack(), vars=locals, genv=env.genv, senv=env.senv, debug=env.debug
        }
        local co = coroutine.running() 
        if co then co.env=env end    -- If co - patch in our env. so we can pickup in resume/yield
        if lastFunCalled ~= fun then -- Called from "C"
          lastEnv = env
          lastFunCalled = fun
          return evaluate(env)       -- ...not much else to do
        else
          env.parent = lastEnv
          lastEnv = env
          return "<%%RUNME%%>",env
        end

      end
      if     obj=='obj'  then local o,k = st.pop(),st.pop() assignTable(o,k,fun) st.push(fun)
      elseif typ=='expr' then                                         st.push(fun)
      elseif typ=='loc'  then env.vars[name[2]]={fun}                 st.push(fun)
      elseif typ=='glob' then _G[name[2]]=fun                         st.push(fun)
      end
    end
  }

  local function trimSafe(expr) local stat,res = pcall(json.encode,expr) return stat and res:sub(1,80) or "<non-json>" end
  function evaluate(env)
    LuaLua = true
    local stack,code,trace,inst = env.stack,env.code,env.debug.trace
    local stat = {
      pcall(function()
          if trace then
            while true do           -- a bit slower trace/debug loop
              inst = code[env.p]
              if not eval[inst[1]] then self:errorf("Not implemented: %s",inst) end
              local thread = coroutine.running() or {name="main"}
              self:tracef("%-7s PC:%03d ST:%03d %-30s %s",thread.name,env.p,stack.p(),trimSafe(inst),trimSafe(stack.peek()))
              env.p = env.p + (eval[inst[1]](inst,stack,env) or 1)
              if env.stat then                                -- returns/calls
                local new,res = env.stat(env) 
                env.stat = nil
                if new then
                  env,code,stack = res,res.code,res.stack     -- call - stay in loop
                else return unpack(res) end                   -- return values
              end
            end
          else
            while true do           -- optimized non-trace loop
              inst = code[env.p]
              env.p = env.p + (eval[inst[1]](inst,stack,env) or 1)
              if env.stat then                                -- returns/calls
                local call,res = env.stat(env) 
                env.stat = nil
                if call then
                  env,code,stack = res,res.code,res.stack     -- call - stay in loop
                else return unpack(res) end                   -- return values
              end
            end
          end
        end)
    }
    if not stat[1] then -- Catch errors and "yields" (sytemThrows)
      if not isSystemThrow(stat[2]) then 
        if type(stat[2])=='string' then error(format("LuaLua, instruction:%s - %s",json.encode(inst),stat[2]),0) end
        self:errorf("LuaLua, instruction:%s",inst) 
      end
      return error(stat[2])               -- Rethrow systemThrow
    else 
      return select(2,table.unpack(stat)) -- return values
    end
  end

  local parser = require('LuaParser')
  luc.parser = parser
  luc.optimizer = optTree

  function luc.load(str, locals, global_env, shadow_env, debug)
    debug,locals = debug or {},locals or {}
    local p = parser(str,locals)
    p = optTree(p)
    if debug.struct then self:debugf("%s",p) end
    local code = makeCode()
    compile(p,code)
    code.code[#code.code+1]={"return",0}
    if debug.code then self:debugf("%s",code.code) end
    if debug.codel then 
      hc3_emulator.colorDebug = false
      for i,inst in ipairs(code.code) do self:debugf("PC:%3d %s",i,inst) end
      hc3_emulator.colorDebug = true
    end

    return function()
      local env = {p=1, vars=locals, code=code.code, stack=makeStack(), genv=global_env or _G, senv=shadow_env or {}, debug=debug}
      local co = coroutine.running() 
      if co then co.env=env end
      return evaluate(env) -- 
    end
  end

  coroutine = { _running = nil, threadIndex=0 }
  local function isCoroutine(co) return type(co)=='table' and co._coro end

  function coroutine.create(fun) 
    assert(type(fun)=='function',"coroutine.create(f) expected function")
    coroutine.threadIndex = coroutine.threadIndex+1
    local co = {_coro=true,fun=fun, status='suspended', name=format("[T:%03s]",coroutine.threadIndex)}
    co.__tostring = function() return co.name end
    return co
  end

  function coroutine.resume(co,...) 
    assert(isCoroutine(co),"coroutine.resume(co) - 'co' is not a coroutine")
    if co.status == 'dead' then return false,"cannot resume dead coroutine" end
    co.status='running'
    local args = {...}
    LL,LC=0,0
    local stat = {pcall(function()
          coroutine.Running = co
          LuaLua = true
          if co.env then                       -- Resuming already running
            co.env.stack.push(args[1]) 
            if #args>1 then co.env.mv = args end
            evaluate(co.env)
          else 
            --lastFunCalled = co.fun
            co.fun(unpack(args))                -- Fresh start  // -- callRes(res,st,env)
          end  
        end
      )}
    coroutine.Running = nil
    if not stat[1] then
      if type(stat[2])=='table' and stat[2].type=='yield' then
        assert(LC-LL <=1,"attempt to yield across non LuaLua-call boundary")
        co.status = 'suspended'
        co.env.p = co.env.p+1
        return true,table.unpack(stat[2].args)
      else
        co.status='dead'
        return false,tostring(stat[2])
      end
    end
    co.status='dead'
    return true,select(2,table.unpack(stat))
  end

  function coroutine.status(co) 
    assert(isCoroutine(co),"coroutine.status(co) - 'co' is not a coroutine")
    return co.status 
  end

  function coroutine.yield(...)
    --   print("Y",LL,LC)
    assert(coroutine.running(),"Yield called outside coroutine")
    error({type='yield',args={...}})
  end

  function coroutine.running() return coroutine.Running end

  luc.coroutine = coroutine 

  luc.stdFuns = {  -- builtin functions
    ['rawset'] = function(t,k,v) k[t]=v end,
    ['rawget'] = function(t,k) return k[t] end,
    ['getmetatable'] = function(t) return t.__META end,
    ['setmetatable'] = function(t,m) t.__META = m end,
    ['coroutine'] = coroutine,
  }
  
  Toolbox_Module.LuaCompiler.inited = luc
  return luc
end
