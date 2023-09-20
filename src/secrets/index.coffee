import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

export default ( Genie, options ) ->


  # verify that all secrets in config exist
  Genie.define "sky:secrets:check", run "check", options

  # ensures all secrets in config exist, 
  # generating missing secrets
  Genie.define "sky:secrets:put", run "putAll", options

  # update a specific secret, creating the secret
  # if it doesn't exist already - useful for rotation
  Genie.define "sky:secret:put", run "put", options

  # TODO maybe remove this later?
  Genie.define "sky:secret:get", run "get", options

  Genie.define "sky:secret:delete", run "delete", options

  # TODO temporary key rotation task to update key in WAF
  # See: https://github.com/dashkite/sky-alb/issues/1



