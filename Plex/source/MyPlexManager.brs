'*
'* Utilities related to signing in to myPlex and making myPlex requests
'*

Function MyPlexManager() As Object
    if m.MyPlexManager = invalid then
        ' Start by creating a PlexMediaServer since we can't otherwise inherit
        ' anything. Then tweak as appropriate.
        obj = newPlexMediaServer("https://plex.tv", "myPlex", "myplex")

        AppManager().AddInitializer("myplex")

        obj.CreateRequest = mpCreateRequest
        obj.ValidateToken = mpValidateToken
        obj.Disconnect = mpDisconnect
        obj.SetOffline = mpSetOffline

        obj.ExtraHeaders = {}
        obj.ExtraHeaders["X-Plex-Provides"] = "player"

        ' Masquerade as a basic Plex Media Server
        obj.owned = false
        obj.home = false
        obj.online = true
        obj.TranscodedImage = mpTranscodedImage
        obj.TranscodingVideoUrl = mpTranscodingVideoUrl
        obj.GetQueryResponse = mpGetQueryResponse
        obj.Log = mpLog
        obj.AllowsMediaDeletion = false
        obj.SupportsMultiuser = false
        obj.SupportsVideoTranscoding = true

        ' Commands, mostly use the PMS functions
        obj.Delete = mpDelete
        obj.ExecuteCommand = mpExecuteCommand
        obj.ExecutePostCommand = mpExecutePostCommand

        obj.IsSignedIn = false
        obj.IsOffline = false
        obj.IsPlexPass = false
        obj.IsRestricted = false
        obj.HasQueue = false
        obj.Username = invalid
        obj.EmailAddress = invalid
        obj.RefreshAccountInfo = mpRefreshAccountInfo
        obj.PinAuthenticated = false

        obj.TranscodeServer = invalid
        obj.CheckTranscodeServer = mpCheckTranscodeServer

        obj.ProcessAccountResponse = mpProcessAccountResponse
        obj.Publish = mpPublish

        ' For using the view controller for HTTP requests
        obj.ScreenID = -5
        obj.OnUrlEvent = mpOnUrlEvent

        ' Home Users
        obj.homeUsers = createObject("roList")
        obj.UpdateHomeUsers = mpUpdateHomeUsers
        obj.SwitchHomeUser = mpSwitchHomeUser

        ' Singleton
        m.MyPlexManager = obj

        ' Kick off initialization
        token = RegRead("AuthToken", "myplex")
        if token <> invalid then
            obj.ValidateToken(token, true)
        else
            AppManager().ClearInitializer("myplex")
        end if
    end if

    return m.MyPlexManager
End Function

Sub mpRefreshAccountInfo()
    if m.AuthToken <> invalid then
        dialog = CreateObject("roOneLineDialog")
        dialog.ShowBusyAnimation()
        dialog.Show()

        m.ValidateToken(m.AuthToken, false)

        dialog.Close()
    end if
End Sub

Function mpValidateToken(token, async) As Boolean
    req = m.CreateRequest("", "/users/account", false)
    req.AddHeader("X-Plex-Token", token)

    if async then
        context = CreateObject("roAssociativeArray")
        context.requestType = "account"
        context.timeout = 10000
        GetViewController().StartRequest(req, m, context)
    else
        port = CreateObject("roMessagePort")
        req.SetPort(port)
        req.AsyncGetToString()

        event = wait(10000, port)
        m.ProcessAccountResponse(event)
    end if

    return m.IsSignedIn
End Function

Sub mpOnUrlEvent(msg, requestContext)
    if requestContext.requestType = "account" then
        m.ProcessAccountResponse(msg)
        AppManager().ClearInitializer("myplex")
    end if
End Sub

Sub mpProcessAccountResponse(event)
    if type(event) = "roUrlEvent" AND event.GetInt() = 1 AND event.GetResponseCode() = 200 then
        xml = CreateObject("roXMLElement")
        xml.Parse(event.GetString())
        m.Id = xml@id
        m.Username = xml@username
        m.EmailAddress = xml@email
        m.Title = xml@title
        m.IsSignedIn = true
        m.AuthToken = xml@authenticationToken
        m.IsPlexPass = (xml.subscription <> invalid AND xml.subscription@active = "1")
        m.IsRestricted = (xml@restricted = "1")
        m.HasQueue = (xml@queueEmail <> invalid and xml@queueEmail <> "" and xml@queueEmail <> invalid and xml@queueEmail <> "")
        m.Protected = false
        m.Admin = false

        Debug("Validated myPlex token, corresponds to " + tostr(m.Id) + ":" + tostr(m.Title))
        Debug("PlexPass: " + tostr(m.IsPlexPass))
        Debug("Restricted: " + tostr(m.IsRestricted))

        m.Publish()

        ' update the list of users in the home
        m.UpdateHomeUsers()

        ' set admin attribute for the user
        if m.homeUsers.count() > 0 then
            for each user in m.homeUsers
                if m.id = user.id then
                    m.Admin = (tostr(user.admin) = "1")
                    exit for
                end if
            end for
        end if

        ' reset the current admin state
        GetGlobalAA().AddReplace("IsAdmin", m.Admin)

        ' cache the current user for offline mode
        RegWrite("AuthToken", xml@authenticationToken, "myplex")
        RegWrite("Title", m.Title, "user_cache")
        RegWrite("Id", m.Id, "user_cache")
        RegWrite("IsRestricted", tostr(m.IsRestricted), "user_cache")
        RegWrite("Admin", tostr(m.Admin), "user_cache")

        ' cache/remove PIN for offline mode
        if xml@pin <> invalid and xml@pin <> "" then
            RegWrite("Pin", xml@pin, "user_cache")
        else
            RegDelete("Pin", "user_cache")
        end if
        m.Protected = (RegRead("Pin", "user_cache") <> invalid)

        ' reset registry user
        RegInitializeUser()
    else
        if type(event) = "roUrlEvent" AND event.GetInt() = 1 then
            responseCode = tostr(event.GetResponseCode())
        else
            responseCode = "unknown"
        end if

        Debug("Failed to validate myPlex token: ResponseCode=" + responseCode)
        if val(responseCode) >= 400 and val(responseCode) < 500 then
            m.Disconnect()

            ' Set the reauth flag and a dialog to continue or cancel reauth
            MyPlexManager().reauth = true
            dlg = createBaseDialog()
            dlg.Title = "Please sign in again. Your credentials have expired."
            dlg.Text = " "
            dlg.SetButton("sign_in", "Sign In")
            dlg.SetButton("ignore", "Ignore")
            dlg.HandleButton = mpDialogHandleButton
            dlg.Show(true)
        else
            m.SetOffline()
        end if
    end if
End Sub

Sub mpPublish()
    context = CreateObject("roAssociativeArray")
    context.requestType = "publish"

    url = "/devices/" + GetGlobal("rokuUniqueID")
    device = CreateObject("roDeviceInfo")
    addrs = device.GetIPAddrs()
    first = true
    for each iface in addrs
        if first then
            first = false
            url = url + "?"
        else
            url = url + "&"
        end if
        url = url + HttpEncode("Connection[][uri]") + "=" + HttpEncode("http://" + addrs[iface] + ":8324")
    end for

    req = m.CreateRequest("", url)
    GetViewController().StartRequest(req, m, context, "_method=PUT")
End Sub

Function mpCreateRequest(sourceUrl As String, path As String, appendToken=true As Boolean, connectionUrl=invalid) As Object
    url = FullUrl(m.serverUrl, sourceUrl, path)
    req = CreateURLTransferObject(url)
    if appendToken AND m.AuthToken <> invalid then
        if Instr(1, url, "?") > 0 then
            req.SetUrl(url + "&auth_token=" + m.AuthToken)
        else
            req.SetUrl(url + "?auth_token=" + m.AuthToken)
        end if
    end if
    for each name in m.ExtraHeaders
        req.AddHeader(name, m.ExtraHeaders[name])
    next
    req.AddHeader("Accept", "application/xml")
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    return req
End Function

Sub mpDisconnect()
    Debug("Disconnect Plex Account")

    RegDelete("AuthToken", "myplex")
    ' remove all auth tokens for any server
    RegDeleteSection("server_tokens")
    RegDeleteSection("user_cache")
    ' reset the current admin state
    GetGlobalAA().AddReplace("IsAdmin", true)

    ' reset the MyPlexManager singleton
    GetGlobalAA().Delete("MyPlexManager")
    MyPlexManager()

    ' reset registry user
    RegInitializeUser()
End Sub

Function mpCheckTranscodeServer(showError=false As Boolean) As Boolean
    if m.TranscodeServer = invalid then
        m.TranscodeServer = GetPrimaryServer()
    end if

    if m.TranscodeServer = invalid then
        if showError then
            dlg = createBaseDialog()
            dlg.Title = "Unsupported Content"
            dlg.Text = "Your Roku needs a bit of help to play this. This video is in a format that your Roku doesn't understand. To play it, you need to connect to your Plex Media Server, which can convert it in real time to a more friendly format. To learn more and install Plex Media Server, visit https://plex.tv/downloads"
            dlg.Show(true)
        end if
        Debug("myPlex operation failed due to lack of primary server")
        return false
    else
        m.SupportsVideoTranscoding = m.TranscodeServer.SupportsVideoTranscoding
    end if

    return true
End Function

Function mpTranscodingVideoUrl(videoUrl As String, item As Object, httpHeaders As Object, seekValue=0)
    if NOT m.CheckTranscodeServer(true) then return invalid

    return m.TranscodeServer.TranscodingVideoUrl(videoUrl, item, httpHeaders, seekValue)
End Function

Function mpTranscodedImage(queryUrl, imagePath, width, height) As String
    if Left(imagePath, 5) = "https" then
        imagePath = "http" +  Mid(imagePath, 6, len(imagePath) - 5)
    end if

    if m.CheckTranscodeServer() then
        return m.TranscodeServer.TranscodedImage(queryUrl, imagePath, width, height)
    else if Left(imagePath, 4) = "http" then
        return imagePath
    else
        Debug("Don't know how to transcode image: " + tostr(queryUrl) + ", " + tostr(imagePath))
        return ""
    end if
End Function

Sub mpDelete(id)
    if id <> invalid then
        commandUrl = m.serverUrl + "/pms/playlists/queue/items/" + id
        Debug("Executing delete command: " + commandUrl)
        request = m.CreateRequest("", commandUrl)
        request.PostFromString("_method=DELETE")
    end if
End Sub

Function mpExecuteCommand(commandPath)
    commandUrl = m.serverUrl + "/pms" + commandPath
    Debug("Executing command with full command URL: " + commandUrl)
    request = m.CreateRequest("", commandUrl)
    request.AsyncGetToString()

    GetGlobalAA().AddReplace("async_command", request)
End Function

Function mpExecutePostCommand(commandPath)
    commandUrl = m.serverUrl + "/pms" + commandPath
    Debug("Executing POST command with full command URL: " + commandUrl)
    request = m.CreateRequest("", commandUrl)
    request.AsyncPostFromString("")

    GetGlobalAA().AddReplace("async_command", request)
End Function

Function mpGetQueryResponse(sourceUrl, key) As Object
    xmlResult = CreateObject("roAssociativeArray")
    xmlResult.server = m
    httpRequest = m.CreateRequest(sourceUrl, key)
    Debug("Fetching content from server at query URL: " + tostr(httpRequest.GetUrl()))
    response = GetToStringWithTimeout(httpRequest, 60)
    xml=CreateObject("roXMLElement")
    if not xml.Parse(response) then
        Debug("Can't parse feed: " + tostr(response))
    endif

    xmlResult.xml = xml
    xmlResult.sourceUrl = httpRequest.GetUrl()

    return xmlResult
End Function

Sub mpLog(msg="", level=3, timeout=0)
    ' Noop, only defined to implement PlexMediaServer "interface"
End Sub

sub mpUpdateHomeUsers()
    ' ignore request and clear any home users we are not signed in
    if m.IsSignedIn = false then
        m.homeUsers.clear()
        if m.IsOffline then
            m.homeUsers.push(MyPlexManager())
        end if
        return
    end if

    req = m.CreateRequest("", "/api/home/users")
    port = CreateObject("roMessagePort")
    req.SetPort(port)
    req.AsyncGetToString()

    event = wait(10000, port)
    if type(event) = "roUrlEvent" and event.GetInt() = 1 and event.GetResponseCode() = 200 then
        xml = CreateObject("roXMLElement")
        xml.Parse(event.GetString())
        m.homeUsers.clear()
        if firstOf(xml@size, "0").toInt() and xml.user <> invalid then
            for each user in xml.user
                m.homeUsers.push(user.GetAttributes())
            end for
        end if
    end if

    Debug("home users total: " + tostr(m.homeUsers.count()))
end sub

function mpSwitchHomeUser(userId as string, pin="" as dynamic) as boolean
    result = false

    if m.IsOffline then
        if createDigest(pin + m.AuthToken, "sha256") = firstOf(RegRead("Pin", "user_cache"), "") then
            Debug("Offline PIN accepted")
            m.PinAuthenticated = true
            result = true
        end if
    else
        ' build path and post to myplex to swith the user
        path = "/api/home/users/" + userid + "/switch"
        req = m.CreateRequest("", path)
        port = CreateObject("roMessagePort")
        req.SetPort(port)
        req.AsyncPostFromString("pin=" + pin)

        event = wait(10000, port)

        if type(event) = "roUrlEvent" and event.GetInt() = 1 then
            xml = CreateObject("roXMLElement")
            xml.Parse(event.GetString())
            if xml@authenticationToken <> invalid and m.ValidateToken(xml@authenticationToken, false) then
                ' remove all auth tokens for any server
                RegDeleteSection("server_tokens")
                result = true
            end if
        end if
    end if

    if result then
        if m.Protected then m.PinAuthenticated = true
        m.switchSuccess = true

        ' refresh the home screen if it exists
        home = GetViewController().home
        if home <> invalid then
            home.Refresh({ myplex: "connected", servers: true, switchUser: true })
        end if
    end if

    return result
end function

sub mpSetOffline()
    m.IsSignedIn = false

    ' set a couple variables needed for offline mode
    m.AuthToken = RegRead("AuthToken", "myplex")
    if m.AuthToken = invalid then return

    Debug("Setting plex account in offline mode")
    m.IsOffline = true
    m.Id = RegRead("Id", "user_cache")
    m.Title = RegRead("Title", "user_cache")
    m.Protected = (RegRead("Pin", "user_cache") <> invalid)
    m.IsRestricted = (RegRead("IsRestricted", "user_cache", "false") = "true")
    m.Admin = (RegRead("Admin", "user_cache", "false") = "true")
    GetGlobalAA().AddReplace("IsAdmin", m.Admin)

    ' reset registry user
    RegInitializeUser()
end sub

Function mpDialogHandleButton(command, data) As Boolean
    if command <> "sign_in" then MyPlexManager().reauth = false
    return true
End Function
