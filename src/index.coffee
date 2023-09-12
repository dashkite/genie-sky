Presets = {
  zip: -> import( "./zip" )
  secrets: -> import( "./secrets" )
  role: -> import( "./role" )
  lambda: -> import( "./lambda" )
  alb: -> import( "./alb" )
  edge: -> import( "./edge" )
  bridge: -> import( "./bridge" )
  "step-function": -> import( "./step-function" )
  buckets: -> import( "./buckets" )
  tables: -> import( "./tables" )
  cloudfront: -> import( "./cloudfront" )
  graphene: -> import( "./graphene" )
  queues: -> import( "./queues" )
  ses: -> import( "./ses" )
  schema: -> import( "./schema" )
}

export default (genie) ->
  
  genie.define "sky:clean", -> 
    Logger = await import( "@dashkite/dolores/logger" )
    Logger.clean()
  
  genie.on "clean", "sky:clean"
  
  genie.define "sky:env", ->
    { Mixins } = await import( "@dashkite/drn" )
    options = genie.get "sky"
    { mixins } = options
    options.env = mode: process.env.mode ? "development"
    if mixins?
      options.env.context = await Mixins.apply mixins, genie
  
  genie.before "pug", "sky:env"
  
  if (options = genie.get "sky")?
    Promise.all do ->
      for name in Object.keys options
        if ( loader = Presets[ name ])?
          do ( name ) ->
            installer = await loader()
            installer.default genie, options

