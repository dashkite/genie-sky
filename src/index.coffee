import zip from "./zip"
import secrets from "./secrets"
import publish from "./publish"

export default (genie) ->
  if (presets = genie.get "sky")?
    zip genie, presets.zip
    secrets genie, presets.secrets
    publish genie, presets.publish
