Tasks = undefined

run = ( task ) -> ->
  Tasks ?= await import("./tasks")
  Tasks[ task ] Genie, options

export default ( Genie, options ) ->

  Genie.on "deploy", "sky:s3:deploy"
  Genie.on "publish", "sky:s3:publish"

  Genie.define "sky:s3:deploy", run "deploy"
  Genie.define "sky:s3:undeploy", run "undeploy"
  genie.define "sky:s3:publish", "sky:s3:deploy", run "publish"
