-------- Start EventScript4 ------------------
INSTALLED_MODULES['EventScript4.lua']={isInstalled=true,installedVersion=0.1}
function setUpEventScript()

  local self = Util
  function self.map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
  function self.mapAnd(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) if not e then return false end end return e end 
  function self.mapOr(f,l,s) s = s or 1; for i=s,table.maxn(l) do local e = f(l[i]) if e then return e end end return false end
  function self.mapF(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) end return e end
  function self.mapkl(f,l) local r={} for i,j in pairs(l) do r[#r+1]=f(i,j) end return r end
  function self.mapkk(f,l) local r={} for k,v in pairs(l) do r[k]=f(v) end return r end
  function self.member(v,tab) for _,e in ipairs(tab) do if v==e then return e end end return nil end
  function self.append(t1,t2) for _,e in ipairs(t2) do t1[#t1+1]=e end return t1 end

  function isError(e) return type(e)=='table' and e.ERR end
  function throwError(args) args.ERR=true; error(args,args.level) end

  function self.mkStream(tab)
    local p,self=0,{ stream=tab, eof={type='eof', value='', from=tab[#tab].from, to=tab[#tab].to} }
    function self.next() p=p+1 return p<=#tab and tab[p] or self.eof end
    function self.last() return tab[p] or self.eof end
    function self.peek(n) return tab[p+(n or 1)] or self.eof end
    return self
  end
  function self.mkStack()
    local p,st,self=0,{},{}
    function self.push(v) p=p+1 st[p]=v end
    function self.pop(n) n = n or 1; p=p-n; return st[p+n] end
    function self.popn(n,v) v = v or {}; if n > 0 then local p = self.pop(); self.popn(n-1,v); v[#v+1]=p end return v end 
    function self.peek(n) return st[p-(n or 0)] end
    function self.lift(n) local s = {} for i=1,n do s[i] = st[p-n+i] end self.pop(n) return s end
    function self.liftc(n) local s = {} for i=1,n do s[i] = st[p-n+i] end return s end
    function self.isEmpty() return p<=0 end
    function self.size() return p end    
    function self.setSize(np) p=np end
    function self.set(i,v) st[p+i]=v end
    function self.get(i) return st[p+i] end
    function self.dump() for i=1,p do print(json.encode(st[i])) end end
    function self.clear() p,st=0,{} end
    return self
  end

  self._vars = {}
  local _vars = self._vars
  local _triggerVars = {}
  self._triggerVars = _triggerVars
  self._reverseVarTable = {}
  function self.defvar(var,expr) if _vars[var] then _vars[var][1]=expr else _vars[var]={expr} end end
  function self.defvars(tab) for var,val in pairs(tab) do self.defvar(var,val) end end
  function self.defTriggerVar(var,expr) _triggerVars[var]=true; self.defvar(var,expr) end
  function self.triggerVar(v) return _triggerVars[v] end
  function self.reverseMapDef(table) self._reverseMap({},table) end
  function self._reverseMap(path,value)
    if type(value) == 'number' then self._reverseVarTable[tostring(value)] = table.concat(path,".")
    elseif type(value) == 'table' and not value[1] then
      for k,v in pairs(value) do table.insert(path,k); self._reverseMap(path,v); table.remove(path) end
    end
  end
  function self.reverseVar(id) return Util._reverseVarTable[tostring(id)] or id end

  self.coroutine = {
    create = function(code,src,env)
      env=env or {}
      env.cp,env.stack,env.code,env.src=1,Util.mkStack(),code,src
      return {state='suspended', context=env}
    end,
    resume = function(co) 
      if co.state=='dead' then return false,"cannot resume dead coroutine" end
      if co.state=='running' then return false,"cannot resume running coroutine" end
      co.state='running' 
      local status,res = ScriptEngine.eval(co.context)
      co.state= status=='suspended' and status or 'dead'
      return true,table.unpack(res)
    end,
    status = function(co) return co.state end,
    _reset = function(co) co.state,co.context.cp='suspended',1; co.context.stack.clear(); return co.context end
  }

  function makeEventScriptParser()
    local source, tokens, cursor
    local mkStack,mkStream,toTime,map,mapkk,gensym=Util.mkStack,Util.mkStream,Util.toTime,Util.map,Util.mapkk,Util.gensym
    local patterns,self = {},{}
    local opers = {['%neg']={14,1},['t/']={14,1,'%today'},['n/']={14,1,'%nexttime'},['+/']={14,1,'%plustime'},['$']={14,1,'%vglob'},
      ['.']={12.9,2},[':']= {13,2,'%prop'},['..']={9,2,'%betw'},['...']={9,2,'%betwo'},['@']={9,1,'%daily'},['jmp']={9,1},['::']={9,1},--['return']={-0.5,1},
      ['@@']={9,1,'%interv'},['+']={11,2},['-']={11,2},['*']={12,2},['/']={12,2},['%']={12,2},['==']={6,2},['<=']={6,2},['>=']={6,2},['~=']={6,2},
      ['>']={6,2},['<']={6,2},['&']={5,2,'%and'},['|']={4,2,'%or'},['!']={5.1,1,'%not'},['=']={0,2},['+=']={0,2},['-=']={0,2},
      ['*=']={0,2},[';']={-1,2,'%progn'},
    }
    local nopers = {['jmp']=true,}--['return']=true}
    local reserved={
      ['sunset']={{'sunset'}},['sunrise']={{'sunrise'}},['midnight']={{'midnight'}},['dusk']={{'dusk'}},['dawn']={{'dawn'}},
      ['now']={{'now'}},['wnum']={{'wnum'}},['env']={{'env'}},
      ['true']={true},['false']={false},['{}']={{'quote',{}}},['nil']={{'%quote',nil}},
    }
    local function apply(t,st) return st.push(st.popn(opers[t.value][2],{t.value})) end
    local _samePrio = {['.']=true,[':']=true}
    local function lessp(t1,t2) 
      local v1,v2 = t1.value,t2.value
      if v1==':' and v2=='.' then return true 
      elseif v1=='=' then v1='/' end
      return v1==v2 and _samePrio[v1] or opers[v1][1] < opers[v2][1] 
    end
    local function isInstr(i,t) return type(i)=='table' and i[1]==t end

    local function tablefy(t)
      local res={}
      for k,e in pairs(t) do if isInstr(e,'=') then res[e[2][2]]=e[3] else res[k]=e end end
      return res
    end

    local pExpr,gExpr={}
    pExpr['lpar']=function(inp,st,ops,t,pt)
      if pt.value:match("^[%]%)%da-zA-Z]") then 
        while not ops.isEmpty() and opers[ops.peek().value][1] >= 12.9 do apply(ops.pop(),st) end
        local fun,args = st.pop(),self.gArgs(inp,')')
        if isInstr(fun,':') then st.push({'%calls',{'%aref',fun[2],fun[3]},fun[2],table.unpack(args)})
        elseif isInstr(fun,'%var') then st.push({fun[2],table.unpack(args)})
        elseif type(fun)=='string' then st.push({fun,table.unpack(args)})
        else st.push({'%calls',fun,table.unpack(args)}) end
      else
        st.push(gExpr(inp,{[')']=true})) inp.next()
      end
    end
    pExpr['lbra']=function(inp,st,ops,t,pt) 
      while not ops.isEmpty() and opers[ops.peek().value][1] >= 12.9 do apply(ops.pop(),st) end
      st.push({'%aref',st.pop(),gExpr(inp,{[']']=true})}) inp.next() 
    end
    pExpr['lor']=function(inp,st,ops,t,pt) 
      local e = gExpr(inp,{['>>']=true}); inp.next()
      local body,el = gExpr(inp,{[';;']=true,['||']=true})
      if inp.peek().value == '||' then el = gExpr(inp) else inp.next() end
      st.push({'if',e,body,el})
    end
    pExpr['lcur']=function(inp,st,ops,t,pt) st.push({'%table',tablefy(self.gArgs(inp,'}'))}) end
    pExpr['ev']=function(inp,st,ops,t,pt) local v = {}
      if inp.peek().value == '{' then inp.next() v = tablefy(self.gArgs(inp,'}')) end
      v.type = t.value:sub(2); st.push({'%table',v})
    end
    pExpr['num']=function(inp,st,ops,t,pt) st.push(t.value) end
    pExpr['str']=function(inp,st,ops,t,pt) st.push(t.value) end
    pExpr['nam']=function(inp,st,ops,t,pt) 
      if reserved[t.value] then st.push(reserved[t.value][1]) 
      elseif pt.value == '.' or pt.value == ':' then st.push(t.value) 
      else st.push({'%var',t.value,'script'}) end -- default to script vars
    end
    pExpr['op']=function(inp,st,ops,t,pt)
      if t.value == '-' and not(pt.type == 'name' or pt.type == 'number' or pt.value == '(') then t.value='%neg' end
      while ops.peek() and lessp(t,ops.peek()) do apply(ops.pop(),st) end
      ops.push(t)
    end

    function gExpr(inp,stop)
      local st,ops,t,pt=mkStack(),mkStack(),{value='<START>'}
      while true do
        t,pt = inp.peek(),t
        if t.type=='eof' or stop and stop[t.value] then break end
        t = inp.next()
        pExpr[t.sw](inp,st,ops,t,pt)
      end
      while not ops.isEmpty() do apply(ops.pop(),st) end
      --st.dump()
      return st.pop()
    end

    function self.gArgs(inp,stop)
      local res,i = {},1
      while inp.peek().value ~= stop do _assert(inp.peek().type~='eof',"Missing ')'"); res[i] = gExpr(inp,{[stop]=true,[',']=true}); i=i+1; if inp.peek().value == ',' then inp.next() end end
      inp.next() return res
    end

    local function token(pattern, createFn)
      table.insert(patterns, function ()
          local _, len, res, group = string.find(source, "^(" .. pattern .. ")")
          if len then
            if createFn then
              local token = createFn(group or res)
              token.from, token.to = cursor, cursor+len
              table.insert(tokens, token)
            end
            source = string.sub(source, len+1)
            cursor = cursor + len
            return true
          end
        end)
    end

    local function toTimeDate(str)
      local y,m,d,h,min,s=str:match("(%d?%d?%d?%d?)/?(%d+)/(%d+)/(%d%d):(%d%d):?(%d?%d?)")
      local t = os.date("*t")
      return os.time{year=y~="" and y or t.year,month=m,day=d,hour=h,min=min,sec=s~="" and s or 0}
    end

    local SW={['(']='lpar',['{']='lcur',['[']='lbra',['||']='lor'}
    token("[%s%c]+")
    --2019/3/30/20:30
    token("%d?%d?%d?%d?/?%d+/%d+/%d%d:%d%d:?%d?%d?",function (t) return {type="number", sw='num', value=toTimeDate(t)} end)
    token("%d%d:%d%d:?%d?%d?",function (t) return {type="number", sw='num', value=toTime(t)} end)
    token("[t+n][/]", function (op) return {type="operator", sw='op', value=op} end)
    token("#[A-Za-z_][%w_]*", function (w) return {type="event", sw='ev', value=w} end)
    --token("[A-Za-z_][%w_]*", function (w) return {type=nopers[w] and 'operator' or "name", sw=nopers[w] and 'op' or 'nam', value=w} end)
    token("[_a-zA-Z\xC3\xA5\xA4\xB6\x85\x84\x96][_0-9a-zA-Z\xC3\xA5\xA4\xB6\x85\x84\x96]*", function (w) return {type=nopers[w] and 'operator' or "name", sw=nopers[w] and 'op' or 'nam', value=w} end)
    token("%d+%.%d+", function (d) return {type="number", sw='num', value=tonumber(d)} end)
    token("%d+", function (d) return {type="number", sw='num', value=tonumber(d)} end)
    token('"([^"]*)"', function (s) return {type="string", sw='str', value=s} end)
    token("'([^']*)'", function (s) return {type="string", sw='str', value=s} end)
    token("%-%-.-\n")
    token("%-%-.*")  
    token("%.%.%.",function (op) return {type="operator", sw=SW[op] or 'op', value=op} end)
    token("[@%$=<>!+%.%-*&|/%^~;:][@=<>&|;:%.]?", function (op) return {type="operator", sw=SW[op] or 'op', value=op} end)
    token("[{}%(%),%[%]#%%]", function (op) return {type="operator", sw=SW[op] or 'op', value=op} end)


    local function dispatch() for _,m in ipairs(patterns) do if m() then return true end end end

    local function tokenize(src)
      source, tokens, cursor = src, {}, 0
      while #source>0 and dispatch() do end
      if #source > 0 then print("tokenizer failed at " .. source) end
      return tokens
    end

    local postP={}
    postP['%progn'] = function(e) local r={'%progn'}
      map(function(p) if isInstr(p,'%progn') then for i=2,#p do r[#r+1] = p[i] end else r[#r+1]=p end end,e,2)
      return r
    end
    postP['%vglob'] = function(e) return {'%var',e[2][2],'glob'} end
    postP['='] = function(e) 
      local lv,rv = e[2],e[3]
      if type(lv) == 'table' and ({['%var']=true,['%prop']=true,['%aref']=true,['slider']=true,['label']=true})[lv[1]] then
        return {'%set',lv[1]:sub(1,1)~='%' and '%'..lv[1] or lv[1],lv[2], lv[3] or true, rv}
      else error("Illegal assignment") end
    end
    postP['%betwo'] = function(e) 
      local t = Util.gensym("TODAY")
      return {'%and',{'%betw', e[2],e[3]},{'%and',{'~=',{'%var',t,'script'},{'%var','dayname','script'}},{'%set','%var',t,'script',{'%var','dayname','script'}}}}
    end 
    postP['if'] = function(e) local c = {'%and',e[2],{'%always',e[3]}} return self.postParse(#e==3 and c or {'%or',c,e[4]}) end
    postP['=>'] = function(e) return {'%rule',{'%quote',e[2]},{'%quote',e[3]}} end
    postP['.'] = function(e) return {'%aref',e[2],e[3]} end
    postP['::'] = function(e) return {'%addr',e[2][2]} end
    postP['%jmp'] = function(e) return {'%jmp',e[2][2]} end
    -- preC['return'] = function(e) return {'return',e[2]} end
    postP['%neg'] = function(e) return tonumber(e[2]) and -e[2] or e end
    postP['+='] = function(e) return {'%inc',e[2],e[3],'+'} end
    postP['-='] = function(e) return {'%inc',e[2],e[3],'-'} end
    postP['*='] = function(e) return {'%inc',e[2],e[3],'*'} end
    postP['+'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])+tonumber(e[3]) or e end
    postP['-'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])-tonumber(e[3]) or e end
    postP['*'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])*tonumber(e[3]) or e end
    postP['/'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])/tonumber(e[3]) or e end
    postP['%'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])%tonumber(e[3]) or e end

    function self.postParse(e)
      local function traverse(e)
        if type(e)~='table' or e[1]=='quote' then return e end
        if opers[e[1]] then 
          e[1]=opers[e[1]][3] or e[1]
        end
        local pc = mapkk(traverse,e); return postP[pc[1]] and postP[pc[1]](pc) or pc
      end
      return traverse(e)
    end

    local gStatements; local gElse; 
    local function matchv(inp,t,v) local t0=inp.next(); _assert(t0.value==t,"Expected '%s' in %s",t,v); return t0 end
    local function matcht(inp,t,v) local t0=inp.next(); _assert(t0.type==t,"Expected %s",v); return t0 end

    local function mkVar(n) return {'%var',n and n or gensym("V"),'script'} end
    local function mkSet(v,e) return {'%set',v[1],v[2],v[3],e} end        
    local function gStatement(inp,stop)
      local t,vars,exprs = inp.peek(),{},{}
      if t.value=='local' then inp.next()
        vars[1] = matcht(inp,'name',"variable in 'local'").value
        while inp.peek().value==',' do inp.next(); vars[#vars+1]= matcht(inp,'name',"variable in 'local'").value end
        if inp.peek().value == '=' then
          inp.next()
          exprs[1] = {gExpr(inp,{[',']=true,[';']=true})}
          while inp.peek().value==',' do inp.next(); exprs[#exprs+1]= {gExpr(inp,{[',']=true,[';']=true})} end
        end
        return {'%local',vars,exprs}
      elseif t.value == 'while' then inp.next()
        local test = gExpr(inp,{['do']=true}); matchv(inp,'do',"While loop")
        local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"While loop")
        return {'%frame',{'%while',test,body}}
      elseif t.value == 'repeat' then inp.next()
        local body = gStatements(inp,{['until']=true}); matchv(inp,'until',"Repeat loop")
        local test = gExpr(inp,stop)
        return {'%frame',{'%repeat',body,test}}
      elseif t.value == 'begin' then inp.next()
        local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"Begin block")
        return {'%frame',body} 
      elseif t.value == 'for' then inp.next()
        local var = matcht(inp,'name').value; 
        if inp.peek().value==',' then -- for a,b in f(x) do ...  end
          matchv(inp,','); --local l,a,b,c,i; c=pack(f(x)); i=c[1]; l=c[2]; c=pack(i(l,c[3])); while c[1] do a=c[1]; b=c[2]; ... ; c=pack(i(l,a)) end
          local var2 = matcht(inp,'name').value; 
          matchv(inp,'in',"For loop"); 
          local expr = gExpr(inp,{['do']=true}); matchv(inp,'do',"For loop")
          local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"For loop")
          local v1,v2,i,l = mkVar(var),mkVar(var2),mkVar(),mkVar()
          return {'%frame',{'%progn',{'%local',{var,var2,l[2],i[2]},{}},
              {'setList',{i,l,v1},{'pack',expr}},{'setList',{v1,v2},{'pack',{'%calls',i,l,v1}}},
              {'%while',v1,{'%progn',body,{'setList',{v1,v2},{'pack',{'%calls',i,l,v1}}}}}}}
        else -- for for a = x,y,z  do ... end
          matchv(inp,'=') -- local a,e,s,si=x,y,z; si=sign(s); e*=si while a*si<=e do ... a+=s end
          local inits = {}
          inits[1] = {gExpr(inp,{[',']=true,['do']=true})}
          while inp.peek().value==',' do inp.next(); inits[#inits+1]= {gExpr(inp,{[',']=true,['do']=true})} end
          matchv(inp,'do',"For loop")
          local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"For loop")
          local v,s,e,step = mkVar(var),mkVar(),mkVar(),mkVar()
          if #inits<3 then inits[#inits+1]={1} end
          local locals = {'%local',{var,e[2],step[2],s[2]},inits}
          return {'%frame',{'%progn',locals,mkSet(s,{'sign',step}),{'*=',e,s},{'%while',{'<=',{'*',v,s},e},{'%progn',body,{'+=',v,step}}}}}
        end
      elseif t.value == 'if' then inp.next()
        local test = gExpr(inp,{['then']=true}); matchv(inp,'then',"If statement")
        local body = gStatements(inp,{['end']=true,['else']=true,['elseif']=true})
        return {'if',test,{'%frame',body},gElse(inp)}
      else return gExpr(inp,stop) end 
    end

    function gElse(inp)
      if inp.peek().value=='end' then inp.next(); return nil end
      if inp.peek().value=='else' then inp.next()
        local r = gStatements(inp,{['end']=true}); matchv(inp,'end',"If statement"); return {'%frame',r}
      end
      if inp.peek().value=='elseif' then inp.next(); 
        local test = gExpr(inp,{['then']=true}); matchv(inp,'then',"If statement")
        local body = gStatements(inp,{['end']=true,['else']=true,['elseif']=true})  
        return {'if',test,{'%frame',body},gElse(inp)}
      end
      error()
    end

    function gStatements(inp,stop)
      local progn = {'%progn'}; stop=stop or {}; stop[';']=true; progn[2] = gStatement(inp,stop)
      while inp.peek().value == ';' do
        inp.next(); progn[#progn+1] = gStatement(inp,stop)
      end
      return #progn > 2 and progn or progn[2]
    end

    local statement={['while']=true,['repeat']=true,['if']=true,['local']=true,['begin']=true,['for']=true}
    local function gRule(inp)
      if statement[inp.peek().value] then return gStatements(inp) end
      local e = gExpr(inp,{['=>']=true,[';']=true})
      if inp.peek().value=='=>' then inp.next()
        return {'=>',e,gStatements(inp)}
      elseif inp.peek().value==';' then inp.next()
        local s = gStatements(inp)
        return {'%progn',e,s}
      else return e end
    end

    function self.parse(str)
      local tokens = mkStream(tokenize(str))
      --for i,v in ipairs(tokens.stream) do print(v.type, v.value, v.from, v.to) end
      local stat,res = pcall(function() return self.postParse(gRule(tokens)) end)
      if not stat then local t=tokens.last() error(string.format("Parser error char %s ('%s') in expression '%s' (%s)",t.from+1,str:sub(t.from+1,t.to),str,res)) end
      return res
    end

    return self
  end

---------- Event Script Compiler --------------------------------------
  function makeEventScriptCompiler(parser)
    local self,comp,gensym,isVar,isGlob={ parser=parser },{},Util.gensym,Util.isVar,Util.isGlob
    local function mkOp(o) return o end
    local POP = {mkOp('%pop'),0}

    local function compT(e,ops)
      if type(e) == 'table' then
        local ef = e[1]
        if comp[ef] then comp[ef](e,ops)
        else for i=2,#e do compT(e[i],ops) end ops[#ops+1] = {mkOp(e[1]),#e-1} end -- built-in fun
      else 
        ops[#ops+1]={mkOp('%push'),0,e} -- constants etc
      end
    end

    comp['%quote'] = function(e,ops) ops[#ops+1] = {mkOp('%push'),0,e[2]} end
    comp['%var'] = function(e,ops) ops[#ops+1] = {mkOp('%var'),0,e[2],e[3]} end
    comp['%addr'] = function(e,ops) ops[#ops+1] = {mkOp('%addr'),0,e[2]} end
    comp['%jmp'] = function(e,ops) ops[#ops+1] = {mkOp('%jmp'),0,e[2]} end
    comp['%frame'] = function(e,ops) ops[#ops+1] = {mkOp('%frame'),0} compT(e[2],ops) ops[#ops+1] = {mkOp('%unframe'),0} end  
    comp['%eventmatch'] = function(e,ops) ops[#ops+1] = {mkOp('%eventmatch'),0,e[2],e[3]} end
    comp['setList'] = function(e,ops) compT(e[3],ops); ops[#ops+1]={mkOp('%setlist'),1,e[2]} end
    comp['%set'] = function(e,ops)
      if e[2]=='%var' then
        if type(e[5])~='table' then ops[#ops+1] = {mkOp('%setvar'),0,e[3],e[4],e[5]} 
        else compT(e[5],ops); ops[#ops+1] = {mkOp('%setvar'),1,e[3],e[4]} end
      else
        local args,n = {},1;
        if type(e[4])~='table' then args[2]={e[4]} else args[2]=false compT(e[4],ops) n=n+1 end
        if type(e[5])~='table' then args[1]={e[5]} else args[1]=false compT(e[5],ops) n=n+1 end
        compT(e[3],ops)
        ops[#ops+1] = {mkOp('%set'..e[2]:sub(2)),n,table.unpack(args)} 
      end
    end
    comp['%aref'] = function(e,ops)
      compT(e[2],ops) 
      if type(e[3])~='table' then ops[#ops+1] = {mkOp('%aref'),1,e[3]} 
      else compT(e[3],ops); ops[#ops+1] = {mkOp('%aref'),2} end
    end
    comp['%prop'] = function(e,ops)
      _assert(type(e[3])=='string',"non constant property '%s'",function() return json.encode(e[3]) end)
      compT(e[2],ops); ops[#ops+1] = {mkOp('%prop'),1,e[3]} 
    end
    comp['%table'] = function(e,ops) local keys={}
      for key,val in pairs(e[2]) do keys[#keys+1] = key; compT(val,ops) end
      ops[#ops+1]={mkOp('%table'),#keys,keys}
    end
    comp['%and'] = function(e,ops) 
      compT(e[2],ops)
      local o1,z = {mkOp('%ifnskip'),0,0}
      ops[#ops+1] = o1 -- true skip 
      z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1
    end
    comp['%or'] = function(e,ops)  
      compT(e[2],ops)
      local o1,z = {mkOp('%ifskip'),0,0}
      ops[#ops+1] = o1 -- true skip 
      z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1;
    end
    comp['%inc'] = function(e,ops) 
      if tonumber(e[3]) then ops[#ops+1] = {mkOp('%inc'..e[4]),0,e[2][2],e[2][3],e[3]}
      else compT(e[3],ops) ops[#ops+1] = {mkOp('%inc'..e[4]),1,e[2][2],e[2][3]} end 
    end
    comp['%progn'] = function(e,ops)
      if #e == 2 then compT(e[2],ops) 
      elseif #e > 2 then for i=2,#e-1 do compT(e[i],ops); ops[#ops+1]=POP end compT(e[#e],ops) end
    end
    comp['%local'] = function(e,ops)
      for _,e1 in ipairs(e[3]) do compT(e1[1],ops) end
      ops[#ops+1]={mkOp('%local'),#e[3],e[2]}
    end
    comp['%while'] = function(e,ops) -- lbl1, test, infskip lbl2, body, jmp lbl1, lbl2
      local test,body,lbl1,cp=e[2],e[3],gensym('LBL1')
      local jmp={mkOp('%ifnskip'),0,nil,true}
      ops[#ops+1] = {'%addr',0,lbl1}; ops[#ops+1] = POP
      compT(test,ops); ops[#ops+1]=jmp; cp=#ops
      compT(body,ops); ops[#ops+1]=POP; ops[#ops+1]={mkOp('%jmp'),0,lbl1}
      jmp[3]=#ops+1-cp
    end
    comp['%repeat'] = function(e,ops) -- -- lbl1, body, test, infskip lbl1
      local body,test,z=e[2],e[3],#ops
      compT(body,ops); ops[#ops+1]=POP; compT(test,ops)
      ops[#ops+1] = {mkOp('%ifnskip'),0,z-#ops,true}
    end

    function self.compile(src,log) 
      local code,res=type(src)=='string' and self.parser.parse(src) or src,{}
      if log and log.code then print(json.encode(code)) end
      compT(code,res) 
      if log and log.code then if ScriptEngine then  ScriptEngine.dump(res) end end
      return res 
    end
    function self.compile2(code) local res={}; compT(code,res); return res end
    return self
  end

---------- Event Script RunTime --------------------------------------
  function makeEventScriptRuntime()
    local self,instr={},{}
    local format = string.format
    local function safeEncode(e) local stat,res = pcall(function() return tojson(e) end) return stat and res or tostring(e) end
    local toTime,midnight,map,mkStack,copy,coerce,isEvent=Util.toTime,Util.midnight,Util.map,Util.mkStack,Util.copy,Event.coerce,Event.isEvent
    local _vars,triggerVar = Util._vars,Util.triggerVar

    local function getVarRec(var,locs) return locs[var] or locs._next and getVarRec(var,locs._next) end
    local function getVar(var,env) local v = getVarRec(var,env.locals); env._lastR = var
      if v then return v[1]
      elseif _vars[var] then return _vars[var][1]
      elseif _ENV[var]~=nil then return _ENV[var] end
    end
    local function setVar(var,val,env) local v = getVarRec(var,env.locals)
      if v then v[1] = val
      else
        local oldVal 
        if _vars[var] then oldVal=_vars[var][1]; _vars[var][1] = val else _vars[var]={val} end
        if triggerVar(var) and oldVal ~= val then Event.post({type='variable', name=var, value=val}) end
        --elseif _ENV[var] then return _ENV[var] end -- allow for setting Lua globals
      end
      return val 
    end

    -- Primitives
    instr['%pop'] = function(s) s.pop() end
    instr['%push'] = function(s,n,e,i) s.push(i[3]) end
    instr['%ifnskip'] = function(s,n,e,i) if not s.peek() then e.cp=e.cp+i[3]-1; end if i[4] then s.pop() end end
    instr['%ifskip'] = function(s,n,e,i) if s.peek() then e.cp=e.cp+i[3]-1; end if i[4] then s.pop() end end
    instr['%addr'] = function(s,n,e,i) s.push(i[3]) end
    instr['%frame'] = function(s,n,e,i)  e.locals = {_next=e.locals} end
    instr['%unframe'] = function(s,n,e,i)  e.locals = e.locals._next end
    instr['%jmp'] = function(s,n,e,i) local addr,c,p = i[3],e.code,i[4]
      if p then  e.cp=p-1 return end  -- First time we search for the label and cache the position
      for k=1,#c do if c[k][1]=='%addr' and c[k][3]==addr then i[4]=k e.cp=k-1 return end end 
      error({"jump to bad address:"..addr}) 
    end
    instr['%table'] = function(s,n,e,i) local k,t = i[3],{} for j=n,1,-1 do t[k[j]] = s.pop() end s.push(t) end
    local function getArg(s,e) if e then return e[1] else return s.pop() end end
    instr['%aref'] = function(s,n,e,i) local k,tab 
      if n==1 then k,tab=i[3],s.pop() else k,tab=s.pop(),s.pop() end
      _assert(type(tab)=='table',"attempting to index non table with key:'%s'",k); e._lastR = k
      s.push(tab[k])
    end
    instr['%setaref'] = function(s,n,e,i) local r,v,k = s.pop(),getArg(s,i[3]),getArg(s,i[4])
      _assertf(type(r)=='table',"trying to set non-table value '%s'",function() return json.encode(r) end)
      r[k]= v; s.push(v) 
    end
    local _marshalBool={['true']=true,['True']=true,['TRUE']=true,['false']=false,['False']=false,['FALSE']=false}

    local function marshallFrom(v) 
      if not _MARSHALL then return v elseif v==nil then return v end
      local fc = v:sub(1,1)
      if fc == '[' or fc == '{' then local s,t = pcall(json.decode,v); if s then return t end end
      if tonumber(v) then return tonumber(v)
      elseif _marshalBool[v ]~=nil then return _marshalBool[v ] end
      local s,t = pcall(toTime,v); return s and t or v 
    end
    local function marshallTo(v) 
      if not _MARSHALL then return v end
      if type(v)=='table' then return safeEncode(v) else return tostring(v) end
    end
    local getVarFs = { script=getVar, glob=function(n,e) return marshallFrom(fibaro.getGlobalVariable(n)) end }
    local setVarFs = { script=setVar, glob=function(n,v,e) fibaro.setGlobalVariable(n,marshallTo(v)) return v end }
    instr['%var'] = function(s,n,e,i) s.push(getVarFs[i[4]](i[3],e)) end
    instr['%setvar'] = function(s,n,e,i) if n==1 then setVarFs[i[4]](i[3],s.peek(),e) else s.push(setVarFs[i[4]](i[3],i[5],e)) end end
    instr['%local'] = function(s,n,e,i) local vn,ve = i[3],s.lift(n); e.locals = e.locals or {}
      local i,x=1; for _,v in ipairs(vn) do x=ve[i]; e.locals[v]={ve[i]}; i=i+1 end
      s.push(x) 
    end
    instr['%setlist'] = function(s,n,e,i) 
      local vars,arg,r = i[3],s.pop() 
      for i,v in ipairs(vars) do r=setVarFs[v[3]](v[2],arg[i],e) end 
      s.push(r) 
    end
    instr['trace'] = function(s,n,e) _traceInstrs=s.peek() end
    instr['pack'] = function(s,n,e) local res=s.get(1); s.pop(); s.push(res) end
    instr['env'] = function(s,n,e) s.push(e) end
    local function resume(co,e)
      local res = {coroutine.resume(co)}
      if res[1]==true then
        if coroutine.status(co)=='dead' then e.log.cont(select(2,table.unpack(res))) end
      else error(res[2]) end
    end
    local function handleCall(s,e,fun,args)
      local res = table.pack(fun(table.unpack(args)))
      if type(res[1])=='table' and res[1]['<cont>'] then
        local co = e.co
        setTimeout(function() res[1]['<cont>'](function(...) local r=table.pack(...); s.push(r[1]); s.set(1,r); resume(co,e) end) end,0)
        return 'suspended',{}
      else s.push(res[1]) s.set(1,res) end
    end
    instr['%call'] = function(s,n,e,i) local fun = getVar(i[1] ,e); _assert(type(fun)=='function',"No such function:%s",i[1] or "nil")
      return handleCall(s,e,fun,s.lift(n))
    end
    instr['%calls'] = function(s,n,e,i) local args,fun = s.lift(n-1),s.pop(); _assert(type(fun)=='function',"No such function:%s",fun or "nil")
      return handleCall(s,e,fun,args)
    end
    instr['yield'] = function(s,n,e,i) local r = s.lift(n); s.push(nil); return 'suspended',r end
    instr['return'] = function(s,n,e,i) return 'dead',s.lift(n) end
    instr['wait'] = function(s,n,e,i) local t,co=s.pop(),e.co; t=t < os.time() and t or t-os.time(); s.push(t);
      setTimeout(function() resume(co,e) end,t*1000); return 'suspended',{}
    end
    instr['%not'] = function(s,n) s.push(not s.pop()) end
    instr['%neg'] = function(s,n) s.push(-tonumber(s.pop())) end
    instr['+'] = function(s,n) s.push(s.pop()+s.pop()) end
    instr['-'] = function(s,n) s.push(-s.pop()+s.pop()) end
    instr['*'] = function(s,n) s.push(s.pop()*s.pop()) end
    instr['/'] = function(s,n) local y,x=s.pop(),s.pop() s.push(x/y) end
    instr['%'] = function(s,n) local a,b=s.pop(),s.pop(); s.push(b % a) end
    instr['%inc+'] = function(s,n,e,i) local var,t,val=i[3],i[4] if n>0 then val=s.pop() else val=i[5] end 
    s.push(setVarFs[t](var,getVarFs[t](var,e)+val,e)) end
    instr['%inc-'] = function(s,n,e,i) local var,t,val=i[3],i[4]; if n>0 then val=s.pop() else val=i[5] end 
    s.push(setVarFs[t](var,getVarFs[t](var,e)-val,e)) end
    instr['%inc*'] = function(s,n,e,i) local var,t,val=i[3],i[4]; if n>0 then val=s.pop() else val=i[5] end
    s.push(setVarFs[t](var,getVarFs[t](var,e)*val,e)) end
    instr['>'] = function(s,n) local y,x=coerce(s.pop(),s.pop()) s.push(x>y) end
    instr['<'] = function(s,n) local y,x=coerce(s.pop(),s.pop()) s.push(x<y) end
    instr['>='] = function(s,n) local y,x=coerce(s.pop(),s.pop()) s.push(x>=y) end
    instr['<='] = function(s,n) local y,x=coerce(s.pop(),s.pop()) s.push(x<=y) end
    instr['~='] = function(s,n) s.push(tostring(s.pop())~=tostring(s.pop())) end
    instr['=='] = function(s,n) s.push(tostring(s.pop())==tostring(s.pop())) end

-- ER funs
    local getFuns,setFuns={},{}
    local _getFun = function(id,prop) return fibaro.get(id,prop) end
    do
      local function BN(x) return (type(x)=='boolean' and x and '1' or '0') or x end
      local get = _getFun
      local function on(id,prop) return BN(fibaro.get(id,prop)) > '0' end
      local function off(id,prop) return BN(fibaro.get(id,prop)) == '0' end
      local function last(id,prop) return os.time()-select(2,fibaro.get(id,prop)) end
      local function cce(id,prop,e) e=e.event; return e.type=='property' and e.propertyName=='CentralSceneEvent' and e.deviceID==id and e.value or {} end
      local function ace(id,prop,e) e=e.event; return e.type=='property' and e.propertyName=='AccessControlEvent' and e.deviceID==id and e.value or {} end
      local function armed(id,prop) return fibaro.get(id,prop) == '1' end
      local function call(id,cmd) fibaro.call(id,cmd); return true end
      local function set(id,cmd,val) fibaro.call(id,cmd,val); return val end
      local function setArmed(id,cmd,val) fibaro.call(id,cmd,val and '1' or '0'); return val end
      local function set2(id,cmd,val) fibaro.call(id,cmd,table.unpack(val)); return val end
      local mapOr,mapAnd,mapF=Util.mapOr,Util.mapAnd,function(f,l,s) Util.mapF(f,l,s); return true end
      getFuns={
        value={get,'value',nil,true},bat={get,'batteryLevel',nil,true},power={get,'power',nil,true},
        isOn={on,'value',mapOr,true},isOff={off,'value',mapAnd,true},isAllOn={on,'value',mapAnd,true},isAnyOff={off,'value',mapOr,true},
        last={last,'value',nil,true},scene={get,'sceneActivation',nil,true},
        access={ace,'AccessControlEvent',nil,true},central={cce,'CentralSceneEvent',nil,true},
        safe={off,'value',mapAnd,true},breached={on,'value',mapOr,true},isOpen={on,'value',mapOr,true},isClosed={off,'value',mapAnd,true},
        lux={get,'value',nil,true},temp={get,'value',nil,true},on={call,'turnOn',mapF,true},off={call,'turnOff',mapF,true},
        open={call,'open',mapF,true},close={call,'close',mapF,true},stop={call,'stop',mapF,true},
        secure={call,'secure',mapF,false},unsecure={call,'unsecure',mapF,false},
        isSecure={on,'secured',mapOr,true},isUnsecure={off,'secured',mapAnd,true},
        name={function(id) return fibaro.getName(id) end,nil,nil,false},
        HTname={function(id) return Util.reverseVar(id) end,nil,nil,false},
        roomName={function(id) return fibaro.getRoomNameByDeviceID(id) end,nil,nil,false},
        trigger={function() return true end,'value',nil,true},time={get,'time',nil,true},armed={armed,'armed',mapOr,true},
        manual={function(id) return Event.lastManual(id) end,'value',nil,true},
        start={function(id) return fibaro.scene("execute",{id}) end,"",mapF,false},
        kill={function(id) return fibaro.scene("kill",{id}) end,"",mapF,false},
        toggle={call,'toggle',mapF,true},wake={call,'wakeUpDeadDevice',mapF,true},
        removeSchedule={call,'removeSchedule',mapF,true},retryScheduleSynchronization={call,'retryScheduleSynchronization',mapF,true},
        setAllSchedules={call,'setAllSchedules',mapF,true},
        dID={function(a,e) 
            if type(a)=='table' then
              local id = e.event and Util.getIDfromTrigger[e.event.type or ""](e.event)
              if id then for _,id2 in ipairs(a) do if id == id2 then return id end end end
            end
            return a
          end,'<nop>',nil,true}
      }
      getFuns.lock=getFuns.secure;getFuns.unlock=getFuns.unsecure;getFuns.isLocked=getFuns.isSecure;getFuns.isUnlocked=getFuns.isUnsecure -- Aliases
      setFuns={
        R={set,'setR'},G={set,'setG'},B={set,'setB'},W={set,'setW'},value={set,'setValue'},armed={setArmed,'setArmed'},
        time={set,'setTime'},power={set,'setPower'},targetLevel={set,'setTargetLevel'},interval={set,'setInterval'},
        mode={set,'setMode'},setpointMode={set,'setSetpointMode'},defaultPartyTime={set,'setDefaultPartyTime'},
        scheduleState={set,'setScheduleState'},color={set2,'setColor'},
        thermostatSetpoint={set2,'setThermostatSetpoint'},schedule={set2,'setSchedule'},dim={set2,'dim'},
        msg={set,'sendPush'},defemail={set,'sendDefinedEmailNotification'},btn={set,'pressButton'},
        email={function(id,cmd,val) local h,m = val:match("(.-):(.*)"); fibaro.call(id,'sendEmail',h,m) return val end,""},
        start={function(id,cmd,val) 
            if isEvent(val) then Event.postRemote(id,val) else fibaro.scene("execute",{id},val) return true end 
          end,""},
      }
      self.getFuns=getFuns
    end

    local function ID(id,i,l) 
      if tonumber(id)==nil then 
        error(format("bad deviceID '%s' for '%s' '%s'",id,i[1],tojson(l or i[4] or "").."?"),3) else return id
      end
    end
    instr['%prop'] = function(s,n,e,i) local id,f=s.pop(),getFuns[i[3]]
      if i[3]=='dID' then s.push(getFuns['dID'][1](id,e)) return end
      if not f then f={_getFun,i[3]} end
      if type(id)=='table' then s.push((f[3] or map)(function(id) return f[1](ID(id,i,e._lastR),f[2],e) end,id))
      else s.push(f[1](ID(id,i,e._lastR),f[2],e)) end
    end
    instr['%setprop'] = function(s,n,e,i) local id,val,prop=s.pop(),getArg(s,i[3]),getArg(s,i[4])
      local f = setFuns[prop] _assert(f,"bad property '%s'",prop or "") 
      if type(id)=='table' then Util.mapF(function(id) f[1](ID(id,i,e._lastR),f[2],val,e) end,id); s.push(true)
      else s.push(f[1](ID(id,i,e._lastR),f[2],val,e)) end
    end
    instr['%rule'] = function(s,n,e,i) local b,h=s.pop(),s.pop(); s.push(Rule.compRule({'=>',h,b,e.log},e)) end
    instr['log'] = function(s,n) s.push(Log(LOG.ULOG,table.unpack(s.lift(n)))) end
    instr['%logRule'] = function(s,n,e,i) local src,res = s.pop(),s.pop() 
      Debug(_debugFlags.rule or (_debugFlags.ruleTrue and res),"[%s]>>'%s'",tojson(res),src) s.push(res) 
    end
    instr['%setlabel'] = function(s,n,e,i) local id,v,lbl = s.pop(),getArg(s,i[3]),getArg(s,i[4])
      fibaro.call(ID(id,i),"setProperty",format("ui.%s.value",lbl),tostring(v)) s.push(v) 
    end
    instr['%setslider'] = instr['%setlabel'] 

-- ER funs
    local simpleFuns={num=tonumber,str=tostring,idname=Util.reverseVar,time=toTime,['type']=type,
      tjson=safeEncode,fjson=json.decode}
    for n,f in pairs(simpleFuns) do instr[n]=function(s,n,e,i) return s.push(f(s.pop())) end end

    instr['sunset']=function(s,n,e,i) s.push(toTime(fibaro.getValue(1,'sunsetHour'))) end
    instr['sunrise']=function(s,n,e,i) s.push(toTime(fibaro.getValue(1,'sunriseHour'))) end
    instr['midnight']=function(s,n,e,i) s.push(midnight()) end
    instr['dawn']=function(s,n,e,i) s.push(toTime(fibaro.getValue(1,'dawnHour'))) end
    instr['dusk']=function(s,n,e,i) s.push(toTime(fibaro.getValue(1,'duskHour'))) end
    instr['now']=function(s,n,e,i) s.push(os.time()-midnight()) end
    instr['wnum']=function(s,n,e,i) s.push(Util.getWeekNumber(os.time())) end
    instr['%today']=function(s,n,e,i) s.push(midnight()+s.pop()) end
    instr['%nexttime']=function(s,n,e,i) local t=s.pop()+midnight(); s.push(t >= os.time() and t or t+24*3600) end
    instr['%plustime']=function(s,n,e,i) s.push(os.time()+s.pop()) end
    instr['HM']=function(s,n,e,i) local t = s.pop(); s.push(os.date("%H:%M",t < os.time() and t+midnight() or t)) end  
    instr['HMS']=function(s,n,e,i) local t = s.pop(); s.push(os.date("%H:%M:%S",t < os.time() and t+midnight() or t)) end  
    instr['sign'] = function(s,n) s.push(tonumber(s.pop()) < 0 and -1 or 1) end
    instr['rnd'] = function(s,n) local ma,mi=s.pop(),n>1 and s.pop() or 1 s.push(math.random(mi,ma)) end
    instr['round'] = function(s,n) local v=s.pop(); s.push(math.floor(v+0.5)) end
    instr['sum'] = function(s,n) local m,res=s.pop(),0 for _,x in ipairs(m) do res=res+x end s.push(res) end 
    instr['average'] = function(s,n) local m,res=s.pop(),0 for _,x in ipairs(m) do res=res+x end s.push(res/#m) end 
    instr['size'] = function(s,n) s.push(#(s.pop())) end
    instr['min'] = function(s,n) s.push(math.min(table.unpack(type(s.peek())=='table' and s.pop() or s.lift(n)))) end
    instr['max'] = function(s,n) s.push(math.max(table.unpack(type(s.peek())=='table' and s.pop() or s.lift(n)))) end
    instr['sort'] = function(s,n) local a = type(s.peek())=='table' and s.pop() or s.lift(n); table.sort(a) s.push(a) end
    instr['match'] = function(s,n) local a,b=s.pop(),s.pop(); s.push(string.match(b,a)) end
    instr['osdate'] = function(s,n) local x,y = s.peek(n-1),(n>1 and s.pop() or nil) s.pop(); s.push(os.date(x,y)) end
    instr['ostime'] = function(s,n) s.push(os.time()) end
    instr['%daily'] = function(s,n,e) s.pop() s.push(true) end
    instr['%interv'] = function(s,n,e,i) local t = s.pop(); s.push(true) end
    instr['fmt'] = function(s,n) s.push(string.format(table.unpack(s.lift(n)))) end
    instr['label'] = function(s,n,e,i) local nm,id = s.pop(),s.pop() s.push(fibaro.getValue(ID(id,i),format("ui.%s.value",nm))) end
    instr['slider'] = instr['label']
    instr['redaily'] = function(s,n,e,i) s.push(Rule.restartDaily(s.pop())) end
    instr['eval'] = function(s,n) s.push(Rule.eval(s.pop(),{print=false})) end
    instr['global'] = function(s,n,e,i)  s.push(api.post("/globalVariables/",{name=s.pop()})) end  
    instr['listglobals'] = function(s,n,e,i) s.push(api.get("/globalVariables/")) end
    instr['deleteglobal'] = function(s,n,e,i) s.push(api.delete("/globalVariables/"..s.pop())) end
    instr['once'] = function(s,n,e,i) 
      if n==1 then local f; i[4],f = s.pop(),i[4]; s.push(not f and i[4]) 
      elseif n==2 then local f,g,e; e,i[4],f = s.pop(),s.pop(),i[4]; g=not f and i[4]; s.push(g) 
        if g then Event.cancel(i[5]) i[5]=Event.post(function() i[4]=nil end,e) end
      else local f; i[4],f=os.date("%x"),i[4] or ""; s.push(f ~= i[4]) end
    end
    instr['%always'] = function(s,n,e,i) local v = s.pop(n) s.push(v or true) end
    instr['enable'] = function(s,n,e,i) local t,g = s.pop(),false; if n==2 then g,t=t,s.pop() end s.push(Event.enable(t,g)) end
    instr['disable'] = function(s,n,e,i) s.push(Event.disable(s.pop())) end
    instr['post'] = function(s,n,ev) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end s.push(Event.post(e,t,ev.rule)) end
    instr['subscribe'] = function(s,n,ev) Event.subscribe(s.pop()) s.push(true) end
    instr['publish'] = function(s,n,ev) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end Event.publish(e,t) s.push(e) end
    instr['remote'] = function(s,n,ev) _assert(n==2,"Wrong number of args to 'remote/2'"); 
      local e,u=s.pop(),s.pop(); 
      Event.postRemote(u,e) 
      s.push(true) 
    end
    instr['cancel'] = function(s,n) Event.cancel(s.pop()) s.push(nil) end
    instr['add'] = function(s,n) local v,t=s.pop(),s.pop() table.insert(t,v) s.push(t) end
    instr['remove'] = function(s,n) local v,t=s.pop(),s.pop() table.remove(t,v) s.push(t) end
    instr['%betw'] = function(s,n) local t2,t1,now=s.pop(),s.pop(),os.time()-midnight()
      _assert(tonumber(t1) and tonumber(t2),"Bad arguments to between '...', '%s' '%s'",t1 or "nil", t2 or "nil")
      if t1<=t2 then s.push(t1 <= now and now <= t2) else s.push(now >= t1 or now <= t2) end 
    end
    instr['%eventmatch'] = function(s,n,e,i) 
      local ev,evp=i[4],i[3]; 
      local vs = Event._match(evp,e.event)
      if vs then for k,v in pairs(vs) do e.locals[k]={v} end end -- Uneccesary? Alread done in head matching.
      s.push(e.event and vs and ev or false) 
    end
    instr['again'] = function(s,n,e) 
      local v = n>0 and s.pop() or math.huge
      e.rule._again = (e.rule._again or 0)+1
      if v > e.rule._again then setTimeout(function() e.rule.start(e.rule._event) end,0) else e.rule._again,e.rule._event = nil,nil end
      s.push(e.rule._again or v)
    end
    instr['trueFor'] = function(s,n,e,i)
      local val,time = s.pop(),s.pop()
      e.rule._event = e.event
      local flags = i[5] or {}; i[5]=flags
      if val then
        if flags.expired then s.push(val); flags.expired=nil; return end
        if flags.timer then s.push(false); return end
        flags.timer = setTimeout(function() 
            --  Event._callTimerFun(function()
            flags.expired,flags.timer=true,nil; 
            e.rule.start(e.rule._event) 
            --      end)
          end,1000*time); 
        s.push(false); return
      else
        if flags.timer then flags.timer=clearTimeout(flags.timer) end
        s.push(false)
      end
    end

    function self.addInstr(name,fun) _assert(instr[name] == nil,"Instr already defined: %s",name) instr[name] = fun end

    self.instr = instr
    local function postTrace(i,args,stack,cp)
      local f,n = i[1],i[2]
      if not ({jmp=true,push=true,pop=true,addr=true,fn=true,table=true,})[f] then
        local p0,p1=3,1; while i[p0] do table.insert(args,p1,i[p0]) p1=p1+1 p0=p0+1 end
        args = format("%s(%s)=%s",f,safeEncode(args):sub(2,-2),safeEncode(stack.peek()))
        Log(LOG.LOG,"pc:%-3d sp:%-3d %s",cp,stack.size(),args)
      else
        Log(LOG.LOG,"pc:%-3d sp:%-3d [%s/%s%s]",cp,stack.size(),i[1],i[2],i[3] and ","..json.encode(i[3]) or "")
      end
    end

    function self.dump(code)
      code = code or {}
      for p = 1,#code do
        local i = code[p]
        Log(LOG.LOG,"%-3d:[%s/%s%s%s]",p,i[1],i[2] ,i[3] and ","..tojson(i[3]) or "",i[4] and ","..tojson(i[4]) or "")
      end
    end

    function self.listInstructions()
      local t={}
      print("User functions:")
      for f,_ in pairs(instr) do if f=="%" or f:sub(1,1)~='%' then t[#t+1]=f end end
      table.sort(t); for _,f in ipairs(t) do print(f) end
      print("Property functions:")
      t={}
      for f,_ in pairs(getFuns) do t[#t+1]="<ID>:"..f end 
      for f,_ in pairs(setFuns) do t[#t+1]="<ID>:"..f.."=.." end 
      table.sort(t); for _,f in ipairs(t) do print(f) end
    end

    function self.eval(env)
      local stack,code=env.stack or mkStack(),env.code
      local traceFlag = env.log and env.log.trace or _traceInstrs
      env.cp,env.env,env.src = env.cp or 1, env.env or {},env.src or ""
      local i,args
      local status,stat,res = pcall(function() 
          local stat,res
          while env.cp <= #code and stat==nil do
            i = code[env.cp]
            if traceFlag or _traceInstrs then 
              args = copy(stack.liftc(i[2]))
              stat,res=(instr[i[1]] or instr['%call'])(stack,i[2],env,i)
              postTrace(i,args,stack,env.cp) 
            else stat,res=(instr[i[1]] or instr['%call'])(stack,i[2],env,i) end
            env.cp = env.cp+1
          end --until env.cp > #code or stat
          return stat,res or {stack.pop()}
        end)
      if status then return stat,res
      else
        if isError(stat) then stat.src = stat.src or env.src; error(stat) end
        throwError{msg=format("Error executing instruction:'%s'",tojson(i)),err=stat,src=env.src,ctx=res}
      end
    end

    function self.eval2(env) env.cp=nil; env.locals = env.locals or {}; local _,res=self.eval(env) return res[1] end

    local function makeDateInstr(f)
      return function(s,n,e,i)
        local ts,cache = s.pop(),e.rule.cache
        if ts ~= i[5] then i[6] = Util.dateTest(f(ts)); i[5] = ts end -- cache fun
        s.push(i[6]())
      end
    end

    self.addInstr("date",makeDateInstr(function(s) return s end))             -- min,hour,days,month,wday
    self.addInstr("day",makeDateInstr(function(s) return "* * "..s end))      -- day('1-31'), day('1,3,5')
    self.addInstr("month",makeDateInstr(function(s) return "* * * "..s end))  -- month('jan-feb'), month('jan,mar,jun')
    self.addInstr("wday",makeDateInstr(function(s) return "* * * * "..s end)) -- wday('fri-sat'), wday('mon,tue,wed')

    return self
  end

--------- Event script Rule compiler ------------------------------------------
  function makeEventScriptRuleCompiler()
    local self = {}
    local HOURS24,CATCHUP,RULEFORMAT = 24*60*60,math.huge,"Rule:%s[%s]"
    local map,mapkl,getFuns,format,midnight,time2str=Util.map,Util.mapkl,ScriptEngine.getFuns,string.format,Util.midnight,Util.time2str
    local transform,copy,isGlob,isVar,triggerVar = Util.transform,Util.copy,Util.isGlob,Util.isVar,Util.triggerVar
    local _macros,dailysTab,rCounter= {},{},0
    local lblF=function(id,e) return {type='property', deviceID=id, propertyName=format("ui.%s.value",e[3])} end
    local triggFuns={label=lblF,slider=lblF}
    local function isTEvent(e) return type(e)=='table' and (e[1]=='%table' or e[1]=='%quote') and type(e[2])=='table' and e[2].type end

    local function ID(id,p) _assert(tonumber(id),"bad deviceID '%s' for '%s'",id,p or "") return id end
    local gtFuns = {
      ['%daily'] = function(e,s) s.dailys[#s.dailys+1 ]=ScriptCompiler.compile2(e[2]); s.dailyFlag=true end,
      ['%interv'] = function(e,s) s.scheds[#s.scheds+1 ] = ScriptCompiler.compile2(e[2]) end,
      ['%betw'] = function(e,s) 
        s.dailys[#s.dailys+1 ]=ScriptCompiler.compile2(e[2])
        s.dailys[#s.dailys+1 ]=ScriptCompiler.compile({'+',1,e[3]}) 
      end,
      ['%var'] = function(e,s) 
        if e[3]=='glob' then s.triggs[e[2] ] = {type='global', name=e[2]} 
        elseif triggerVar(e[2]) then s.triggs[e[2] ] = {type='variable', name=e[2]} end 
      end,
      ['%set'] = function(e,s) if isVar(e[2]) and triggerVar(e[2][2]) or isGlob(e[2]) then error("Can't assign variable in rule header") end end,
      ['%prop'] = function(e,s)
        local pn
        if not getFuns[e[3]] then pn = e[3] elseif not getFuns[e[3]][4] then return else pn = getFuns[e[3]][2] end
        local cv = ScriptCompiler.compile2(e[2])
        local v = ScriptEngine.eval2({code=cv})
        map(function(id) s.triggs[ID(id,e[3])..pn]={type='property', deviceID=id, propertyName=pn} end,type(v)=='table' and v or {v})
      end,
    }

    local function getTriggers(e)
      local s={triggs={},dailys={},scheds={},dailyFlag=false}
      local function traverse(e)
        if type(e) ~= 'table' then return e end
        if e[1]== '%eventmatch' then -- {'eventmatch',{'quote', ep,ce}} 
          local ep,ce = e[2],e[3]
          s.triggs[tojson(ce)] = ce  
        else
          Util.mapkk(traverse,e)
          if gtFuns[e[1]] then gtFuns[e[1]](e,s)
          elseif triggFuns[e[1]] then
            local cv = ScriptCompiler.compile2(e[2])
            local v = ScriptEngine.eval2({code=cv})
            map(function(id) s.triggs[id]=triggFuns[e[1]](id,e) end,type(v)=='table' and v or {v})
          end
        end
      end
      traverse(e); return mapkl(function(_,v) return v end,s.triggs),s.dailys,s.scheds,s.dailyFlag
    end

    function self.test(s) return {getTriggers(ScriptCompiler.parse(s))} end
    function self.define(name,fun) ScriptEngine.define(name,fun) end
    function self.addTrigger(name,instr,gt) ScriptEngine.addInstr(name,instr) triggFuns[name]=gt end

    local function compTimes(cs)
      local t1,t2=map(function(c) return ScriptEngine.eval2({code=c}) end,cs),{}
      if #t1>0 then transform(t1,function(t) t2[t]=true end) end
      return mapkl(function(k,_) return k end,t2)
    end

    local function remapEvents(obj)
      if isTEvent(obj) then 
        local ce = ScriptEngine.eval2({code=ScriptCompiler.compile(obj)})
        local ep = copy(ce); Event._compilePattern(ep)
        obj[1],obj[2],obj[3]='%eventmatch',ep,ce; 
--    elseif type(obj)=='table' and (obj[1]=='%and' or obj[1]=='%or' or obj[1]=='trueFor') then remapEvents(obj[2]); remapEvents(obj[3])  end
      elseif type(obj)=='table' then map(function(e) remapEvents(e) end,obj,2) end
    end

    local function trimRule(str)
      local str2 = str:sub(1,(str:find("\n") or math.min(#str,_RULELOGLENGTH or 80)+1)-1)
      if #str2 < #str then str2=str2.."..." end
      return str2
    end

    local coroutine = Util.coroutine
    function Event._compileActionHook(a,src,log)
      if type(a)=='string' or type(a)=='table' then        -- EventScript
        src = src or a
        local code = type(a)=='string' and ScriptCompiler.compile(src,log) or a
        local function run(env)
          env=env or {}; env.log = env.log or {}; env.log.cont=env.log.cont or function(...) return ... end
          env.locals = env.locals or {}
          local co = coroutine.create(code,src,env); env.co = co
          local res={coroutine.resume(co)}
          if res[1]==true then
            if coroutine.status(co)=='dead' then return env.log.cont(select(2,table.unpack(res))) end
          else error(res[1]) end
        end
        return run
      else return nil end
    end

    function self.compRule(e,env)
      local head,body,log,res,events,src,triggers2,sdaily = e[2],e[3],e[4],{},{},env.src or "<no src>",{}
      src=format(RULEFORMAT,rCounter+1,trimRule(src))
      remapEvents(head)  -- #event -> eventmatch
      local triggers,dailys,reps,dailyFlag = getTriggers(head)
      _assert(#triggers>0 or #dailys>0 or #reps>0, "no triggers found in header")
      --_assert(not(#dailys>0 and #reps>0), "can't have @daily and @@interval rules together in header")
      local code = ScriptCompiler.compile({'%and',(_debugFlags.rule or _debugFlags.ruleTrue) and {'%logRule',head,src} or head,body})
      local action = Event._compileAction(code,src,env.log)
      if #reps>0 then -- @@interval rules
        local event,env={type=Util.gensym("INTERV")},{code=reps[1]}
        events[#events+1] = Event.event(event,action,src)
        event._sh=true
        local timeVal,skip = nil,ScriptEngine.eval2(env)
        local function interval()
          timeVal = timeVal or os.time()
          Event.post(event)
          timeVal = timeVal+math.abs(ScriptEngine.eval2(env))
          setTimeout(interval,1000*(timeVal-os.time()))
        end
        setTimeout(interval,1000*(skip < 0 and -skip or 0))
      else
        if #dailys > 0 then -- daily rules
          local event,timers={type=Util.gensym("DAILY"),_sh=true},{}
          sdaily={dailys=dailys,event=event,timers=timers}
          dailysTab[#dailysTab+1] = sdaily
          events[#events+1]=Event.event(event,action,src)
          self.recalcDailys({dailys=sdaily,src=src},true)
          local reaction = function() self.recalcDailys(res) end
          for _,tr in ipairs(triggers) do -- Add triggers to reschedule dailys when variables change...
            if tr.type=='global' then Event.event(tr,reaction,{doc=src})  end
          end
        end
        if not dailyFlag and #triggers > 0 then -- id/glob trigger or events
          for _,tr in ipairs(triggers) do 
            if tr.propertyName~='<nop>' then events[#events+1]=Event.event(tr,action,src) triggers2[#triggers2+1]=tr end
          end
        end
      end
      res=#events>1 and Event.comboEvent(src,action,events,src) or events[1]
      res.dailys = sdaily
      if sdaily then sdaily.rule=res end
      res.print = function()
        Util.map(function(r) Log(LOG.LOG,"Interval(%s) =>...",time2str(r)) end,compTimes(reps)) 
        Util.map(function(d) Log(LOG.LOG,"Daily(%s) =>...",d==CATCHUP and "catchup" or time2str(d)) end,compTimes(dailys)) 
        Util.map(function(tr) Log(LOG.LOG,"Trigger(%s) =>...",tojson(tr)) end,triggers2)
      end
      rCounter=rCounter+1
      return res
    end

-- context = {log=<bool>, level=<int>, line=<int>, doc=<str>, trigg=<bool>, enable=<bool>}
    function self.eval(escript,log)
      if log == nil then log = {} elseif log==true then log={print=true} end
      if log.print==nil then log.print=true end
      local status,res,ctx
      status, res = pcall(function() 
          local expr = self.macroSubs(escript)
          if not log.cont then 
            log.cont=function(res)
              log.cont=nil
              local name,r
              if not log.print then return res end
              if Event.isRule(res) then name,r=res.src,"OK" else name,r=escript,res end
              Log(LOG.LOG,"%s = %s",name,r or "nil") 
              return res
            end
          end
          local f = Event._compileAction(expr,nil,log)
          return f({log=log,rule={cache={}}})
        end)
      if not status then 
        if not isError(res) then res={ERR=true,ctx=ctx,src=escript,err=res} end
        Log(LOG.ERROR,"Error in '%s': %s",res and res.src or "rule",res.err)
        if res.ctx then Log(LOG.ERROR,"\n%s",res.ctx) end
        error(res.err)
      else return res end
    end

    function self.load(rules,log)
      local function splitRules(rules)
        local lines,cl,pb,cline = {},math.huge,false,""
        if not rules:match("([^%c]*)\r?\n") then return {rules} end
        rules:gsub("([^%c]*)\r?\n?",function(p) 
            if p:match("^%s*---") then return end
            local s,l = p:match("^(%s*)(.*)")
            if l=="" then cl = math.huge return end
            if #s > cl then cline=cline.." "..l cl = #s pb = true
            elseif #s == cl and pb then cline=cline.." "..l
            else if cline~="" then lines[#lines+1]=cline end cline=l cl=#s pb = false end
          end)
        lines[#lines+1]=cline
        return lines
      end
      map(function(r) self.eval(r,log) end,splitRules(rules))
    end

    function self.macro(name,str) _macros['%$'..name..'%$'] = str end
    function self.macroSubs(str) for m,s in pairs(_macros) do str = str:gsub(m,s) end return str end

    function self.recalcDailys(r,catch)
      if r==nil and catch==nil then
        for _,d in ipairs(dailysTab) do self.recalcDailys(d.rule) end
        return
      end
      if not r.dailys then return end
      local dailys,newTimers,oldTimers,max = r.dailys,{},r.dailys.timers,math.max
      for _,t in ipairs(oldTimers) do Event.cancel(t[2]) end
      dailys.timers = newTimers
      local times,m,ot,catchup1,catchup2 = compTimes(dailys.dailys),midnight(),os.time()
      for i,t in ipairs(times) do _assert(tonumber(t),"@time not a number:%s",t)
        local oldT = oldTimers[i] and oldTimers[i][1]
        if t ~= CATCHUP then
          if _MIDNIGHTADJUST and t==HOURS24 then t=t-1 end
          if t+m >= ot then 
            Debug(oldT ~= t and _debugFlags.dailys,"Rescheduling daily %s for %s",r.src or "",os.date("%c",t+m)); 
            newTimers[#newTimers+1]={t,Event.post(dailys.event,max(os.time(),t+m),r.src)}
          else catchup1=true end
        else catchup2 = true end
      end
      if catch and catchup2 and catchup1 then Log(LOG.LOG,"Catching up:%s",r.src); Event.post(dailys.event) end
      return r
    end

    -- Scheduler that every night posts 'daily' rules
    Util.defvar('dayname',os.date("%a"))
    Event.event({type='%MIDNIGHT'},function(env) 
        Util.defvar('dayname',os.date("*t").wday)
        for _,d in ipairs(dailysTab) do self.recalcDailys(d.rule) end 
        Event.post(env.event,"n/00:00")
      end)
    Event.post({type='%MIDNIGHT',_sh=true},"n/00:00")
    return self
  end
--- SceneActivation constants
  Util.defvar('S1',Util.S1)
  Util.defvar('S2',Util.S2)
  Util.defvar('catch',math.huge)
  Util.defvar("defvars",Util.defvars)
  Util.defvar("mapvars",Util.reverseMapDef)
  
  if makeEventScriptParser then ScriptParser = makeEventScriptParser() end
  if makeEventScriptCompiler then ScriptCompiler = makeEventScriptCompiler(ScriptParser) end
  if makeEventScriptRuntime then ScriptEngine = makeEventScriptRuntime() end
  if makeEventScriptRuleCompiler then 
    Rule = makeEventScriptRuleCompiler() 
    Log(LOG.SYS,"Setting up EventScript support..")
  end
end
-------- End EventScript4 ------------------