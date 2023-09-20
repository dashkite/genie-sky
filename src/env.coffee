export default ( Genie ) ->

  Genie.define "sky:env", ->
    { Mixins } = await import( "@dashkite/drn" )
    options = Genie.get "sky"
    { mixins } = options
    options.env = mode: process.env.mode ? "development"
    if mixins?
      options.env.context = await Mixins.apply mixins
  
  Genie.before "pug", "sky:env"
    
