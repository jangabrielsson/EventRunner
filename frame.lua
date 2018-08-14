wx = require("wx")
frame = wx.wxFrame(wx.NULL, wx.wxID_ANY, "EventRunner Control",
                   wx.wxDefaultPosition, wx.wxSize(450, 450),
                   wx.wxDEFAULT_FRAME_STYLE)
              -- create a simple file menu
local fileMenu = wx.wxMenu()
fileMenu:Append(wx.wxID_EXIT, "E&xit", "Quit the program")
-- create a simple help menu
local helpMenu = wx.wxMenu()
helpMenu:Append(wx.wxID_ABOUT, "&About",
                "About the EventRunner Control Application")

-- create a menu bar and append the file and help menus
local menuBar = wx.wxMenuBar()
menuBar:Append(fileMenu, "&File")
menuBar:Append(helpMenu, "&Help")
-- attach the menu bar into the frame
frame:SetMenuBar(menuBar)

-- create a simple status bar
frame:CreateStatusBar(1)
frame:SetStatusText("Welcome to EventRunner.")

-- connect the selection event of the exit menu item to an
-- event handler that closes the window
frame:Connect(wx.wxID_EXIT, wx.wxEVT_COMMAND_MENU_SELECTED,
              function (event) frame:Close(true) end )
-- connect the selection event of the about menu item
frame:Connect(wx.wxID_ABOUT, wx.wxEVT_COMMAND_MENU_SELECTED,
        function (event)
            wx.wxMessageBox('This is the "About" dialog of the EventRunner Control.',
                            "About EventRunner",
                            wx.wxOK + wx.wxICON_INFORMATION,
                            frame)
        end )
      
frame:Show(true)

gstimer = wx.wxTimer(frame)
frame:Connect(wx.wxEVT_TIMER, function() print("HUPP") gstimer:Start(1000,wx.wxTIMER_ONE_SHOT ) end) 
gstimer:Start(1,wx.wxTIMER_ONE_SHOT )
    
wx.wxGetApp():MainLoop()