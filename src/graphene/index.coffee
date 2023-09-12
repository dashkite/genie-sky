export default ( Genie, options ) ->
  
  Tasks = undefined
  
  run = ( task ) -> ->

    Tasks ?= await import("./tasks")
    Tasks[ task ] Genie, options

  Genie.on "deploy", "sky:graphene:deploy"
  Genie.on "undeploy", "sky:graphene:undeploy"
  Genie.on "publish", "sky:graphene:publish"

  Genie.define "sky:graphene:deploy", 
    "build",
    run "deploy"

  Genie.define "sky:graphene:publish", 
    "sky:graphene:deploy", 
    run "publish"


  Genie.define "sky:graphene:undeploy", run "undeploy"
