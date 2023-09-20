import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default

  import: [
    "role"
    "zip"
  ]

  install: ( Genie, options ) ->

    Genie.on "deploy", "sky:lambda:deploy"

    Genie.on "undeploy", "sky:lambda:undeploy"
    
    Genie.define "sky:lambda:handlers", 
      run "handlers", options

    Genie.define "sky:lambda:deploy",
      [ 
        "clean"
        "sky:roles:deploy"
        "sky:lambda:handlers"
        "build"
        "sky:zip" 
      ], run "deploy", Genie, options

    Genie.define "sky:lambda:version", 
      run "version", options

    Genie.define "sky:lambda:undeploy", 
      run "undeploy", options