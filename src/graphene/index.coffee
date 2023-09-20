import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->

  Tasks = undefined
  
  Genie.on "deploy", "sky:graphene:deploy"
  Genie.on "undeploy", "sky:graphene:undeploy"
  Genie.on "publish", "sky:graphene:publish"

  Genie.define "sky:graphene:deploy", 
    run "deploy", options

  Genie.define "sky:graphene:publish", 
    "sky:graphene:deploy", 
    run "publish", options


  Genie.define "sky:graphene:undeploy",
    run "undeploy", options
