--%%name = "Err1"

--intentional_error() -- Cause error while loading file
function QuickApp:onInit()
  --intentional_error() -- Cause error in init
  self:debug(self.name,self.id)
  local s = setTimeout(function() intentional_error() end,1) -- -- Cause error in thread
  setTimeout(function() os.exit() end,500)
end
