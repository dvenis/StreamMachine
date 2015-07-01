FileSource = require "../sources/file"
fs = require "fs"
net = require "net"

debug = require("debug")("sm:IcecastSource")

module.exports = class IcecastSource extends require("events").EventEmitter
    constructor: (@opts) ->
        @_connected = false
        @sock = null


        console.log "using playlist source"

        @playlistPath = @opts.filePath
        @generatePlaylist()

        @currentSong = 0
        @startCurrentSong()

    #----------

    startCurrentSong: ->

      filePath = @songs[@currentSong]
      console.log "PS: starting to stream #{filePath}"
      @fsource = new FileSource format:@opts.format, filePath:filePath, chunkDuration:0.2, shouldLoop:false

      @fsource.on "data", (chunk) =>
          @sock?.write chunk.data

      @fsource.on "done", =>
        @currentSong += 1
        @currentSong = 0 if @currentSong >= @songs.length
        @startCurrentSong()





    generatePlaylist: ->
      playlist = fs.readFileSync @playlistPath, 'utf8'
      @songs = (x.replace("\r", "") for x in playlist.split("\n"))

    #----------

    start: (cb) ->
        sFunc = =>
            @fsource.start()
            cb? null

        if @sock
            sFunc()
        else
            @_connect (err) =>
                return cb err if err
                @_connected = true
                sFunc()

    #----------

    pause: ->
        @fsource.stop()

    #----------

    _connect: (cb) ->
        # -- Open our connection to the server -- #

        @sock = net.connect @opts.port, @opts.host, =>
            debug "Connected!"

            authTimeout = null

            # we really only care about the first thing we see
            @sock.once "readable", =>
                resp = @sock.read()

                if /^HTTP\/1\.0 200 OK/.test(resp.toString())
                    debug "Got HTTP OK. Starting streaming."
                    clearTimeout authTimeout
                    cb null

                else
                    err = "Unknown response: #{ resp.toString() }"
                    debug err
                    cb err
                    @disconnect()

            @sock.write "SOURCE /#{@opts.stream} HTTP/1.0\r\n"

            #@sock.write "User-Agent: StreamMachine IcecastSource"

            if @opts.password
                # username doesn't matter.
                auth = new Buffer("source:#{@opts.password}",'ascii').toString("base64")
                @sock.write "Authorization: Basic #{auth}\r\n\r\n"
                debug "Writing auth with #{ auth }."

            else
                @sock.write "\r\n"

            authTimeout = setTimeout =>
                err = "Timed out waiting for authentication."
                debug err
                cb err
                @disconnect()
            , 5000

        @sock.once "error", (err) =>
            debug "Socket error: #{err}"
            @disconnect()

    #----------

    disconnect: ->
        @_connected = false
        @sock.end()
        @sock = null
        @emit "disconnect"
