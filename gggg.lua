setTimeout(function()
    for _,user in ipairs(api.get("/users") or {}) do
      self:post({type='location', id=user.id, property=user.atHome and 'enter' or 'away'})
   end
end,1)