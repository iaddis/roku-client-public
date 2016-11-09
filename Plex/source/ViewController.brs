'*
'* A controller for managing the stack of screens that have been displayed.
'* By centralizing this we can better support things like destroying and
'* recreating views and breadcrumbs. It also provides a single place that
'* can take an item and figure out which type of screen should be shown
'* so that logic doesn't have to be in each individual screen type.
'*

Function createViewController() As Object
    controller = CreateObject("roAssociativeArray")

    controller.breadcrumbs = CreateObject("roArray", 10, true)
    controller.screens = CreateObject("roArray", 10, true)

    controller.GlobalMessagePort = CreateObject("roMessagePort")

    controller.CreateHomeScreen = vcCreateHomeScreen
    controller.CreateLockScreen = vcCreateLockScreen
    controller.CreateScreenForItem = vcCreateScreenForItem
    controller.CreateTextInputScreen = vcCreateTextInputScreen
    controller.CreateEnumInputScreen = vcCreateEnumInputScreen
    controller.CreateReorderScreen = vcCreateReorderScreen
    controller.CreateContextMenu = vcCreateContextMenu

    controller.CreatePhotoPlayer = vcCreatePhotoPlayer
    controller.CreateVideoPlayer = vcCreateVideoPlayer
    controller.CreatePlayerForItem = vcCreatePlayerForItem
    controller.IsVideoPlaying = vcIsVideoPlaying
    controller.IsSlideShowPlaying = vcIsSlideShowPlaying
    controller.IsMusicNowPlaying = vcIsMusicNowPlaying

    controller.ShowFirstRun = vcShowFirstRun
    controller.ShowHelpScreen = vcShowHelpScreen

    controller.InitializeOtherScreen = vcInitializeOtherScreen
    controller.AssignScreenID = vcAssignScreenID
    controller.PushScreen = vcPushScreen
    controller.PopScreen = vcPopScreen
    controller.IsActiveScreen = vcIsActiveScreen
    controller.GetActiveScreen = vcGetActiveScreen

    controller.afterCloseCallback = invalid
    controller.CloseScreenWithCallback = vcCloseScreenWithCallback
    controller.CloseScreen = vcCloseScreen

    controller.Show = vcShow
    controller.ProcessOneMessage = vcProcessOneMessage
    controller.OnInitialized = vcOnInitialized
    controller.OnScreensaver = vcOnScreensaver
    controller.UpdateScreenProperties = vcUpdateScreenProperties
    controller.AddBreadcrumbs = vcAddBreadcrumbs

    controller.DestroyGlitchyScreens = vcDestroyGlitchyScreens

    ' Even with the splash screen, we still need a facade for memory purposes
    ' and a clean exit.
    controller.facade = CreateObject("roGridScreen")
    controller.facade.Show()

    controller.nextScreenId = 1
    controller.nextTimerId = 1

    controller.InitThemes = vcInitThemes
    controller.PushTheme = vcPushTheme
    controller.PopTheme = vcPopTheme
    controller.ApplyThemeAttrs = vcApplyThemeAttrs

    controller.InitThemes()

    controller.PendingRequests = {}
    controller.RequestsByScreen = {}
    controller.StartRequest = vcStartRequest
    controller.StartRequestIgnoringResponse = vcStartRequestIgnoringResponse
    controller.CancelRequests = vcCancelRequests

    controller.SocketListeners = {}
    controller.AddSocketListener = vcAddSocketListener

    controller.Timers = {}
    controller.TimersByScreen = {}
    controller.AddTimer = vcAddTimer

    controller.SystemLog = CreateObject("roSystemLog")
    controller.SystemLog.SetMessagePort(controller.GlobalMessagePort)
    controller.SystemLog.EnableType("bandwidth.minute")
    controller.SystemLog.EnableType("http.error")

    controller.backButtonTimer = createTimer()
    controller.backButtonTimer.SetDuration(60000, true)

    ' Stuff the controller into the global object
    m.ViewController = controller

    ' Initialize things that run in the background
    AppManager().AddInitializer("viewcontroller")
    RegInitializeUser()
    InitWebServer(controller)
    AudioPlayer()
    AnalyticsTracker()
    MyPlexManager()
    GDMAdvertiser()

    return controller
End Function

Function GetViewController()
    return m.ViewController
End Function

Function vcCreateHomeScreen() as dynamic
    ' Show the PIN screen if we have been flagged for reauth
    if MyPlexManager().reauth = true then
        MyPlexManager().reauth = false
        screen = createMyPlexPinScreen(m)
        m.InitializeOtherScreen(screen, invalid)
        screen.Show()
        return invalid
    end if

    ' show the user list on startup for multi-user homes or if the last user is protected
    isProtectedUser = (MyPlexManager().Protected = true and NOT(MyPlexManager().PinAuthenticated = true))
    isMultiUserHome = (MyPlexManager().homeUsers.count() > 1)
    isAutoLogin = (RegRead("autologin", "preferences", "disabled", true) = "enabled")
    if NOT isAutoLogin and (MyPlexManager().IsSignedIn or MyPlexManager().IsOffline) and NOT (MyPlexManager().switchSuccess = true) and (isProtectedUser or isMultiUserHome) then
        ' only show the user list and pin entry once.
        if m.showUserList <> invalid then return invalid
        m.showUserList = true

        userScreen = createHomeUsersScreen(m)
        m.InitializeOtherScreen(userScreen, ["Home Users"])
        userScreen.Show()

        ' TODO(rob): should we automatically show the PIN screen for the last user selected?
        ' as of now, we'll only prompt immediately if it's a single user home.
        if isProtectedUser and NOT isMultiUserHome then
            screen = createHomeUserPinScreen(m, MyPlexManager().Title, MyPlexManager().Id)
            screen.show()
            if screen.authorized then userScreen.screen.Close()
        end if

        return invalid
    else
        ' consider user pin authed if protected when auto login is enabled
        if isAutoLogin and isProtectedUser then MyPlexManager().PinAuthenticated = true
        screen = createHomeScreen(m)
        screen.ScreenName = "Home"
        m.InitializeOtherScreen(screen, invalid)
        screen.SetBreadcrumbs()
        screen.Show()
    end if

    return screen
End Function

Function vcCreateScreenForItem(context, contextIndex, breadcrumbs, show=true) As Dynamic
    if type(context) = "roArray" then
        item = context[contextIndex]
    else
        item = context
    end if

    contentType = item.ContentType
    viewGroup = item.viewGroup
    if viewGroup = invalid then viewGroup = ""

    ' NOTE: We don't support switching between them as a preference, but
    ' the poster screen can be used anywhere the grid is used below. By
    ' default the poster screen will try to decide whether or not to
    ' include the filter bar that makes it more grid like, but it can
    ' be forced by setting screen.FilterMode = true.

    screen = invalid
    screenName = invalid

    if contentType = "movie" OR contentType = "episode" OR contentType = "clip" then
        screen = createVideoSpringboardScreen(context, contextIndex, m)
        screenName = "Preplay " + contentType
    else if contentType = "series" then
        if RegRead("use_grid_for_series", "preferences", "") <> "" then
            screen = createGridScreenForItem(item, m, "landscape")
            screenName = "Series Grid"
        else
            screen = createPosterScreen(item, m)
            screenName = "Series Poster"
        end if
    else if contentType = "artist" then
        ' TODO: Poster, poster with filters, or grid?
        screen = createPosterScreen(item, m)
        screenName = "Artist Poster"
    else if contentType = "album" then
        screen = createPosterScreen(item, m)
        ' TODO: What style looks best here, episodic?
        screen.SetListStyle("flat-episodic", "zoom-to-fill")
        screenName = "Album Poster"
    else if item.key = "nowplaying" then
        if NOT m.IsMusicNowPlaying() then
            AudioPlayer().ContextScreenID = m.nextScreenId
            screen = createAudioSpringboardScreen(AudioPlayer().Context, AudioPlayer().CurIndex, m)
            screenName = "Now Playing"
            breadcrumbs = [screenName, ""]
        end if
    else if contentType = "audio" then
        screen = createAudioSpringboardScreen(context, contextIndex, m)
        screenName = "Audio Springboard"
    else if contentType = "section" then
        if item.server <> invalid AND item.server.machineID <> invalid then
            RegWrite("lastMachineID", item.server.machineID)
            RegWrite("lastSectionKey", item.key)
        end if
        ' we have some options to display a different style here per item type.
        ' I am not sure the best fit, but music and photos seem to look better,
        ' imho, in flat-landscape mode (but we need a focus border asset for
        ' that). The gridscreen will ignore this if one has selected
        ' mixed-aspect-ratio
        itemType = tostr(item.type)
        nonMixStyle = invalid
        if itemType = "artist" or itemType = "photo" then
            ' style = "flat-landscape" ' needs border asset
            nonMixStyle = "flat-movie"
        end if
        screen = createGridScreenForItem(item, m, "portrait", nonMixStyle)
        screenName = "Section: " + tostr(item.type)
    else if contentType = "playlists" then
        screen = createGridScreenForItem(item, m, "landscape")
        screenName = "Playlist Grid"
    else if contentType = "photo" then
        if right(item.key, 8) = "children" then
            screen = createPosterScreen(item, m)
            screenName = "Photo Poster"
        else
            screen = createPhotoSpringboardScreen(context, contextIndex, m)
            screenName = "Photo Springboard"
        end if
    else if contentType = "keyboard" then
        screen = createKeyboardScreen(m, item)
        screenName = "Keyboard"
    else if contentType = "search" then
        screen = createSearchScreen(item, m)
        screenName = "Search"
    else if item.key = "/system/appstore" then
        screen = createGridScreenForItem(item, m, "square")
        screenName = "Channel Directory"
    else if viewGroup = "Store:Info" then
        dialog = createPopupMenu(item)
        dialog.Show()
    else if viewGroup = "secondary" then
        screen = createPosterScreen(item, m)
    else if item.key = "globalprefs" then
        screen = createPreferencesScreen(m)
        screenName = "Preferences Main"
    else if item.key = "homeusers" then
        screen = createHomeUsersScreen(m)
        screenName = "Home Users"
    else if item.key = "_filters_" then
        screen = createFiltersScreen(item, m)
        screenName = "Filters"
    else if item.key = "/channels/all" then
        ' Special case for all channels to force it into a special grid view
        screen = createGridScreen(m, "square")
        names = ["Video Channels", "Music Channels", "Photo Channels"]
        keys = ["/video", "/music", "/photos"]
        fakeContainer = createFakePlexContainer(item.server, names, keys)
        screen.Loader = createPaginatedLoader(fakeContainer, 8, 25)
        screen.Loader.Listener = screen
        screen.Loader.Port = screen.Port
        screenName = "All Channels"
    else if item.searchTerm <> invalid AND item.server = invalid then
        screen = createGridScreen(m, "square")
        screen.Loader = createSearchLoader(item.searchTerm)
        screen.Loader.Listener = screen

        ' Search screen is special. We do not refresh the search screen, but if we
        ' need to, we'll have to create a refreshData routine in the searchLoader.
        screen.ignoreOnActivate = true

        screenName = "Search Results"
    else if item.settings = "1"
        screen = createSettingsScreen(item, m)
        screenName = "Settings"
    else if item.paragraphs <> invalid then
        if item.screenType = "paragraph" then
            screen = createParagraphScreen(item.header, item.paragraphs, m)
        else
            dialog = createBaseDialog()
            dialog.Title = item.header
            dialog.Text = item.paragraphs
            dialog.Show()
        end if
    else if item.key <> invalid
        ' Where do we capture channel directory?
        Debug("Creating a default view for contentType=" + tostr(contentType) + ", viewGroup=" + tostr(viewGroup))
        screen = createPosterScreen(item, m)
    end if

    if screen = invalid then return invalid

    if screenName = invalid then
        screenName = type(screen.Screen) + " " + firstOf(contentType, "unknown") + " " + firstOf(viewGroup, "unknown")
    end if

    screen.ScreenName = screenName

    m.AddBreadcrumbs(screen, breadcrumbs)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreateTextInputScreen(heading, breadcrumbs, show=true, initialValue="", secure=false) As Dynamic
    screen = createKeyboardScreen(m, invalid, heading, initialValue, secure)
    screen.ScreenName = "Keyboard: " + tostr(heading)

    m.AddBreadcrumbs(screen, breadcrumbs)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreateEnumInputScreen(options, selected, heading, breadcrumbs, show=true) As Dynamic
    screen = createEnumScreen(options, selected, m)
    screen.ScreenName = "Enum: " + tostr(heading)

    if heading <> invalid then
        screen.Screen.SetHeader(heading)
    end if

    m.AddBreadcrumbs(screen, breadcrumbs)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreateReorderScreen(items, breadcrumbs, show=true) As Dynamic
    screen = createReorderScreen(items, m)
    screen.ScreenName = "Reorder"

    m.AddBreadcrumbs(screen, breadcrumbs)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreateContextMenu()
    ' Our context menu is only relevant if the audio player has content.
    if AudioPlayer().ContextScreenID = invalid then return invalid

    return AudioPlayer().ShowContextMenu()
End Function

Function vcCreatePhotoPlayer(context, contextIndex=invalid, show=true, shuffled=false)
    screen = createPhotoPlayerScreen(context, contextIndex, m, shuffled)
    screen.ScreenName = "Photo Player"

    m.AddBreadcrumbs(screen, invalid)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    return screen
End Function

Function vcCreateVideoPlayer(metadata, seekValue=0, directPlayOptions=0, show=true)
    ' Create a facade screen for instant feedback.
    facade = CreateObject("roGridScreen")
    facade.show()

    ' Stop any background audio first
    AudioPlayer().Stop()

    ' Make sure we have full details before trying to play.
    metadata.ParseDetails()

    ' Prompt about resuming if there's an offset and the caller didn't specify a seek value.
    if seekValue = invalid then
        if metadata.viewOffset <> invalid then
            offsetMillis = int(val(metadata.viewOffset))

            dlg = createBaseDialog()
            dlg.Title = "Play Video"
            dlg.SetButton("resume", "Resume from " + TimeDisplay(int(offsetMillis/1000)))
            dlg.SetButton("play", "Play from beginning")
            dlg.Show(true)

            if dlg.Result = invalid then return invalid
            if dlg.Result = "resume" then
                seekValue = offsetMillis
            else
                seekValue = 0
            end if
        else
            seekValue = 0
        end if
    end if

    screen = createVideoPlayerScreen(metadata, seekValue, directPlayOptions, m)
    screen.ScreenName = "Video Player"

    m.AddBreadcrumbs(screen, invalid)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)

    if show then screen.Show()

    facade.close()
    return screen
End Function

Function vcCreatePlayerForItem(context, contextIndex, seekValue=invalid)
    item = context[contextIndex]

    if item.ContentType = "photo" then
        return m.CreatePhotoPlayer(context, contextIndex)
    else if item.ContentType = "audio" then
        AudioPlayer().Stop()
        return m.CreateScreenForItem(context, contextIndex, invalid)
    else if item.ContentType = "movie" OR item.ContentType = "episode" OR item.ContentType = "clip" then
        directplay = RegRead("directplay", "preferences", "0").toint()
        return m.CreateVideoPlayer(item, seekValue, directplay)
    else
        Debug("Not sure how to play item of type " + tostr(item.ContentType))
        return m.CreateScreenForItem(context, contextIndex, invalid)
    end if
End Function

Function vcIsVideoPlaying() As Boolean
    return type(m.screens.Peek().Screen) = "roVideoScreen"
End Function

Function vcIsSlideShowPlaying() As Boolean
    return type(m.screens.Peek().Screen) = "roSlideShow"
End Function

Function vcIsMusicNowPlaying() As Boolean
    return AudioPlayer().ContextScreenID = m.screens.Peek().ScreenID
End Function

Sub vcShowFirstRun()
    ' TODO(schuyler): Are these different?
    m.ShowHelpScreen()
End Sub

Sub vcShowHelpScreen()
    ' Only show the help screen once per launch.
    if m.helpScreenShown = true then
        return
    else
        m.helpScreenShown = true
    end if

    header = "Welcome to Plex!"
    paragraphs = []
    paragraphs.Push("With Plex you can easily stream your videos, music, photos and home movies to your Roku using your Plex Media Server.")
    paragraphs.Push("To download and install your free Plex Media Server on your computer, visit https://plex.tv/downloads")

    screen = createParagraphScreen(header, paragraphs, m)
    m.InitializeOtherScreen(screen, invalid)

    screen.Show()
End Sub

Sub vcInitializeOtherScreen(screen, breadcrumbs)
    m.AddBreadcrumbs(screen, breadcrumbs)
    m.UpdateScreenProperties(screen)
    m.PushScreen(screen)
End Sub

Sub vcAssignScreenID(screen)
    if screen.ScreenID = invalid then
        screen.ScreenID = m.nextScreenId
        m.nextScreenId = m.nextScreenId + 1
    end if
End Sub

Sub vcPushScreen(screen)
    m.AssignScreenID(screen)
    screenName = firstOf(screen.ScreenName, type(screen.Screen))
    AnalyticsTracker().TrackScreen(screenName)
    Debug("Pushing screen " + tostr(screen.ScreenID) + " onto view controller stack - " + screenName)
    m.screens.Push(screen)
End Sub

Sub vcPopScreen(screen, callActivate=true as boolean)
    if screen.Cleanup <> invalid then screen.Cleanup()

    ' Try to clean up some potential circular references
    screen.Listener = invalid
    screen.FilterOptions = invalid
    if screen.Loader <> invalid then
        screen.Loader.Listener = invalid
        screen.Loader = invalid
    end if

    if screen.ScreenID = invalid OR m.screens.Peek().ScreenID = invalid then
        Debug("Trying to pop screen a screen without a screen ID!")
        Return
    end if

    screenID = screen.ScreenID.tostr()
    if screen.ScreenID <> m.screens.Peek().ScreenID then
        Debug("Trying to pop screen that doesn't match the top of our stack!")

        ' This is potentially indicative of something very wrong, which we may
        ' not be able to recover from. But it also happens when we launch a new
        ' screen from a dialog and try to pop the dialog after the new screen
        ' has been put on the stack. If we don't remove the screen from the
        ' stack, things will almost certainly go wrong (seen one crash report
        ' likely caused by this). So we might as well give it a shot.

        for i = m.screens.Count() - 1 to 0 step -1
            if screen.ScreenID = m.screens[i].ScreenID then
                Debug("Removing screen " + screenID + " from middle of stack!")
                m.screens.Delete(i)
                exit for
            end if
        next
        callActivate = false
    else
        Debug("Popping screen " + screenID + " and cleaning up " + tostr(screen.NumBreadcrumbs) + " breadcrumbs")
        m.screens.Pop()
        for i = 0 to screen.NumBreadcrumbs - 1
            m.breadcrumbs.Pop()
        next
    end if

    ' Clean up any requests initiated by this screen
    m.CancelRequests(screen.ScreenID)

    ' Clean up any timers initiated by this screen
    timers = m.TimersByScreen[screenID]
    if timers <> invalid then
        for each timerID in timers
            timer = m.Timers[timerID]
            timer.Active = false
            timer.Listener = invalid
            m.Timers.Delete(timerID)
        next
        m.TimersByScreen.Delete(screenID)
    end if

    ' Let the new top of the stack know that it's visible again. If we have
    ' no screens on the stack, but we didn't just close the home screen, then
    ' we haven't shown the home screen yet. Show it now.
    if m.Home <> invalid AND screen.screenID = m.Home.ScreenID then
        Debug("Popping home screen")
        while m.screens.Count() > 1
            m.PopScreen(m.screens.Peek())
        end while
        m.screens.Pop()
    else if m.screens.Count() = 0 then
        m.Home = m.CreateHomeScreen()
    else if callActivate then
        newScreen = m.screens.Peek()
        screenName = firstOf(newScreen.ScreenName, type(newScreen.Screen))
        Debug("Top of stack is once again: " + screenName)
        AnalyticsTracker().TrackScreen(screenName)
        newScreen.Activate(screen)
    end if

    ' If some other screen requested this close, let it know.
    if m.afterCloseCallback <> invalid then
        callback = m.afterCloseCallback
        m.afterCloseCallback = invalid
        callback.OnAfterClose()
    end if
End Sub

Function vcIsActiveScreen(screen=invalid as dynamic) As Boolean
    return (screen <> invalid and m.screens.Count() > 0 and m.screens.Peek().ScreenID = screen.ScreenID)
End Function

Function vcGetActiveScreen(wrapper=false)
    screen = m.screens.Peek()
    if screen = invalid then
        return invalid
    else if wrapper then
        return screen
    else
        return screen.screen
    end if
End Function

Sub vcCloseScreenWithCallback(callback)
    m.afterCloseCallback = callback
    m.screens.Peek().Screen.Close()
End Sub

Sub vcCloseScreen(simulateRemote)
    ' Unless the visible screen is the home screen.
    if m.Home <> invalid AND NOT m.IsActiveScreen(m.Home) then
        ' Our one complication is the screensaver, which we can't know anything
        ' about. So if we're simulating the remote control and haven't been
        ' called in a while, send an ECP back. Otherwise, directly close our
        ' top screen.
        if m.backButtonTimer.IsExpired() then
            SendEcpCommand("Back")
        else
            m.screens.Peek().Screen.Close()
        end if
    end if
End Sub

Sub vcShow()
    Debug("Starting global message loop")
    AppManager().ClearInitializer("viewcontroller")

    timeout = 0
    while m.screens.Count() > 0 OR NOT AppManager().IsInitialized()
        timeout = m.ProcessOneMessage(timeout)
    end while

    ' Clean up some references on the way out
    AnalyticsTracker().Cleanup()
    GDMAdvertiser().Cleanup()
    AudioPlayer().Cleanup()
    m.Home = invalid
    m.WebServer = invalid
    m.Timers.Clear()
    m.PendingRequests.Clear()
    m.SocketListeners.Clear()

    Debug("Finished global message loop")
End Sub

Function vcProcessOneMessage(timeout)
    if RegRead("screensaverActivated") <> invalid then
        m.OnScreensaver()
    else if CheckMinimumVersion(GetGlobal("rokuVersionArr", [0]), [4, 8]) and TimeSinceLastKeyPress() > GetGlobal("plexIdleTimeout") then
        m.CreateLockScreen()
    end if

    m.WebServer.prewait()
    msg = wait(timeout, m.GlobalMessagePort)
    if msg <> invalid then
        ' Printing debug information about every message may be overkill
        ' regardless, but note that URL events don't play by the same rules,
        ' and there's no ifEvent interface to check for. Sigh.
        'if type(msg) = "roUrlEvent" OR type(msg) = "roSocketEvent" OR type(msg) = "roChannelStoreEvent" then
        '    Debug("Processing " + type(msg) + " (top of stack " + type(m.GetActiveScreen()) + ")")
        'else
        '    Debug("Processing " + type(msg) + " (top of stack " + type(m.GetActiveScreen()) + "): " + tostr(msg.GetType()) + ", " + tostr(msg.GetIndex()) + ", " + tostr(msg.GetMessage()))
        'end if

        for i = m.screens.Count() - 1 to 0 step -1
            if m.screens[i].HandleMessage(msg) then exit for
        end for

        ' Process URL events. Look up the request context and call a
        ' function on the listener.
        if type(msg) = "roUrlEvent" AND msg.GetInt() = 1 then
            id = msg.GetSourceIdentity().tostr()
            requestContext = m.PendingRequests[id]
            if requestContext <> invalid then
                m.PendingRequests.Delete(id)
                if requestContext.Listener <> invalid then
                    requestContext.Listener.OnUrlEvent(msg, requestContext)
                end if
                requestContext = invalid
            end if
        else if type(msg) = "roSocketEvent" then
            listener = m.SocketListeners[msg.getSocketID().tostr()]
            if listener <> invalid then
                listener.OnSocketEvent(msg)
                listener = invalid
            else
                ' Assume it was for the web server (it won't hurt if it wasn't)
                m.WebServer.postwait()
            end if
        else if type(msg) = "roAudioPlayerEvent" then
            AudioPlayer().HandleMessage(msg)
        else if type(msg) = "roSystemLogEvent" then
            msgInfo = msg.GetInfo()
            if msgInfo.LogType = "bandwidth.minute" then
                GetGlobalAA().AddReplace("bandwidth", msgInfo.Bandwidth)
            else if msgInfo.LogType = "http.error" then
                Debug("http error: " + tostr(msgInfo, 1))
            end if
        else if msg.isRemoteKeyPressed() and msg.GetIndex() = 10 then
            m.CreateContextMenu()
        end if
    end if

    ' Check for expired url requests
    for each requestID in m.PendingRequests
        request = m.PendingRequests[requestId]
        if request <> invalid and request.timer <> invalid and request.timer.IsExpired() then
            Debug("Cancel expired pending request")
            request.Request.AsyncCancel()
            m.PendingRequests.Delete(requestID)
            if request.listener <> invalid and type(request.listener.OnUrlEvent) = "roFunction" then
                request.listener.OnUrlEvent(fakeUrlResponse(requestID.toInt()), request)
            end if
        end if
    end for

    ' Check for any expired timers
    timeout = 0
    for each timerID in m.Timers
        timer = m.Timers[timerID]
        if timer.IsExpired() then
            timer.Listener.OnTimerExpired(timer)
        end if

        ' Make sure we set a timeout on the wait so we'll catch the next timer
        remaining = timer.RemainingMillis()
        if remaining > 0 AND (timeout = 0 OR remaining < timeout) then
            timeout = remaining
        end if
    next

    return timeout
End Function

Sub vcOnInitialized()
    ' As good a place as any, note that we've started
    AnalyticsTracker().OnStartup(MyPlexManager().IsSignedIn)

    if m.screens.Count() = 0 then
        if m.PlaybackArgs <> invalid then
            m.CreatePlayerForItem(m.PlaybackArgs.context, m.PlaybackArgs.index, m.PlaybackArgs.offset)
        else if RegRead("last_run_version", "misc") = invalid then
            m.ShowFirstRun()
            RegWrite("last_run_version", GetGlobal("appVersionStr"), "misc")
        else
            m.Home = m.CreateHomeScreen()
        end if
    end if
End Sub

Sub vcAddBreadcrumbs(screen, breadcrumbs)
    ' Add the breadcrumbs to our list and set them for the current screen.
    ' If the current screen specified invalid for the breadcrubms then it
    ' doesn't want any breadcrumbs to be shown. If it specified an empty
    ' array, then the current breadcrumbs will be shown again.
    screenType = type(screen.Screen)
    if breadcrumbs = invalid then
        screen.NumBreadcrumbs = 0
        return
    end if

    ' Special case for springboard screens, don't show the current title
    ' in the breadcrumbs.
    if screenType = "roSpringboardScreen" AND breadcrumbs.Count() > 0 then
        breadcrumbs.Pop()
    end if

    if breadcrumbs.Count() = 0 AND m.breadcrumbs.Count() > 0 then
        count = m.breadcrumbs.Count()
        if count >= 2 then
            breadcrumbs = [m.breadcrumbs[count-2], m.breadcrumbs[count-1]]
        else
            breadcrumbs = [m.breadcrumbs[0]]
        end if

        m.breadcrumbs.Append(breadcrumbs)
        screen.NumBreadcrumbs = breadcrumbs.Count()
    else
        for each b in breadcrumbs
            m.breadcrumbs.Push(tostr(b))
        next
        screen.NumBreadcrumbs = breadcrumbs.Count()
    end if
End Sub

Sub vcUpdateScreenProperties(screen)
    ' Make sure that metadata requests from the screen carry an auth token.
    if GetInterface(screen.Screen, "ifHttpAgent") <> invalid AND screen.Item <> invalid AND screen.Item.server <> invalid AND screen.Item.server.AccessToken <> invalid then
        screen.Screen.SetCertificatesDepth(5)
        screen.Screen.SetCertificatesFile("common:/certs/ca-bundle.crt")
        AddAccountHeaders(screen.Screen, screen.Item.server.AccessToken)
    end if

    if screen.NumBreadcrumbs <> 0 then
        count = m.breadcrumbs.Count()
        if count >= 2 then
            enableBreadcrumbs = true
            bread1 = m.breadcrumbs[count-2]
            bread2 = m.breadcrumbs[count-1]
        else if count = 1 then
            enableBreadcrumbs = true
            bread1 = ""
            bread2 = m.breadcrumbs[0]
        else
            enableBreadcrumbs = false
        end if
    else
        enableBreadcrumbs = false
    end if

    screenType = type(screen.Screen)
    ' Sigh, different screen types don't support breadcrumbs with the same functions
    if screenType = "roGridScreen" OR screenType = "roPosterScreen" OR screenType = "roSpringboardScreen" then
        if enableBreadcrumbs then
            screen.Screen.SetBreadcrumbEnabled(true)
            screen.Screen.SetBreadcrumbText(bread1, bread2)
        else
            screen.Screen.SetBreadcrumbEnabled(false)
        end if
    else if screenType = "roSearchScreen" then
        if enableBreadcrumbs then
            screen.Screen.SetBreadcrumbText(bread1, bread2)
        end if
    else if screenType = "roListScreen" OR screenType = "roKeyboardScreen" OR screenType = "roParagraphScreen" then
        if enableBreadcrumbs then
            screen.Screen.SetTitle(bread2)
        end if
    else
        Debug("Not sure what to do with breadcrumbs on screen type: " + tostr(screenType))
    end if
End Sub

Sub vcInitThemes()
    m.ThemeStack = CreateObject("roList")
    m.ThemeApplyParams = CreateObject("roAssociativeArray")
    m.ThemeRevertParams = CreateObject("roAssociativeArray")
End Sub

Sub vcPushTheme(name)
    if NOT m.ThemeApplyParams.DoesExist(name) then return

    if name <> m.ThemeStack.GetTail() then
        m.ApplyThemeAttrs(m.ThemeApplyParams[name])
    end if

    m.ThemeStack.AddTail(name)
End Sub

Sub vcPopTheme()
    name = m.ThemeStack.RemoveTail()

    if name <> m.ThemeStack.GetTail() then
        m.ApplyThemeAttrs(m.ThemeRevertParams[name])
        m.ApplyThemeAttrs(m.ThemeApplyParams[m.ThemeStack.GetTail()])
    end if
End Sub

Sub vcApplyThemeAttrs(attrs)
    app = CreateObject("roAppManager")
    for each attr in attrs
        if attrs[attr] <> invalid then
            app.SetThemeAttribute(attr, attrs[attr])
        else
            app.ClearThemeAttribute(attr)
        end if
    next
End Sub

Sub vcDestroyGlitchyScreens()
    ' The audio player / grid screen glitch only affects older firmware versions.
    versionArr = GetGlobal("rokuVersionArr", [0])
    if versionArr[0] >= 4 then return

    for each screen in m.screens
        if screen.DestroyAndRecreate <> invalid then
            Debug("Destroying screen " + tostr(screen.ScreenID) + " to work around glitch")
            screen.DestroyAndRecreate()
        end if
    next
End Sub

Function vcStartRequest(request, listener, context, body=invalid) As Boolean
    request.SetPort(m.GlobalMessagePort)
    context.Listener = listener
    context.Request = request

    if body = invalid then
        started = request.AsyncGetToString()
    else
        started = request.AsyncPostFromString(body)
    end if

    if started then
        ' add a timer to the request (to cancel) if requested.
        if context.timeout <> invalid then
            context.timer = createTimer()
            context.timer.setDuration(context.timeout)
        end if

        id = request.GetIdentity().tostr()
        m.PendingRequests[id] = context

        if listener <> invalid then
            screenID = listener.ScreenID.tostr()
            if NOT m.RequestsByScreen.DoesExist(screenID) then
                m.RequestsByScreen[screenID] = []
            end if
            ' Screen ID's less than 0 are fake screens that won't be popped until
            ' the app is cleaned up, so no need to waste the bytes tracking them
            ' here.
            if listener.ScreenID >= 0 then m.RequestsByScreen[screenID].Push(id)
        end if

        return true
    else
        return false
    end if
End Function

Sub vcStartRequestIgnoringResponse(url, body=invalid, contentType="xml")
    request = CreateURLTransferObject(url)
    request.SetCertificatesFile("common:/certs/ca-bundle.crt")

    if body <> invalid then
        request.AddHeader("Content-Type", MimeType(contentType))
    end if

    context = CreateObject("roAssociativeArray")
    context.requestType = "ignored"

    m.StartRequest(request, invalid, context, body)
End Sub

Sub vcCancelRequests(screenID)
    requests = m.RequestsByScreen[screenID.tostr()]
    if requests <> invalid then
        for each requestID in requests
            request = m.PendingRequests[requestID]
            if request <> invalid then request.Request.AsyncCancel()
            m.PendingRequests.Delete(requestID)
        next
        m.RequestsByScreen.Delete(screenID.tostr())
    end if
End Sub

Sub vcAddSocketListener(socket, listener)
    m.SocketListeners[socket.GetID().tostr()] = listener
End Sub

Sub vcAddTimer(timer, listener)
    timer.ID = m.nextTimerId.tostr()
    m.nextTimerId = m.NextTimerId + 1
    timer.Listener = listener
    m.Timers[timer.ID] = timer

    screenID = listener.ScreenID.tostr()
    if NOT m.TimersByScreen.DoesExist(screenID) then
        m.TimersByScreen[screenID] = []
    end if
    m.TimersByScreen[screenID].Push(timer.ID)
End Sub

Sub InitWebServer(vc)
    ' Initialize some globals for the web server
    globals = CreateObject("roAssociativeArray")
    globals.pkgname = "Plex"
    globals.maxRequestLength = 4000
    globals.idletime = 60
    globals.wwwroot = "tmp:/"
    globals.index_name = "index.html"
    globals.serverName = "Plex"
    AddGlobals(globals)
    MimeType()
    HttpTitle()
    ClassReply().AddHandler("/logs", ProcessLogsRequest)
    InitRemoteControlHandlers()

    vc.WebServer = InitServer({msgPort: vc.GlobalMessagePort, port: 8324})
End Sub

Sub createScreenForItemCallback()
    GetViewController().CreateScreenForItem(m.Item, invalid, [firstOf(m.Heading, "")])
End Sub

Sub vcOnScreensaver()
    Debug("screensaver started")
    ' run once, remove registry status
    RegDelete("screensaverActivated")

    m.CreateLockScreen()
End Sub

Sub vcCreateLockScreen(force=false as boolean)
    ' Do not lock the screen while the video player is active. Roku used to reset
    ' the idle time during playback, but as a fail safe we'll ignore this until
    ' playback stops
    '
    if VideoPlaybackActive() then return

    ' ignore creating lock screen if auto login is enabled
    if (RegRead("autologin", "preferences", "disabled", true) <> "disabled") then return
    ' ignore creating (recreating) lock screen if NOT force and it's already locked/not pin authed
    if force = false and (GetGlobal("screenIsLocked") <> invalid or MyPlexManager().PinAuthenticated = false) then return
    ' ignore if NOT signed in/offline and NOT protected
    if NOT ((MyPlexManager().IsSignedIn or MyPlexManager().IsOffline) and MyPlexManager().Protected = true) then return

    Debug("Create lock screen and global lock")
    GetGlobalAA().AddReplace("screenIsLocked", "true")
    MyPlexManager().PinAuthenticated = false

    lockScreen = createHomeUsersScreen(m)
    m.InitializeOtherScreen(lockScreen, ["Home Users: Lock Screen"])
    lockScreen.Show()
End Sub
