import Coffee from "coffeescript"
import * as cheerio from "cheerio"
import * as Fn from "@dashkite/joy"
import M from "@dashkite/masonry"

coffee = ( code ) ->
  Coffee.compile code,
    bare: true
    inlineMap: true

inject = ({ html, events, module }) ->
  $ = cheerio.load html
  if ( $ "script[name='env']").length == 0
    $ "head"
      .append do ->
        # TODO put this in a module
        $ "<script name='env' type='module'>"
          .text coffee """
            import Reload from "@dashkite/reload"
            Reload.listen
              domain: "#{ events }"
              module: "#{ module }"
            """
  $.html()

build = ({ events }) ->
  ({ module, input }) ->
    inject 
      html: input
      module: module.name
      events: events

changed = ( f ) ->
  do ( cache = {} ) ->
    ( context ) ->  
      if cache[ context.source.path ] != context.input
        _context = await f context
        cache[ context.source.path ] = _context.output
        _context

export default ( Genie, options ) ->

  if options.reload?

    target = options.reload.target ?
      "build/browser/src/index.html"

    Genie.define "sky:reload", ->

      W = await import( "@dashkite/masonry-watch" )
      { Module } = await import( "@dashkite/masonry-module" )
  
      do M.start [
        M.glob target
        M.read
        Module.data
        M.tr build options.reload
        M.write "."
      ]

    Genie.after "build", "sky:reload"

    Genie.define "sky:reload:watch", ->

      W = await import( "@dashkite/masonry-watch" )
      { Module } = await import( "@dashkite/masonry-module" )

      do M.start [
        W.glob glob: target
        M.read
        changed Fn.flow [
          Module.data
          M.tr build options.reload
          M.write "."
        ]
      ]
    
    Genie.on "watch", "sky:reload:watch&"
