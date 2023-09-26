import * as cheerio from "cheerio"
import * as DRN from "@dashkite/drn-sky"
import M from "@dashkite/masonry"

inject = ( html, env ) ->
  json = JSON.stringify env, null, 2
  $ = cheerio.load html
  $ "head"
    .append do ->
      $ "<script type='module'>"
        .text """
          import Registry from "@dashkite/helium"
          Registry.set #{ json }
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
      
export default ( Genie ) ->

  options = Genie.get "sky"
  
  target = options.env.target ?
    "build/browser/src/index.html"

  Genie.define "sky:env", M.start [
      M.glob target, "."
      M.read
      M.tr build options
      M.write "."
    ]

  Genie.after "build", "sky:env"