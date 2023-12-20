import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default

  import: [
    "role"
    "zip"
  ]

  install: ( Genie, options ) ->

    if options.lambda?.handlers?
      console.warn "[ lambda.handlers ] defined in genie.yaml:
        do you need to update your configuration?"

    Genie.on "deploy", "sky:lambda:deploy"

    if !options.edge?
      Genie.on "undeploy", "sky:lambda:undeploy"
    
    Genie.on "tail", "sky:lambda:tail"

    Genie.define "sky:lambda:handlers", 
      run "handlers", options

    Genie.define "sky:lambda:deploy",
      [ 
        "clean"
        "sky:roles:deploy"
        "sky:lambda:handlers"
        "build"
        "sky:zip" 
      ], run "deploy", options

    Genie.define "sky:lambda:version",
      run "version", options

    Genie.define "sky:lambda:version-all",
      "sky:lambda:deploy",
      run "versionAll", options

    Genie.define "sky:lambda:undeploy", 
      run "undeploy", options

    Genie.define "sky:lambda:tail", 
      run "tail", options