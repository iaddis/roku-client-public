' ********************************************************************
' **  Entry point for the Plex client. Configurable themes etc. haven't been yet.
' **
' ********************************************************************

Sub Main()

    screenFacade = CreateObject("roPosterScreen")
    screenFacade.show()
    'initialize theme attributes like titles, logos and overhang color
    initTheme()

    'prepare the screen for display and get ready to begin
    screen=preShowHomeScreen("", "")
    if screen=invalid then
        print "unexpected error in preShowHomeScreen"
        return
    end if
	' TODO: move this to home screen to enable rescan when home screen visited. Too slow though?
	retrieving = CreateObject("roOneLineDialog")
	retrieving.SetTitle("Finding Plex Media Servers ...")
	retrieving.ShowBusyAnimation()
	retrieving.Show()
    'servers = MockDiscoverPlexMediaServers()
    servers = DiscoverPlexMediaServers()
	retrieving.Close()
    if servers.count() > 0 then
    	showHomeScreen(screen, servers)
    
    	screenFacade.showMessage("")
    	sleep(25)
    else
    	screenFacade.showMessage("Unable to find any Plex Media Servers")
    	sleep(5000)
    endif

End Sub


'*************************************************************
'** Set the configurable theme attributes for the application
'** 
'** Configure the custom overhang and Logo attributes
'** Theme attributes affect the branding of the application
'** and are artwork, colors and offsets specific to the app
'*************************************************************

Sub initTheme()

    app = CreateObject("roAppManager")
    theme = CreateObject("roAssociativeArray")

    theme.OverhangOffsetSD_X = "72"
    theme.OverhangOffsetSD_Y = "31"
    theme.OverhangSliceSD = "pkg:/images/Background_SD.jpg"
    theme.OverhangLogoSD  = "pkg:/images/logo_final_SD.png"

    theme.OverhangOffsetHD_X = "125"
    theme.OverhangOffsetHD_Y = "35"
    theme.OverhangSliceHD = "pkg:/images/Background_HD.jpg"
    theme.OverhangLogoHD  = "pkg:/images/logo_final_HD.png"

    app.SetTheme(theme)

End Sub
