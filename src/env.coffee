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

inject = ( html, module, env ) ->
  json = JSON.stringify env, null, 2
  $ = cheerio.load html
  $ "head"
    .append do ->
      $ "<script type='module'>"
        .text coffee """
          import Registry from "@dashkite/helium"
          Registry.set #{ json }

          do ({ response } = {}) ->
            loop
              response = await fetch "/.events"
              events = await response.json()
              console.log events
              for event in events
                if ( event.content.module == "#{ module }" )
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
    inject input, module.name, sky: env: { mode, dictionary }

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
