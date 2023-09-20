export default ( genie ) ->
  
  genie.define "sky:clean", -> 
    Logger = await import( "@dashkite/dolores/logger" )
    Logger.clean()
  
  genie.on "clean", "sky:clean"
