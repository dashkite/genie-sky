import Coffee from "coffeescript"
import * as cheerio from "cheerio"
import * as Fn from "@dashkite/joy"
import * as DRN from "@dashkite/drn-sky"
import M from "@dashkite/masonry"
import W from "@dashkite/masonry-watch"
import { Module } from "@dashkite/masonry-module"

coffee = ( code ) ->
  Coffee.compile code,
    bare: true
    inlineMap: true

inject = ({ html, module, env }) ->
  json = JSON.stringify env, null, 2
  $ = cheerio.load html
  if ( $ "script[name='env']").length == 0
    $ "head"
      .append do ->
        $ "<script name='env' type='module'>"
          .text coffee """
            import Registry from "@dashkite/helium"
            Registry.set #{ json }

            do ({ get, flush, listen, event } = {}) ->
              
              get = do ({ response } = {}) -> ->
                console.log "try get"
                events = []
                try
                  # failures will already be logged
                  # so we just ignore them
                  response = await fetch "/.events"
                  events = if response.status == 200
                    await response.json()
                  else
                    console.error "unexpected status from /.events"
                    console.log { response }
                    []
                events

              flush = do ({ events } = {}) -> ->
                console.log "flush"
                until events?.length == 0
                  events = await do get
                  console.log "got events", events 

              listen = do ({ event } = {}) -> ->
                console.log "listen"
                loop
                  console.log "listening"
                  for event in await do get
                    console.log "got event", event
                    yield event

              await do flush

              for await event from do listen
                console.log { event }
                if ( event.content.module == "#{ module }" )
                  console.log "reload"
                  location.reload()

            """
  $.html()

build = ( options ) ->
  ({ module, input }) ->
    mode = process.env.mode ? "development"
    dictionary = {}
    if options.env?.drn?
      for drn in options.env.drn
        dictionary[ drn ] = await DRN.resolve drn
    inject 
      html: input
      module: module.name
      env: sky: env: { mode, drn: { dictionary }}

changed = ( f ) ->
  do ( cache = {} ) ->
    ( context ) ->  
      if cache[ context.source.path ] != context.input
        _context = await f context
        cache[ context.source.path ] = _context.output
        _context

export default ( Genie ) ->

  options = Genie.get "sky"

  if options.mixins? && options.env?
    console.warn "found [ mixins ] without [ env ] in genie.yaml:
      do you need to migrate to the [ env ] stanza?"

  if options.env?
  
    target = options.env.target ?
      "build/browser/src/index.html"

    Genie.define "sky:env", M.start [
      M.glob target
      M.read
      Module.data
      M.tr build options
      M.write "."
    ]

    Genie.after "build", "sky:env"

    Genie.define "sky:env:watch", M.start [
      W.glob glob: target
      M.read
      changed Fn.flow [
        Module.data
        M.tr build options
        M.write "."
      ]
    ]
    
    Genie.on "watch", "sky:env:watch&"
