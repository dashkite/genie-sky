import * as Fn from "@dashkite/joy"
import * as cheerio from "cheerio"
import * as DRN from "@dashkite/drn-sky"
import M from "@dashkite/masonry"
import W from "@dashkite/masonry-targets/watch"

inject = ( html, env ) ->
  json = JSON.stringify env, null, 2
  $ = cheerio.load html
  $ "head"
    .append do ->
      $ "<script type='module'>"
        .text """
          import Registry from "@dashkite/helium"
          Registry.set(#{ json });
          """
  $.html()

build = ( options ) ->
  ({ input }) ->
    mode = process.env.mode ? "development"
    dictionary = {}
    if options.env?.drn?
      for drn in options.env.drn
        dictionary[ drn ] = await DRN.resolve drn
    inject input, sky: env: { mode, dictionary }

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
        M.tr build options
        M.write "."
      ]
    ]
    
    Genie.on "watch", "sky:env:watch&"
