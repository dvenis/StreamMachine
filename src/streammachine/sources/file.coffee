fs = require "fs"
_ = require "underscore"

# FileSource emulates a stream source by reading a local audio file. The shouldLoop
# option can be set to cause the file to loop. Otherwise, the stream will
# automatically stop and disconnect at the end of the song.

module.exports = class FileSource extends require("./base")
    TYPE: -> "File (#{@opts.filePath})"

    constructor: (@opts) ->
        super()

        @connected = false
        @looping = @opts.shouldLoop

        @_file = null

        @_chunks = []

        @_emit_pos  = 0
        @_last_ts   = Number(@opts.ts) || null

        @start() if !@opts.do_not_emit

        @on "_chunk", (chunk) =>
            @_chunks.push chunk

        @parser.once "header", (header) =>
            @connected = true
            @emit "connect"

        @parser.once "end", =>
            # done parsing...
            @parser.removeAllListeners()
            @_current_chunk = null
            @emit "_loaded"

        # pipe our file into the parser
        @_file = fs.createReadStream @opts.filePath
        @_file.pipe(@parser)

    #----------

    start: ->
        return true if @_int

        @_int = setInterval =>
            @_emitOnce()
        , @emitDuration * 1000

        @_emitOnce()

        true

    #----------

    stop: ->
        return true if !@_int

        clearInterval @_int
        @_int = null

        true

    #----------

    # emit a certain length of time. useful for filling a buffer
    emitSeconds: (secs,cb) ->
        emits = Math.ceil(secs / @emitDuration)
        count = 0

        _f = =>
            @_emitOnce()
            count += 1

            if count < emits
                process.nextTick => _f()
            else
                cb()

        _f()

    #----------

    _emitOnce: (ts=null) ->
        #if the audio file should be looped and we're at the end of all the chunks
        if @looping is false and @_emit_pos >= @_chunks.length and @_chunks.length > 0
          @emit "done",
            ts:         new Date(ts)
            streamKey:  @streamKey
            uuid:       @uuid
          @stop()
          @disconnect()
          return

        @_emit_pos = 0 if @_emit_pos >= @_chunks.length

        chunk = @_chunks[ @_emit_pos ]

        return if !chunk

        console.log "NO DATA!!!! ", chunk if !chunk.data

        ts = if @_last_ts then @_last_ts + chunk.duration else Number(new Date())

        @emit "data",
            data:       chunk.data
            ts:         new Date(ts)
            duration:   chunk.duration
            streamKey:  @streamKey
            uuid:       @uuid

        @_last_ts   = ts
        @_emit_pos  = @_emit_pos + 1

    #----------

    info: ->
        source:     @TYPE?() ? @TYPE
        uuid:       @uuid
        filePath:   @filePath

    #----------

    disconnect: ->
        if @connected
            @connected = false
            @emit "disconnect"
            clearInterval @_int
