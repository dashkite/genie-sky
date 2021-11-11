import zip from "./zip"
import secrets from "./secrets"
import lambda from "./lambda"
import alb from "./alb"

export default (genie) ->
  if (options = genie.get "sky")?
    zip genie, options
    secrets genie, options
    lambda genie, options
    alb genie, options
