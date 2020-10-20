--[[
     LuaLua
     Copyright (c) 2019 Jan Gabrielsson
     Email: jan@gabrielsson.com
     MIT License
--]]

--[[
chunk ::= block
block ::= {stat} [retstat]
stat ::=  ‘;’ | 
varlist ‘=’ explist | 
functioncall | 
label |          -- NOT IMPLEMENTED
break | 
goto Name |      -- NOT IMPLEMENTED
do block end | 
while exp do block end | 
repeat block until exp | 
if exp then block {elseif exp then block} [else block] end | 
for Name ‘=’ exp ‘,’ exp [‘,’ exp] do block end | 
for namelist in explist do block end | 
function funcname funcbody | 
local function Name funcbody | 
local namelist [‘=’ explist] 
retstat ::= return [explist] [‘;’]
label ::= ‘::’ Name ‘::’
funcname ::= Name {‘.’ Name} [‘:’ Name]
varlist ::= var {‘,’ var}
var ::=  Name | prefixexp ‘[’ exp ‘]’ | prefixexp ‘.’ Name 
namelist ::= Name {‘,’ Name}
explist ::= exp {‘,’ exp}
exp ::=  nil | false | true | Numeral | LiteralString | ‘...’ | functiondef | 
  prefixexp | tableconstructor | exp binop exp | unop exp 
prefixexp ::= var | functioncall | ‘(’ exp ‘)’
functioncall ::=  prefixexp args | prefixexp ‘:’ Name args 
args ::=  ‘(’ [explist] ‘)’ | tableconstructor | LiteralString 
functiondef ::= function funcbody
funcbody ::= ‘(’ [parlist] ‘)’ block end
parlist ::= namelist [‘,’ ‘...’] | ‘...’
tableconstructor ::= ‘{’ [fieldlist] ‘}’ 
fieldlist ::= field {fieldsep field} [fieldsep]
field ::= ‘[’ exp ‘]’ ‘=’ exp | Name ‘=’ exp | exp
fieldsep ::= ‘,’ | ‘;’
binop ::=  ‘+’ | ‘-’ | ‘*’ | ‘/’ | ‘//’ | ‘^’ | ‘%’ | 
  ‘&’ | ‘~’ | ‘|’ | ‘>>’ | ‘<<’ | ‘..’ | 
  ‘<’ | ‘<=’ | ‘>’ | ‘>=’ | ‘==’ | ‘~=’ | 
  and | or
unop ::= ‘-’ | not | ‘#’ | ‘~’
--]]

Toolbox_Module = Toolbox_Module or {}

Toolbox_Module.LuaParser ={
  name = "Lua parser",
  author = "jan@gabrielsson.com",
  version = "0.3"
}

function Toolbox_Module.LuaParser.init(self,args)
  local EVENTSCRIPT = args.EventScript
  local mTokens
  local format = string.format
  local function assert(t,str) if not t then error({err=str,token=mTokens.last()}) end end
  local function mkError(...) error({err=format(...),token=mTokens.last()},3) end
  local lineNr = 1
  table.maxn = table.maxn or function(t) return #t end

  local function mkStream(tab)
    local p,self=0,{ stream=tab, eof={type='eof', value='', from=tab[#tab].from, to=tab[#tab].to} }
    function self.next() p=p+1 return p<=#tab and tab[p] or self.eof end
    function self.last() return tab[p] or self.eof end
    function self.peek(n) return tab[p+(n or 1)] or self.eof end
    function self.match(t) local v=self.next(); assert(v.type==t,"Expected:"..t); return v.value end
    function self.matchA(t) local v=self.next(); assert(v.type==t,"Expected:"..t); return v end
    function self.test(t) local v=self.peek(); if v.type==t then self.next(); return true else return false end end
    function self.back(t) p=p-1 end
    return self
  end
  local function mkStack()
    local p,st,self=0,{},{}
    function self.push(v) p=p+1 st[p]=v end
    function self.pop(n) n = n or 1; p=p-n; return st[p+n] end
    function self.popn(n,v) v = v or {}; if n > 0 then local p = self.pop(); self.popn(n-1,v); v[#v+1]=p end return v end 
    function self.peek(n) return st[p-(n or 0)] end
    function self.isEmpty() return p<=0 end
    function self.size() return p end    
    function self.dump() for i=1,p do print(json.encode(st[i])) end end
    function self.clear() p,st=0,{} end
    return self
  end 

  local patterns,source,cursor,tokens = {}
  local ptabs = {}

  local function token(idp,pattern, createFn, logFn)
    pattern = "^"..pattern
    local f = function ()
      local res = {string.find(source, pattern)}
      if res[1] then
        if createFn then
          local token = createFn(select(3,table.unpack(res)))
          token.from, token.to,token.line = cursor+1, cursor+res[2],lineNr
          --print(json.encode(token))
          table.insert(tokens, token)
        end
        if logFn then 
          logFn(res[3]) 
        end
        source = string.sub(source, res[2]+1)
        cursor = cursor + res[2]
        return true
      end
    end
    for i=1,#idp do 
      local b = idp:byte(i)
      local v = ptabs[b] or {}
      ptabs[b]=v; v[#v+1]=f
    end
  end

  local specT={['(']=true,[')']=true,['{']=true,['}']=true,['[']=true,[']']=true,[',']=true,['.']=true,['=']=true,[';']=true,[':']=true,}
  local opT={['and']=true,['or']=true,['not']=true,}
  local reservedT={
    ['if']=true,['else']=true,['then']=true,['elseif']=true,['while']=true,['repeat']=true,['local']=true,['for']=true,['in']=true,
    ['do']=true,['until']=true,['end']=true,['return']=true,['true']=true,['false']=true,['function']=true,['nil']=true,['break']=true,
  }

  if EVENTSCRIPT then
    reservedT['STARTRULE']=true
    reservedT['ENDRULE']=true
  end

  local function TABEsc(str) return str:gsub("\\x(%x%x)",function(s) return string.char(tonumber(s,16)) end) end
  token(" \t\r","([ \t\r]+)")
  token("\n","(\n[\r\t ]*)",nil,function(str) cursor = -1; lineNr=lineNr+1 end)
  token("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_","([A-Za-z_][%w_]*)", function (w) 
      if reservedT[w] then return {type=w, value=w}
      elseif opT[w] then return {type='operator', value = w}
      else return {type='Name', value=w} end
    end)
  token(".","(%.%.%.?)",function(op) return {type=op=='..' and 'operator' or op, value=op} end)
  if EVENTSCRIPT then
    token("0123456789","(%d%d):(%d%d):?(%d*)", function (h,m,s) 
        return {type="number", value = 3600*tonumber(h)+60*tonumber(m)+(tonumber(s) or 0)} 
      end)
  end
  token("0123456789","(%d+%.%d+)", function (d) return {type="number", value=tonumber(d)} end)
  token("0123456789","(%d+)", function (d) return {type="number", value=tonumber(d)} end)
  token("\"",'"([^"]*)"', 
    function (s) return {type="string", value=TABEsc(s)} 
    end)
  token( "\'" , "'([^']*)'", function (s) return { type="string", value=TABEsc(s) } end )
  token("-","%-%-%[%[(.-)%-%-%]%]")
  token("[","%[%[(.-)%]%]", function (s) return {type="string", value=s} end)
  token("-","(%-%-.-\n)")
  token("-","(%-%-.*)")
  if EVENTSCRIPT then
    token("#@$=<>!+.-*&|/%^~;:","([#@%$=<>!+%.%-*&|/%^~;:][#@=<>&|:]?)", 
      function (op) return op=='=>' and {type=op,value=op} or {type= specT[op] and op or "operator", value=op} 
    end)
  else
    token("#@$=<>!+.-*&|/%^~;:","([#@%$=<>!+%.%-*&|/%^~;:][=<>&|:]?)", function (op) return {type= specT[op] and op or "operator", value=op} end)
  end
  token("[]{}(),#%","([{}%(%),%[%]#%%])", function (op) return {type=specT[op] and op or "operator", value=op} end)

  local function dispatch() 
    local v = ptabs[source:byte(1)]
    if v then
      for i=1,#v do if v[i]() then return true end end
    end
  end

  local ESCTab = {['\"'] = "22", ['\''] = "27", ['t'] = "09", ['n'] = "0A", ['r'] = "0D", }
  local function tokenize(src)
    local lineNr = 1
--    local t1 = os.clock()
    src = src:gsub('\\([\"t\'nr])',function(c) return "\\x"..ESCTab[c] end)
    source, tokens, cursor = src, {}, 0
    while #source>0 and dispatch() do end
    if #source > 0 then
      print("Parser failed at " .. source) 
    end
--      print("Time:"..os.clock()-t1)
    return tokens
  end

  local function copyt(t) local res={}; for _,v in ipairs(t) do res[v]=true end return res end -- shallow copying

  local function addVarsToCtx(varList,ctx)
    ctx.l = ctx.l or {}
    for _,v in ipairs(varList) do if v[1]=='var' then ctx.l[v[2]]=true end end
  end

  local gram = {}

  local opers = {
    ['not']={12,1},['#']={12,1},['%neg']={12,1},['%nor']={12,1},['^']={13,2},
    ['+']={8,2}, ['-']={8,2}, ['*']={11,2}, ['/']={11,2}, ['//']={11,2},['%']={11,2},
    ['..']={7,2},
    ['|']={3,2},['~']={4,2},['&']={5,2},['<<']={6,2},['>>']={6,2},
    ['<']={2,2}, ['<=']={2,2}, ['>']={2,2}, ['>=']={2,2}, ['==']={2,2}, ['~=']={2,2},
    ['and']={1,2}, ['or']={0,2}
  }

  if EVENTSCRIPT then
    opers['@']={7,1}
    opers['@@']={7,1}
    opers['$']={13,1}
    opers['##']={13,1}
  end

  local function apply(t,st) return st.push(st.popn(opers[t.value][2],{t.value})) end
  local _samePrio = {['.']=true,[':']=true}
  local function lessp(t1,t2) 
    local v1,v2 = t1.value,t2.value
    if v1==':' and v2=='.' then return true 
    elseif v1=='=' then v1='/' end
    return v1==v2 and _samePrio[v1] or opers[v1][1] <= opers[v2][1]  -- ToDo, '...' and '^' should be right associative! 
  end

  local function makeVar(name,ctx)
    while ctx do if ctx.l and ctx.l[name] then return {'var',name} else ctx=ctx.n end end
    return {'glob', name}
  end
  local NIL = "%%N".."IL%%"
  local PREFIXTKNS = {['.']=true, ['(']=true, ['[']=true, [':']=true, ['{']=true}

  local pExpr = {
    ['false']=function(inp,st,ops,t,pt,ctx) inp.next(); st.push(false) end,
    ['true']=function(inp,st,ops,t,pt,ctx) inp.next(); st.push(true) end,
--    ['nil']=function(inp,st,ops,t,pt,ctx) inp.next(); st.push(nil) end,
    ['nil']=function(inp,st,ops,t,pt,ctx) inp.next(); st.push(NIL) end,
    ['number']=function(inp,st,ops,t,pt,ctx) inp.next(); st.push(t.value) end,
    ['string']=function(inp,st,ops,t,pt,ctx) inp.next(); st.push(t.value) end,
    ['function']=function(inp,st,ops,t,pt,ctx) 
      inp.next(); 
      local args,varargs,body = gram.funcBody(inp,ctx)
      st.push({'function','expr','fun',"<non>",args,varargs,body})
    end,
    ['{']=function(inp,st,ops,t,pt,ctx) st.push(gram.tableConstructor(inp,ctx)) t.type='}' end,
    ['...']=function(inp,st,ops,t,pt,ctx) inp.next(); st.push({'vararg'}) end,
    ['(']=function(inp,st,ops,t,pt,ctx) 
      inp.next(); 
      local expr = gram.expr(inp,ctx) 
      inp.match(')')
      if PREFIXTKNS[inp.peek().type] then st.push(gram.prefixExp(inp,expr,ctx)) else st.push(expr) end
    end,
    ['Name']=function(inp,st,ops,t,pt,ctx) 
      inp.next();
      local p,v = inp.peek(),makeVar(t.value,ctx)
      if PREFIXTKNS[p.type] then st.push(gram.prefixExp(inp,v,ctx)) else st.push(v) end
    end,
    ['operator']=function(inp,st,ops,t,pt,ctx) 
      if opers[t.value] then
        if t.value == '-' and not(pt.type == 'Name' or pt.type == 'number' or pt.type == '(') then t.value='%neg' end
        while ops.peek() and lessp(t,ops.peek()) do apply(ops.pop(),st) end
        ops.push(t)
        inp.next()
      else mkError("Bad operator '%s'",t.value) end
    end
  }

  local eStop = {['end']=true,[',']=true,[';']=true,['=']=true,[')']=true,[']']=true,['}']=true,}
  for k,v in pairs(reservedT) do eStop[k]=v end
  eStop['true']=nil; eStop['false']=nil; eStop['nil']=nil; eStop['function']=nil
  function gram.expr(inp,ctx)
    local st,ops,t,pt=mkStack(),mkStack(),{type='<START>',value='<START>'}
    while true do
      t,pt = inp.peek(),t
      if t.type=='eof' or eStop and eStop[t.type] then break end
      if not (t.type=='{' and pt.type=='<START>') then
        if pt.type=='{' or t.type~='operator' and pt.type~='<START>' and pt.type~='operator' then break end
      end
      pExpr[t.type](inp,st,ops,t,pt,ctx)
    end
    while not ops.isEmpty() do apply(ops.pop(),st) end
    --st.dump()
    return st.pop()
  end

--[[ My rewrite of the rules...
afterpref ::= '.' prefixexp
afterpref ::= '[' exp ']' afterpref
afterpref ::= '(' args ')' afterpref
afterpref ::= null

prefixexp ::= Name
prefixexp ::= Name . prefixexp
prefixexp ::= Name [ exp ] [ afterpref ]
prefixexp ::= Name ( args ) [ afterpref ]
prefixexp ::= Name : Obj ( args ) [ afterpref ]
prefixexp ::= ( exp ) [ afterpref ]
--]]

--[[
    X = . Name X
    X = [Expr] X
    X = : Name (args) X
    X = (args) X
    (Expr) X
    Var X
--]]

  function gram.prefixExp(inp,r,ctx)  
    if inp.test('.') then
      local n = inp.match('Name')
      return gram.prefixExp(inp,{'aref',r,n},ctx)
    elseif inp.test('[') then     
      local e = gram.expr(inp,ctx)
      inp.match(']')
      return gram.prefixExp(inp,{'aref',r,e},ctx)
    elseif inp.peek().type == '(' or inp.peek().type == '{' then
      local args = gram.args(inp,ctx)
      return gram.prefixExp(inp,{'call',r,args},ctx) 
    elseif inp.test(':') then
      local key = inp.match('Name')
      local args= gram.args(inp,ctx)
      local ep = {'callobj',r,key,args}
      return gram.prefixExp(inp,ep,ctx) 
    else return r end
  end

  function gram.args(inp,ctx)
    local n = inp.next()
    if n.type == '(' then
      local r = gram.exprList(inp,ctx)
      inp.match(')')
      return r
    elseif n.type == '{' then
      inp.back(n)
      return {gram.tableConstructor(inp,ctx)}
    else error("Bad function argument list") end
  end

  function gram.nameList(inp)
    local res={inp.match('Name')}
    while inp.test(',') do res[#res+1]=inp.match('Name') end
    return res
  end

--varlist ::= var {‘,’ var}
--var ::=  Name | prefixexp ‘[’ exp ‘]’ | prefixexp ‘.’ Name 

  function gram.varList(inp,ctx,loc)
    local res = {}
    local p = inp.peek()
    while true do
      local n = inp.matchA('Name')
      local k = inp.peek()
      if PREFIXTKNS[k.type] then
        res[#res+1] = gram.prefixExp(inp,makeVar(n.value,ctx),ctx)
      else res[#res+1]=loc and {'var',n.value} or makeVar(n.value,ctx) end
      if inp.peek().type ~= ',' then break end
      inp.next()
      p=inp.peek()
    end
    return res
  end

  function gram.stat(inp,ctx)
    local n = inp.next()
    local t = n.type
    if t == ';' then return gram.stat(inp,ctx)
    elseif t == 'break' then return {'break'}
    elseif t == '::' then local n = inp.match('Name'); inp.match('::'); return {'label',n}
    elseif t == 'goto' then return {'goto',inp.match('Name')}
    elseif t == 'do' then local b = gram.block(inp,{l={},n=ctx}); inp.match('end'); return b
    elseif t == 'while' then
      local e = gram.expr(inp,ctx)
      inp.match('do')
      local b = gram.block(inp,{l={},n=ctx})
      inp.match('end')
      return {'while',e,b}
    elseif t == 'repeat' then 
      local b = gram.block(inp,{l={},n=ctx});
      inp.match('until') 
      return {'repeat',gram.expr(inp,ctx),b}
    elseif t == 'for' then
--for Name ‘=’ exp ‘,’ exp [‘,’ exp] do block end | 
--for namelist in explist do block end | 
      local l = gram.nameList(inp)
      t = inp.next()
      if t.type == '=' then
        local e1,e2,e3,b = gram.expr(inp,ctx),nil,1
        inp.match(',')
        e2 = gram.expr(inp,ctx)
        if inp.test(',') then e3 = gram.expr(inp,ctx) end
        inp.match('do'); b=gram.block(inp,{l=copyt(l),n=ctx}); inp.match('end')
        assert(#l==1,"wrong number of loop variables")
        return {'foridx',l[1],e1,e2,e3,b}
      elseif t.type == 'in' then
        local el,b = gram.exprList(inp,ctx)
        inp.match('do'); b=gram.block(inp,{l=copyt(l),n=ctx}); inp.match('end')
        return {'forlist',l[1],l[2] or '_',el,b}
      else error() end
    elseif t == 'if' then
      local e = gram.expr(inp,ctx)
      inp.match('then')
      local b = gram.block(inp,{l={},n=ctx})
      local eif,els={}
      while inp.test('elseif') do
        local e = gram.expr(inp,ctx)
        inp.match('then')
        local b = gram.block(inp,{l={},n=ctx})
        eif[#eif+1]={e,b}
      end
      if inp.test('else') then 
        els = gram.block(inp,{l={},n=ctx})
      end
      inp.match('end')
      return {'if',e,b,eif,els}
    elseif t == 'Name' then
      inp.back(n)
      local vars=gram.varList(inp,ctx)
      if inp.test('=') then
        local exprs = gram.exprList(inp,ctx)
        return {'assign',vars,exprs}
      else
        assert(#vars==1,"Bad expression1")
        vars = vars[1]
        assert(vars[1]=='call' or vars[1]=='callobj',"Bad expression2")
        return {'nop',vars}
      end
    elseif t == 'function' then
      local name,ft = gram.funcName(inp,ctx)
      local args,varargs,body = gram.funcBody(inp,ctx)
      ctx.l[name[2]]=nil
      return {'nop',{'function','glob',ft,name,args,varargs,body}}
    elseif t == 'local' then
      if inp.test('function') then
--      local name,ft = gram.funcName(inp)
        local name,ft = makeVar(inp.match('Name'),ctx),'fun'  -- If it exists?
        name[1]='var'
        addVarsToCtx({name},ctx)
        local args,varargs,body = gram.funcBody(inp,ctx)
        return {'nop',{'function','loc',ft,name,args,varargs,body}}
      else 
        local vars,exprs = gram.varList(inp,ctx,true),{}
        addVarsToCtx(vars,ctx)
        if inp.test('=') then
          exprs = gram.exprList(inp,ctx)
        end
        return {'local',vars,exprs}
      end
    end
    inp.back(n)
  end

  function gram.exprList(inp,ctx)
    local res,i = {gram.expr(inp,ctx)},2
    while inp.test(',') do
      res[i]=gram.expr(inp,ctx) i=i+1
    end
    return res
  end

  local bends = {['end']=true,['elseif']=true,['else']=true,['until']=true,['return']=true,['eof']=true,}

  function gram.block(inp,ctx)
    local s = {gram.stat(inp,ctx)}
    if #s>0 then
      while not bends[inp.peek().type] do 
        local t=gram.stat(inp,ctx) 
        if t== nil then break else s[#s+1]=t end
      end
    end
    if inp.test('return') then
      local re = gram.exprList(inp,ctx)
      s[#s+1] = {'return'..(#re < 2 and #re or 'n'),re}
    end
    inp.test(';') -- optional
    return {'block',s}
  end

  function gram.field(inp,ctx) 
    if inp.test('[') then
      local e1 = gram.expr(inp,ctx)
      inp.match(']')
      inp.match('=')
      return {gram.expr(inp,ctx),e1}
    elseif inp.peek().type == 'Name' and inp.peek(2).type == '=' then
      local n = inp.next()
      inp.match('=')
      return {gram.expr(inp,ctx),n.value}
    else
      return {gram.expr(inp,ctx)}
    end
  end

  function gram.tableConstructor(inp,ctx)
    inp.match('{') 
    --if inp.test('}') then return {'quote',{}} end
    local res = {gram.field(inp,ctx)}
    while inp.peek().type == ',' or inp.peek().type == ';' do
      inp.next()
      if inp.peek().type == '}' then break end
      res[#res+1]=gram.field(inp,ctx)
    end
    inp.match('}')
    return {'table',res}
  end
--[[
functiondef ::= function funcbody
funcbody ::= ‘(’ [parlist] ‘)’ block end
parlist ::= namelist [‘,’ ‘...’] | ‘...’
--]]

  function gram.funcBody(inp,ctx)
    inp.match('(')
    local p = inp.peek()
    local varargs,args=false,{}
    if p.type == '...' then
      varargs=true
      inp.next()
    elseif p.type == 'Name' then
      args={inp.match('Name')}
      while inp.test(',') do 
        p=inp.peek()
        if inp.test('...') then  varargs=true break end
        args[#args+1]=inp.match('Name') 
      end
    end 
    inp.match(')')
    local b = gram.block(inp,{l=copyt(args),n=ctx})
    inp.match('end')
    return args,varargs,b
  end

--funcname ::= Name {‘.’ Name} [‘:’ Name]

  function gram.funcName(inp,ctx)
    local t = makeVar(inp.match('Name'),ctx)
    while true do
      local p = inp.peek()
      if inp.test('.') then
        local n = inp.match('Name')
        t = {'aref',t,n}
      elseif inp.test(':') then
        local n = inp.match('Name')
        return {'aref',t,n},'obj'
      end
      break
    end
    return t,'fun'
  end

  local function tokenToError(token,str)
    local l = 0
    line = nil
    for c in str:gmatch"(.-)[\n$]" do l=l+1; if l==token.line then line = c break end end
    if l==0 then return format(">>%s<<",token.val)
    else 
      return format('line %s:"%s>>%s<<%s"',l,line:sub(1,token.from-1),token.value,line:sub(token.to+1))
    end
  end

  return function(str,locals)
    locals = locals or {}
    stat,res = pcall(function()
        mTokens = mkStream(tokenize(str))
        local expr = gram.block(mTokens,{l=locals})
        if mTokens.peek() ~= mTokens.eof then
          error({err="Unexpected token at eof",token=mTokens.next()})
        end
        return expr
      end)
    if stat then return res
    else
      if type(res)=='table' then
        error(res.err.." - "..tokenToError(res.token,str),1)
      else error(res,1) end
    end
  end

end