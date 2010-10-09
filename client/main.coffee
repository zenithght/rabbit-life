root = this
client = (obj) -> new wrapper(obj)
root.client = client

log = (args...) ->
    if console? and console.log?
        console.log(args...)

init = () ->
    app.run("#/")

state = {
    uuid: null
    nick: null
    colour: null
    registered: false
}

definition = () ->
    this.use(Sammy.EJS);
    this.debug = true

    dirty_cells = []

    this.bind "run", () ->
        log("init")
        context = this
        state.uuid = uuid()

        MQ.configure {
            logger: console,
            host: "0.0.0.0",
            port: 5777
        }
        MQ.on "load", () ->
            log("Loaded")
        MQ.on "connect", () ->
            log("Connected")
        MQ.on "disconnect", () ->
            log("Disconnected")
        MQ.topic("life")
        MQ.queue("auto").callback (m) ->
            log("Error: no binding matches", m)
        MQ.queue("auto").bind("life", "life.board.update").callback (m) ->
            context.trigger("update-board", m)
        MQ.queue("auto").bind("life", "life.players.update").callback (m) ->
            context.trigger("update-players", m)

        swfobject.embedSWF(
            "vendor/amqp-js/swfs/amqp.swf?nc=" + Math.random().toString(),
            "AMQPProxy",
            "1",
            "1",
            "9",
            "vendor/amqp-js/swfs/expressInstall.swf",
            {},
            {
                allowScriptAccess: "always",
                wmode: "transparent"
            },
            {},
            () ->
                log("Swfobject loaded")
        )

    this.get "#/", () ->
        log("processing GET #/")
        this.render "launch.ejs", {}, (rendered) ->
            this.event_context.swap(rendered)

    this.post "#/register", () ->
        log("processing POST #/register", this.params)
        this.swap("Registering nick...")
        # TODO register nick with server?
        this.swap("Reticulating splines...")
        MQ.exchange("life").publish({ uuid: state.uuid, nick: this.params.nick, colour: this.params.colour }, "life.register")
        # TODO move to reps from reg req
        state.registered = true
        state.nick = this.params.nick
        state.colour = this.params.colour
        this.redirect("#/game")

    this.get "#/game", () ->
        log("processing GET #/game")

        if (!state.registered)
            log("not logged in -- redirecting to /")
            this.redirect("#/")
            return

        this.render "game.ejs", { width: 200, height: 200, patterns: patterns, nick: state.nick, colour: state.colour }, (rendered) ->
            log("game rendered")
            this.event_context.swap(rendered)
            $(".pattern").draggable({ revert: "invalid", opacity: 0.5, snap: ".cell", helper: "clone" })
            $("#board-container").droppable({
                drop: (e, ui) ->
                    id = ui.draggable[0].id
                    boardPos = $(this).offset()
                    dropPos = ui.offset
                    x = Math.round((dropPos.left - boardPos.left) / 5.0)
                    y = Math.round((dropPos.top - boardPos.top) / 5.0)
                    s = pattern_map[id]
                    log("dropped", id, x, y, s)
                    cells = []
                    for dy in [0...s.height]
                        for dx in [0...s.width] when s.grid[dy][dx]
                            cells.push({x: x + dx, y: y + dy, c: $("#colour").attr("value")})
                    MQ.exchange("life").publish({ cells: cells }, "life.board.add")
            })
            $("#colour").change(() ->
                c = $("#colour").attr("value")
                $(".cell-on").css("background-color", c))

    this.bind "update-board", (e, m) ->
        log("board update")
        start = (new Date()).getTime()

        # TODO optimize update by only modifying the cells that changed colour?

        # clear board
        for c in dirty_cells
            $("#cell_" + c.x + "_" + c.y).css("background", "#ffffff")

        # set cells that came back from the server
        cells = m.data.board.cells
        for c in cells
            $("#cell_" + c.x + "_" + c.y).css("background", c.c)
        dirty_cells = cells

        diff = (new Date()).getTime() - start
        log("update took: ", diff)

    this.bind "update-players", (e, m) ->
        log("player list update")
        start = (new Date()).getTime()

        console.log(m)

        diff = (new Date()).getTime() - start
        log("update took: ", diff)

uuid = () ->
    # http://stackoverflow.com/questions/105034/how-to-create-a-guid-uuid-in-javascript
    # http://www.ietf.org/rfc/rfc4122.txt
    s = []
    hexDigits = "0123456789ABCDEF"
    for i in [1...32]
        s[i] = hexDigits.substr(Math.floor(Math.random() * 0x10), 1)
    s[12] = "4" # bits 12-15 of the time_hi_and_version field to 0010
    s[16] = hexDigits.substr((s[16] & 0x3) | 0x8, 1) # bits 6-7 of the clock_seq_hi_and_reserved to 01
    s.join("")

app = $.sammy("#root", definition)

client.init = init
